import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String currentVersion = '1.0.9';

  static const String versionUrl =
      'https://raw.githubusercontent.com/ruialves93/app_motorista/main/version.json';

  static Future<void> checkForUpdates(BuildContext context,
      {bool showNoUpdateMessage = false}) async {
    try {
      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['version'] as String;
        final apkUrl = data['apk_url'] as String;
        final releaseNotes = data['release_notes'] as String? ??
            'Atualização obrigatória de estabilidade e segurança.';

        if (_isNewerVersion(currentVersion, latestVersion)) {
          if (context.mounted) {
            _showForcedUpdateDialog(context, latestVersion, apkUrl, releaseNotes);
          }
        } else if (showNoUpdateMessage && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A sua aplicação já se encontra na versão mais recente!'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      }
    } catch (e) {
      if (showNoUpdateMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro na ligação ao servidor: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  static bool _isNewerVersion(String current, String latest) {
    List<int> currParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> latestParts =
        latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < latestParts.length; i++) {
      int curr = i < currParts.length ? currParts[i] : 0;
      if (latestParts[i] > curr) return true;
      if (latestParts[i] < curr) return false;
    }
    return false;
  }

  // Pop-up Obrigatório (Sem opção de cancelar)
  static void _showForcedUpdateDialog(BuildContext context, String newVersion,
      String apkUrl, String notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.system_update, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('Atualização Obrigatória (v$newVersion)'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Existe uma nova versão obrigatória disponível para garantir a conformidade e estabilidade.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              const Text('Novidades:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(notes, style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 45),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                _downloadAndInstallApk(context, apkUrl, newVersion);
              },
              child: const Text('Descarregar e Atualizar Agora',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Faz o download direto e abre o instalador do APK de forma imediata
  static Future<void> _downloadAndInstallApk(
      BuildContext context, String url, String version) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text('A descarregar a atualização... Por favor aguarde.'),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200 && response.bodyBytes.length > 1000000) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/app_motorista_v$version.apk');
        await file.writeAsBytes(response.bodyBytes);

        if (context.mounted) {
          Navigator.pop(context); // Fecha o loading
        }

        // Abre o instalador do APK nativamente
        await OpenFilex.open(file.path);
      } else {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Erro ao transferir o ficheiro da atualização.'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}