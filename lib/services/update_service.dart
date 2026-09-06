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

  // Pop-up Obrigatório (Bloqueia o ecrã até atualizar)
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
                'Existe uma nova versão obrigatória. A aplicação vai proceder à transferência e instalação automática.',
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
                _downloadAndInstallAutomatically(context, apkUrl, newVersion);
              },
              child: const Text('Atualizar Automaticamente',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Faz o download direto seguindo redirecionamentos do GitHub e força a instalação
  static Future<void> _downloadAndInstallAutomatically(
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
                child: Text('A descarregar atualização em segundo plano...'),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      var client = http.Client();
      var request = http.Request('GET', Uri.parse(url));
      var streamedResponse = await client.send(request);

      if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 302) {
        final response = await http.Response.fromStream(streamedResponse);
        
        Directory? targetDir;
        if (Platform.isAndroid) {
          targetDir = await getExternalStorageDirectory();
        }
        targetDir ??= await getTemporaryDirectory();

        final filePath = '${targetDir.path}/app_motorista_v$version.apk';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        if (context.mounted) {
          Navigator.pop(context); // Fecha o pop-up de loading
        }

        final result = await OpenFilex.open(filePath);

        if (result.type != ResultType.done && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Por favor, permita a instalação nas definições: ${result.message}'),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Falha ao comunicar com o servidor de atualizações.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no processo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}