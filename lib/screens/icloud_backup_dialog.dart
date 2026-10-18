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
  String _message = 'Toque em Guardar em Ficheiros, escolha iCloud Drive, selecione uma pasta e confirme em Guardar. Assim pode localizar o ficheiro no iCloud Drive.';
  bool _error = false;
  bool _success = false;
  String _account = 'A verificar a conta iCloud…';

  @override
  void initState() {
    super.initState();
    _refreshAccount();
  }

  Future<void> _refreshAccount() async {
    try {
      final description = await ICloudService.accountDescription().timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _account = description);
    } catch (_) {
      if (mounted) setState(() => _account = 'Não foi possível verificar a conta iCloud.');
    }
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() {
      _busy = true;
      _error = false;
      _success = false;
      _message = 'A processar a cópia de segurança…';
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
      _refreshAccount();
    }
  }

  Future<void> _saveViaFiles() => _run(() async {
    final path = await ICloudService.saveViaFiles();
    if (mounted) {
      setState(() {
        _success = path != null;
        _message = path == null ? 'Operação cancelada. Não foi exportada uma cópia.'
            : 'Cópia de segurança exportada com sucesso para a pasta escolhida em Ficheiros. Se escolheu iCloud Drive, o iOS gere o envio. Confirme o ficheiro nessa pasta.';
      });
    }
  }, '');

  Future<void> _checkStatus({bool save = false}) async {
    await _run(() async {
      if (save) await ICloudService.backup();
      final status = await ICloudService.backupStatusDetails();
      if (mounted) {
        setState(() {
          _message = status.message;
          _success = status.confirmed;
        });
      }
    }, '');
  }

  Future<void> _restore({bool viaFiles = false}) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Recuperar do iCloud?'),
      content: const Text('Os registos das mesmas datas e as definições serão substituídos pelos da cópia. Os restantes dias serão mantidos.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Recuperar')),
      ],
    ));
    if (confirmed == true && mounted) {
      await _run(() async {
        final restored = viaFiles ? await ICloudService.restoreViaFiles() : await ICloudService.restore().then((_) => true);
        if (mounted) {
          setState(() {
            _success = restored;
            _message = restored ? 'Cópia recuperada com sucesso. Feche esta janela para atualizar os registos.'
                : 'Operação cancelada. Os registos não foram alterados.';
          });
        }
      }, '');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Cópia de segurança iCloud'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.account_circle, color: Colors.blueGrey, size: 32),
        const SizedBox(height: 8),
        Text(_account, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('O e-mail não é disponibilizado à aplicação. Consulte a conta em Definições > Conta Apple.',
          style: TextStyle(fontSize: 12)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _error ? Colors.red.shade50 : _success ? Colors.green.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Icon(_error ? Icons.error_outline : _success ? Icons.check_circle : Icons.info_outline,
              color: _error ? Colors.red : _success ? Colors.green : Colors.blue),
            const SizedBox(height: 8),
            Text(_message, style: TextStyle(color: _error ? Colors.red.shade900 : _success ? Colors.green.shade900 : Colors.blue.shade900)),
          ]),
        ),
        const SizedBox(height: 16),
        if (_busy) const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Aguarde…')]),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _saveViaFiles,
          icon: const Icon(Icons.save_alt), label: const Text('Guardar em Ficheiros'),
        ),
        TextButton.icon(onPressed: _busy ? null : () => _restore(viaFiles: true),
          icon: const Icon(Icons.folder_open), label: const Text('Recuperar de Ficheiros')),
        ExpansionTile(title: const Text('Pasta iCloud da aplicação'),
          subtitle: const Text('Requer configuração Apple da aplicação'),
          children: [
            TextButton(onPressed: _busy ? null : () => _checkStatus(save: true), child: const Text('Guardar na pasta da aplicação')),
            TextButton(onPressed: _busy ? null : () => _checkStatus(), child: const Text('Verificar envio dessa pasta')),
            TextButton(onPressed: _busy ? null : () => _restore(), child: const Text('Recuperar dessa pasta')),
          ]),
        const Text('Guarde uma nova cópia depois de alterar os registos.',
          style: TextStyle(fontSize: 12)),
      ])),
      actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Fechar'))],
    ),
  );
}
