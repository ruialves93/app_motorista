import 'dart:io';
import 'package:app_motorista/services/auth_service.dart';
import 'package:app_motorista/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Disabling lock preserves PIN', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.setLock(true, '1234');
    expect(await AuthService.isLockEnabled(), isTrue);
    await AuthService.setLock(false, null);
    expect(await AuthService.isLockEnabled(), isFalse);
    expect(await AuthService.getSavedPin(), '1234');
  });
  testWidgets('Non-Android updates use store distribution', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => UpdateService.checkForUpdates(context, showNoUpdateMessage: true),
        child: const Text('Atualizar'),
      )),
    )));
    await tester.tap(find.text('Atualizar'));
    await tester.pump();
    expect(find.textContaining('App Store ou TestFlight'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  }, skip: Platform.isAndroid);
}
