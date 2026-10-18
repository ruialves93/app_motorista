import Flutter
import UIKit
import CryptoKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.ruibarata.cctvmotorista/icloud",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      // Establishing the ubiquity container can block; never do it on the UI thread.
      self.iCloudQueue.async {
        do {
          guard let identity = try self.iCloudIdentity() else {
            DispatchQueue.main.async { result(FlutterError(
              code: "icloud_account_unavailable",
              message: "Não foi encontrada uma conta com iCloud Drive ativo. Verifique Definições > Conta Apple > iCloud > iCloud Drive.",
              details: nil
            )) }
            return
          }
          guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.ruibarata.cctvmotorista"
          ) else {
            DispatchQueue.main.async { result(FlutterError(
              code: "icloud_container_unavailable",
              message: "A conta iCloud foi encontrada, mas o iOS não disponibilizou a pasta da aplicação. Pode faltar a configuração iCloud desta versão ou o serviço ainda não estar disponível no simulador.",
              details: nil
            )) }
            return
          }
          if call.method == "account" {
            DispatchQueue.main.async { result(identity) }
            return
          }
          guard let arguments = call.arguments as? [String: Any],
                arguments["account"] as? String == identity else {
            throw NSError(domain: "iCloud", code: 1, userInfo: [
              NSLocalizedDescriptionKey: "A conta iCloud mudou. Tente novamente."
            ])
          }
          let directory = container.appendingPathComponent("Documents", isDirectory: true)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let file = directory.appendingPathComponent("CCTV_Motorista_Backup.json")
          if call.method == "status" {
            var status: [String: Any] = ["exists": FileManager.default.fileExists(atPath: file.path)]
            if FileManager.default.fileExists(atPath: file.path) {
              let values = try file.resourceValues(forKeys: [
                .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
                .ubiquitousItemUploadingErrorKey, .isUbiquitousItemKey
              ])
              status["uploaded"] = values.ubiquitousItemIsUploaded ?? false
              status["uploading"] = values.ubiquitousItemIsUploading ?? false
              status["ubiquitous"] = values.isUbiquitousItem ?? false
              if let error = values.ubiquitousItemUploadingError {
                status["error"] = error.localizedDescription
              }
            }
            let response = status
            DispatchQueue.main.async { result(response) }
            return
          }
          let coordinator = NSFileCoordinator(filePresenter: nil)
          var coordinationError: NSError?
          var operationError: Error?
          var content: String?
          switch call.method {
          case "write":
            guard let text = arguments["content"] as? String else {
              throw NSError(domain: "iCloud", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Conteúdo da cópia inválido."
              ])
            }
            coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
              do {
                guard try self.iCloudIdentity() == identity else {
                  throw NSError(domain: "iCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "A conta iCloud mudou."])
                }
                try text.write(to: url, atomically: true, encoding: .utf8)
              } catch { operationError = error }
            }
          case "read":
            if FileManager.default.isUbiquitousItem(at: file) {
              let values = try file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
              if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                try FileManager.default.startDownloadingUbiquitousItem(at: file)
                throw NSError(domain: "iCloud", code: 3, userInfo: [
                  NSLocalizedDescriptionKey: "A cópia está a ser descarregada do iCloud. Aguarde e toque novamente em Recuperar."
                ])
              }
            }
            coordinator.coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
              do {
                guard try self.iCloudIdentity() == identity else {
                  throw NSError(domain: "iCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "A conta iCloud mudou."])
                }
                if FileManager.default.fileExists(atPath: url.path) {
                  content = try String(contentsOf: url, encoding: .utf8)
                }
              } catch { operationError = error }
            }
          default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
            return
          }
          if let error = coordinationError { throw error }
          if let error = operationError { throw error }
          let response = content
          DispatchQueue.main.async { result(response) }
        } catch {
          let message = error.localizedDescription
          DispatchQueue.main.async { result(FlutterError(code: "icloud_error", message: message, details: nil)) }
        }
      }
    }
  }

  private let iCloudQueue = DispatchQueue(label: "com.ruibarata.cctvmotorista.icloud", qos: .utility)

  private func iCloudIdentity() throws -> String? {
    guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
    let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
