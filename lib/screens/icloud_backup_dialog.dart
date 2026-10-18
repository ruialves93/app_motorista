import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/icloud_service.dart';

class ICloudBackupDialog extends StatefulWidget {
  const ICloudBackupDialog({super.key});
  @override
  State<ICloudBackupDialog> createState() => _ICloudBackupDialogState();
}

class _ICloudBackupDialogState extends State<ICloudBackupDialog> {
  bool _busy = false;
  String _message = 'Utiliza a conta iCloud das Definições do iPhone. Ative o iCloud Drive para guardar os seus registos e definições.';
  bool _error = false;

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() {
      _busy = true;
      _error = false;
      _message = 'A comunicar com o iCloud…';
    });
    try {
      await action();
      if (mounted && message.isNotEmpty) setState(() => _message = message);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = true;
          _message = error is PlatformException
              ? error.message ?? 'Não foi possível aceder ao iCloud.'
              : error.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkStatus({bool save = false}) async {
    await _run(() async {
      if (save) await ICloudService.backup();
      final status = await ICloudService.backupStatus();
      if (mounted) setState(() => _message = status);
    }, '');
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Recuperar do iCloud?'),
      content: const Text('Os registos das mesmas datas e as definições serão substituídos pelos da cópia. Os restantes dias serão mantidos.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Recuperar')),
      ],
    ));
    if (confirmed == true && mounted) {
      await _run(ICloudService.restore, 'Cópia recuperada. Feche esta janela para atualizar os registos.');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Cópia de segurança iCloud'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _error ? Colors.red.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_message, style: TextStyle(color: _error ? Colors.red.shade900 : Colors.blue.shade900)),
        ),
        const SizedBox(height: 16),
        if (_busy) const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Aguarde…')]),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : () => _checkStatus(save: true),
          icon: const Icon(Icons.cloud_upload), label: const Text('Guardar no iCloud'),
        ),
        TextButton.icon(onPressed: _busy ? null : () => _checkStatus(),
          icon: const Icon(Icons.refresh), label: const Text('Verificar envio')),
        TextButton.icon(onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.cloud_download), label: const Text('Recuperar do iCloud')),
        const Text('Guarde uma nova cópia depois de alterar os registos. A cópia anterior será substituída.',
          style: TextStyle(fontSize: 12)),
      ])),
      actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Fechar'))],
    ),
  );
}
