import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/driver_entry.dart';
import 'db_helper.dart';

class ICloudBackupStatus {
  const ICloudBackupStatus(this.message, {this.confirmed = false});
  final String message;
  final bool confirmed;
}

class ICloudService {
  static const channel = MethodChannel('com.ruibarata.cctvmotorista/icloud');
  static const _settings = [
    'driver_name', 'driver_nif', 'company_name', 'company_nif', 'driver_type',
    'base_salary', 'meal_allowance', 'first_meal_normal', 'second_meal_normal',
    'first_meal_penalized', 'second_meal_penalized', 'night_start', 'night_end',
  ];
  static Future<void> _pending = Future.value();

  static bool isBackupSetting(String key) => _settings.any(
    (name) => key == name || RegExp('^${name}_[0-9]{4}_[0-9]{2}\$').hasMatch(key),
  );

  static Future<String?> account() => channel.invokeMethod<String>('account');

  static Future<String> accountDescription() async {
    final info = await channel.invokeMapMethod<String, dynamic>('accountInfo');
    if (info?['hasAccount'] != true) return 'O iOS não confirmou acesso ao iCloud desta aplicação. Pode escolher iCloud Drive em Ficheiros.';
    if (info?['hasStorage'] != true) return 'Conta iCloud detetada; a pasta da aplicação ainda não está disponível.';
    return 'Conta Apple deste iPhone — iCloud Drive ativo.';
  }

  static Future<String> backupStatus() async => (await backupStatusDetails()).message;

  static Future<ICloudBackupStatus> backupStatusDetails() async {
    final identity = await account();
    if (identity == null) return const ICloudBackupStatus('O iCloud Drive não está disponível nesta sessão.');
    final status = await channel.invokeMapMethod<String, dynamic>('status', {'account': identity});
    if (status == null) return const ICloudBackupStatus('Não foi possível verificar o envio.');
    if (status['error'] is String) return ICloudBackupStatus('O iCloud não conseguiu enviar a cópia: ${status['error']}');
    if (status['exists'] != true) return const ICloudBackupStatus('Ainda não existe uma cópia nesta pasta iCloud.');
    if (status['uploaded'] == true) {
      return const ICloudBackupStatus('Cópia de segurança efetuada com sucesso no iCloud. Envio para o iCloud confirmado pelo iOS. Ficheiro: CCTV_Motorista_Backup.json.', confirmed: true);
    }
    if (status['uploading'] == true) return const ICloudBackupStatus('O iOS está a enviar a cópia para o iCloud. Toque em Verificar envio para atualizar.');
    return const ICloudBackupStatus('Cópia gravada no dispositivo, mas o envio para o iCloud ainda não foi confirmado. Verifique a ligação e o iCloud Drive e toque em Verificar envio.');
  }

  // Serializes backup and restore so an automatic save cannot overlap a restore.
  static Future<T> _serial<T>(Future<T> Function() work) {
    final operation = _pending.then((_) => work());
    _pending = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  static Future<void> backup() => _serial(() async {
    final identity = await account();
    if (identity == null) throw StateError('Ative o iCloud Drive nas Definições do iPhone.');
    final content = await _backupContent();
    await channel.invokeMethod<void>('write', {'account': identity, 'content': content});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_icloud_backup', DateTime.now().toIso8601String());
  });

  static Future<String> _backupContent() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await DBHelper.instance.getAllEntries();
    final settings = <String, Object>{
      for (final key in prefs.getKeys())
        if (isBackupSetting(key)) key: prefs.get(key)!,
    };
    return jsonEncode({
        'version': 1,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'settings': settings,
        'entries': entries.map((e) => e.toMap()).toList(),
      });
  }

  /// Lets iOS grant access to the destination selected by the user, including
  /// iCloud Drive, without relying on the app's own ubiquity container.
  static Future<String?> saveViaFiles() => _serial(() async {
    final content = await _backupContent();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return FilePicker.platform.saveFile(
      dialogTitle: 'Escolha iCloud Drive e toque em Guardar',
      fileName: 'CCTV_Motorista_Backup_$stamp.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
  });

  static Future<bool> restoreViaFiles() => _serial(() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['json'], withData: true,
    );
    if (result == null) return false;
    final picked = result.files.single;
    final bytes = picked.bytes ?? await File(picked.path!).readAsBytes();
    await _restoreContent(utf8.decode(bytes));
    return true;
  });

  static Future<void> restore() => _serial(() async {
    final identity = await account();
    if (identity == null) throw StateError('Ative o iCloud Drive nas Definições do iPhone.');
    final content = await channel.invokeMethod<String>('read', {'account': identity});
    if (content == null) throw StateError('Ainda não existe uma cópia de segurança no iCloud.');
    await _restoreContent(content);
  });

  static Future<void> _restoreContent(String content) async {
    final data = jsonDecode(content);
    if (data is! Map || data['version'] != 1 || data['entries'] is! List || data['settings'] is! Map) {
      throw const FormatException('Cópia de segurança inválida.');
    }
    final entries = (data['entries'] as List).map((item) {
      final entry = DriverEntry.fromMap(Map<String, dynamic>.from(item as Map));
      if (DateTime.tryParse(entry.date) == null) throw const FormatException('Data inválida.');
      return entry.toMap()..remove('id');
    }).toList();
    final settings = Map<String, dynamic>.from(data['settings'] as Map);
    for (final item in settings.entries) {
      final numeric = ['base_salary', 'meal_allowance', 'first_meal_normal',
        'second_meal_normal', 'first_meal_penalized', 'second_meal_penalized']
          .any((name) => item.key == name || item.key.startsWith('${name}_'));
      if (!isBackupSetting(item.key) ||
          (numeric ? item.value is! num : item.value is! String)) {
        throw const FormatException('Definições de backup inválidas.');
      }
    }
    final db = await DBHelper.instance.database;
    await db.transaction((txn) async {
      for (final entry in entries) {
        await txn.insert('driver_entries', entry, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    for (final item in settings.entries) {
      if (item.value is num) {
        await prefs.setDouble(item.key, (item.value as num).toDouble());
      } else {
        await prefs.setString(item.key, item.value as String);
      }
    }
  }
}
