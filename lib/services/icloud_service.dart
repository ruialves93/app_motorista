import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/driver_entry.dart';
import 'db_helper.dart';

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

  // Serializes backup and restore so an automatic save cannot overlap a restore.
  static Future<T> _serial<T>(Future<T> Function() work) {
    final operation = _pending.then((_) => work());
    _pending = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  static Future<void> backup() => _serial(() async {
    final identity = await account();
    if (identity == null) throw StateError('Ative o iCloud Drive nas Definições do iPhone.');
    final prefs = await SharedPreferences.getInstance();
    final entries = await DBHelper.instance.getAllEntries();
    final settings = <String, Object>{
      for (final key in prefs.getKeys())
        if (isBackupSetting(key)) key: prefs.get(key)!,
    };
    await channel.invokeMethod<void>('write', {
      'account': identity,
      'content': jsonEncode({
        'version': 1,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'settings': settings,
        'entries': entries.map((e) => e.toMap()).toList(),
      }),
    });
    await prefs.setString('last_icloud_backup', DateTime.now().toIso8601String());
  });

  static Future<void> restore() => _serial(() async {
    final identity = await account();
    if (identity == null) throw StateError('Ative o iCloud Drive nas Definições do iPhone.');
    final content = await channel.invokeMethod<String>('read', {'account': identity});
    if (content == null) throw StateError('Ainda não existe uma cópia de segurança no iCloud.');
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
  });
}
