import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/main.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/services/app_debug_log_service.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/ble_debug_log_service.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  final Directory tempDir;

  _TestPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getDownloadsPath() async => tempDir.path;

  @override
  Future<String?> getLibraryPath() async => tempDir.path;

  @override
  Future<String?> getExternalStoragePath() async => tempDir.path;

  @override
  Future<List<String>?> getExternalCachePaths() async => [tempDir.path];

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async =>
      [tempDir.path];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('meshcore_widget_test');
  PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir);
  SharedPreferences.setMockInitialValues({});
  PrefsManager.reset();

  testWidgets('App loads successfully', (WidgetTester tester) async {
    final storage = StorageService();
    final connector = MeshCoreConnector();
    final pathHistoryService = PathHistoryService(storage);
    final retryService = MessageRetryService(storage);
    final appSettingsService = AppSettingsService();
    final bleDebugLogService = BleDebugLogService();
    final appDebugLogService = AppDebugLogService();
    final mapTileCacheService = MapTileCacheService();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MeshCoreApp(
        connector: connector,
        retryService: retryService,
        pathHistoryService: pathHistoryService,
        storage: storage,
        appSettingsService: appSettingsService,
        bleDebugLogService: bleDebugLogService,
        appDebugLogService: appDebugLogService,
        mapTileCacheService: mapTileCacheService,
      ),
    );

    // Verify that the app title appears
    expect(find.text('MeshCore Open'), findsOneWidget);
  });
}
