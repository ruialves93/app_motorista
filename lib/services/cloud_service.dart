import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/driver_entry.dart';
import 'db_helper.dart';

// Cliente HTTP autenticado sem dependências extras
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class CloudService {
  static const String backupFileName = 'CCTV_Motorista_Backup.json';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  static Future<GoogleSignInAccount?> signInGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('google_account_email', account.email);
        await syncFromDriveOnLogin(); // Sincroniza logo ao ligar a conta
      }
      return account;
    } catch (_) {
      return null;
    }
  }

  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('google_account_email');
    } catch (_) {}
  }

  static Future<drive.DriveApi?> _getDriveApi() async {
    try {
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      if (account == null) return null;

      final authHeaders = await account.authHeaders;
      final authClient = GoogleAuthClient(authHeaders);

      return drive.DriveApi(authClient);
    } catch (_) {
      return null;
    }
  }

  // Upload automático silencioso em segundo plano
  static Future<bool> uploadOrReplaceBackupOnDrive() async {
    try {
      final api = await _getDriveApi();
      if (api == null) return false;

      final entries = await DBHelper.instance.getAllEntries();
      final prefs = await SharedPreferences.getInstance();

      final backupMap = {
        'version': 2,
        'timestamp': DateTime.now().toIso8601String(),
        'driver_name': prefs.getString('driver_name') ?? '',
        'driver_nif': prefs.getString('driver_nif') ?? '',
        'company_name': prefs.getString('company_name') ?? '',
        'company_nif': prefs.getString('company_nif') ?? '',
        'driver_type': prefs.getString('driver_type') ?? 'Publico',
        'base_salary': prefs.getDouble('base_salary') ?? 942.00,
        'meal_allowance': prefs.getDouble('meal_allowance') ?? 5.50,
        'first_meal_normal': prefs.getDouble('first_meal_normal') ?? 10.00,
        'second_meal_normal': prefs.getDouble('second_meal_normal') ?? 7.00,
        'first_meal_penalized': prefs.getDouble('first_meal_penalized') ?? 5.80,
        'second_meal_penalized': prefs.getDouble('second_meal_penalized') ?? 2.20,
        'night_start': prefs.getString('night_start') ?? '20:00',
        'night_end': prefs.getString('night_end') ?? '07:00',
        'entries': entries.map((e) => e.toMap()).toList(),
      };

      final jsonContent = jsonEncode(backupMap);
      final tempDir = await getTemporaryDirectory();
      final localFile = File('${tempDir.path}/$backupFileName');
      await localFile.writeAsString(jsonContent);

      final query = "name = '$backupFileName' and trashed = false";
      final fileList = await api.files.list(q: query, spaces: 'drive');

      final media = drive.Media(localFile.openRead(), localFile.lengthSync());

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final existingFileId = fileList.files!.first.id!;
        await api.files.update(drive.File(), existingFileId, uploadMedia: media);
      } else {
        final driveFile = drive.File()..name = backupFileName;
        await api.files.create(driveFile, uploadMedia: media);
      }

      await prefs.setString('last_cloud_sync', DateTime.now().toIso8601String());
      return true;
    } catch (_) {
      return false;
    }
  }

  // Sincroniza da nuvem para o dispositivo local
  static Future<bool> syncFromDriveOnLogin() async {
    try {
      final api = await _getDriveApi();
      if (api == null) return false;

      final query = "name = '$backupFileName' and trashed = false";
      final fileList = await api.files.list(q: query, spaces: 'drive');

      if (fileList.files == null || fileList.files!.isEmpty) {
        await uploadOrReplaceBackupOnDrive();
        return true;
      }

      final fileId = fileList.files!.first.id!;
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final List<int> dataStore = [];
      await for (final data in media.stream) {
        dataStore.addAll(data);
      }

      final jsonStr = utf8.decode(dataStore);
      final dynamic decoded = jsonDecode(jsonStr);

      if (decoded is Map<String, dynamic>) {
        final prefs = await SharedPreferences.getInstance();
        if (decoded.containsKey('driver_name')) await prefs.setString('driver_name', decoded['driver_name']);
        if (decoded.containsKey('driver_nif')) await prefs.setString('driver_nif', decoded['driver_nif']);
        if (decoded.containsKey('company_name')) await prefs.setString('company_name', decoded['company_name']);
        if (decoded.containsKey('company_nif')) await prefs.setString('company_nif', decoded['company_nif']);
        if (decoded.containsKey('driver_type')) await prefs.setString('driver_type', decoded['driver_type']);
        if (decoded.containsKey('base_salary')) await prefs.setDouble('base_salary', (decoded['base_salary'] as num).toDouble());
        if (decoded.containsKey('meal_allowance')) await prefs.setDouble('meal_allowance', (decoded['meal_allowance'] as num).toDouble());

        final List<dynamic> entriesList = decoded['entries'] ?? [];
        for (var item in entriesList) {
          final entry = DriverEntry.fromMap(item as Map<String, dynamic>);
          await DBHelper.instance.insertOrUpdate(entry);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> checkAndRunDailySync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('google_account_email');
      if (email == null || email.isEmpty) return;

      final lastSyncStr = prefs.getString('last_cloud_sync');
      if (lastSyncStr != null) {
        final lastSync = DateTime.tryParse(lastSyncStr);
        if (lastSync != null && DateTime.now().difference(lastSync).inHours < 4) {
          return;
        }
      }
      await uploadOrReplaceBackupOnDrive();
    } catch (_) {}
  }

  static Future<bool> openGmailContact({
    required String driverName,
    required String driverNif,
    required String companyName,
  }) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'rui.barata.transportes@gmail.com',
      query: 'subject=Suporte CCTV Motorista - $driverName&body=Motorista: $driverName (NIF: $driverNif)%0AEmpresa: $companyName%0A%0AMensagem:%0A',
    );

    if (await canLaunchUrl(emailUri)) {
      return await launchUrl(emailUri);
    }
    return false;
  }
}