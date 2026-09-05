import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // Versão atual instalada na aplicação
  static const String currentVersion = '1.0.7';

  // URL corrigido no GitHub (Raw)
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
            'Melhorias de estabilidade e novas funcionalidades.';

        if (_isNewerVersion(currentVersion, latestVersion)) {
          if (context.mounted) {
            _showUpdateDialog(context, latestVersion, apkUrl, releaseNotes);
          }
        } else if (showNoUpdateMessage && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A sua aplicação já se encontra na versão mais recente!'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } else {
        if (showNoUpdateMessage && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Erro ao verificar atualizações (Código HTTP: ${response.statusCode}).'),
              backgroundColor: Colors.orange[800],
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

  // Compara versões semânticas (ex: 1.0.5 vs 1.0.6)
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

  static void _showUpdateDialog(BuildContext context, String newVersion,
      String apkUrl, String notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.teal),
            const SizedBox(width: 8),
            Text('Nova Versão Disponível (v$newVersion)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versão instalada: v$currentVersion',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Novidades:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(notes, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mais Tarde'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _downloadAndInstallApk(context, apkUrl, newVersion);
            },
            child: const Text('Atualizar Agora'),
          ),
        ],
      ),
    );
  }

  static Future<void> _downloadAndInstallApk(
      BuildContext context, String url, String version) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A descarregar a nova versão... Aguarde um momento.'),
          duration: Duration(seconds: 4),
          backgroundColor: Colors.blueGrey,
        ),
      );

      final response = await http.get(Uri.parse(url));
      
      // Valida se a resposta foi bem-sucedida e se o ficheiro tem tamanho de APK (> 1MB)
      if (response.statusCode == 200 && response.bodyBytes.length > 1000000) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/app_motorista_v$version.apk');
        await file.writeAsBytes(response.bodyBytes);

        final result = await OpenFilex.open(file.path);
        
        // Se o telemóvel não conseguir abrir o instalador diretamente, abre o browser
        if (result.type != ResultType.done) {
          _openBrowserFallback(url);
        }
      } else {
        // Se falhar a descarga direta ou o link não for um APK válido, abre no browser
        _openBrowserFallback(url);
      }
    } catch (_) {
      _openBrowserFallback(url);
    }
  }

  static void _openBrowserFallback(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}