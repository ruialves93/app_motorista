import 'package:app_motorista/services/icloud_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(ICloudService.channel, null));

  test('Backup settings include monthly rates and exclude credentials', () {
    expect(ICloudService.isBackupSetting('base_salary_2026_10'), isTrue);
    expect(ICloudService.isBackupSetting('driver_name'), isTrue);
    expect(ICloudService.isBackupSetting('app_pin'), isFalse);
    expect(ICloudService.isBackupSetting('google_account_email'), isFalse);
    expect(ICloudService.isBackupSetting('base_salary_unrelated'), isFalse);
  });

  test('Unavailable iCloud prevents writing any backup', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ICloudService.channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await expectLater(ICloudService.backup(), throwsStateError);
    expect(calls, ['account']);
  });

  test('Invalid restore is rejected before touching local records', () async {
    messenger.setMockMethodCallHandler(ICloudService.channel, (call) async {
      if (call.method == 'account') return 'test-account';
      expect(call.arguments['account'], 'test-account');
      return '{"version":99,"entries":[],"settings":{}}';
    });
    await expectLater(ICloudService.restore(), throwsFormatException);
  });

  test('Download errors propagate and do not block a subsequent restore', () async {
    var downloads = 0;
    messenger.setMockMethodCallHandler(ICloudService.channel, (call) async {
      if (call.method == 'account') return 'test-account';
      downloads++;
      throw PlatformException(code: 'downloading', message: 'Aguarde e tente novamente.');
    });
    await expectLater(ICloudService.restore(), throwsA(isA<PlatformException>()));
    await expectLater(ICloudService.restore(), throwsA(isA<PlatformException>()));
    expect(downloads, 2);
  });
}
