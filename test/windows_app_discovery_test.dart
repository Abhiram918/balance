import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/discovered_app.dart';
import 'package:balance/core/services/lnk_resolver.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_app_discovery_service.dart';
import 'package:balance/core/services/windows_process_manager.dart';

class FakeDiscoveryRepository extends UsageRepository {
  final List<Map<String, String>> trackedApps;

  FakeDiscoveryRepository(this.trackedApps);

  @override
  Future<List<Map<String, String>>> getDistinctTrackedAppsWithPaths() async {
    return List.unmodifiable(trackedApps);
  }

  @override
  Future<void> close() async {}
}

WindowsAppDiscoveryService createMockService({
  UsageRepository? repository,
  List<Map<String, String>> Function()? registryEntriesProvider,
  List<String> Function()? startMenuDirectoriesProvider,
  List<String> Function()? windowsAppsDirectoryProvider,
  String Function()? selfExecutablePathProvider,
  bool Function(String)? fileExistsProvider,
}) {
  return WindowsAppDiscoveryService(
    repository: repository,
    registryEntriesProvider: registryEntriesProvider ?? () => [],
    startMenuDirectoriesProvider: startMenuDirectoriesProvider ?? () => [],
    windowsAppsDirectoryProvider: windowsAppsDirectoryProvider ?? () => [],
    selfExecutablePathProvider: selfExecutablePathProvider ?? () => r'C:\Users\test\balance.exe',
    fileExistsProvider: fileExistsProvider ?? (path) => true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LnkResolver Unit Tests', () {
    test('Returns null on non-existent file', () async {
      final res = LnkResolver.resolve(File(r'C:\non_existent_shortcut.lnk'));
      expect(res, isNull);
    });

    test('Returns null on empty or invalid header bytes', () {
      final emptyBytes = Uint8List(0);
      expect(LnkResolver.resolveBytes(emptyBytes), isNull);

      final invalidHeader = Uint8List(76);
      invalidHeader[0] = 0x00; // Not 0x4C
      expect(LnkResolver.resolveBytes(invalidHeader), isNull);

      final invalidGuid = Uint8List(76);
      invalidGuid[0] = 0x4C;
      invalidGuid[4] = 0xFF; // Not CLSID 0x00021401
      expect(LnkResolver.resolveBytes(invalidGuid), isNull);
    });

    test('Parses valid ShellLink with LinkInfo and LocalBasePath', () {
      final buffer = BytesBuilder();

      // Header (76 bytes)
      final header = Uint8List(76);
      final byteData = ByteData.sublistView(header);
      byteData.setUint32(0, 0x0000004C, Endian.little); // HeaderSize = 76
      // CLSID {00021401-0000-0000-C000-000000000046}
      header[4] = 0x01;
      header[5] = 0x14;
      header[6] = 0x02;
      header[7] = 0x00;
      header[8] = 0x00;
      header[9] = 0x00;
      header[10] = 0x00;
      header[11] = 0x00;
      header[12] = 0xC0;
      header[13] = 0x00;
      header[14] = 0x00;
      header[15] = 0x00;
      header[16] = 0x00;
      header[17] = 0x00;
      header[18] = 0x00;
      header[19] = 0x46;

      // LinkFlags: HasLinkInfo = bit 1 (0x02)
      byteData.setUint32(20, 0x00000002, Endian.little);
      buffer.add(header);

      const testPath = r'C:\Program Files\Telegram Desktop\Telegram.exe';
      final pathBytes = testPath.codeUnits;

      final linkInfoHeader = Uint8List(28);
      final liData = ByteData.sublistView(linkInfoHeader);
      final totalLinkInfoSize = 28 + pathBytes.length + 1;
      liData.setUint32(0, totalLinkInfoSize, Endian.little);
      liData.setUint32(4, 28, Endian.little);
      liData.setUint32(8, 0x01, Endian.little);
      liData.setUint32(12, 0, Endian.little);
      liData.setUint32(16, 28, Endian.little);

      buffer.add(linkInfoHeader);
      buffer.add(pathBytes);
      buffer.add([0]); // Null terminator

      final bytes = buffer.toBytes();
      final result = LnkResolver.resolveBytes(bytes);

      expect(result, isNotNull);
      expect(result!.targetPath, equals(testPath));
    });

    test('Expands environment variables', () {
      final expanded = LnkResolver.expandEnvVars(r'%USERPROFILE%\AppData\Local');
      expect(expanded.contains('%USERPROFILE%'), isFalse);
    });
  });

  group('WindowsAppDiscoveryService Unit Tests', () {
    test('Discovers installed applications from Registry mock provider', () async {
      final service = createMockService(
        registryEntriesProvider: () => [
          {
            'DisplayName': 'Google Chrome',
            'DisplayIcon': r'C:\Program Files\Google\Chrome\Application\chrome.exe,0',
            'InstallLocation': r'C:\Program Files\Google\Chrome\Application',
            'Publisher': 'Google LLC',
          },
          {
            'DisplayName': 'Visual Studio Code',
            'DisplayIcon': r'C:\Users\test\AppData\Local\Programs\Microsoft VS Code\Code.exe',
            'InstallLocation': r'C:\Users\test\AppData\Local\Programs\Microsoft VS Code',
            'Publisher': 'Microsoft Corporation',
          },
          {
            // System component that should be excluded
            'DisplayName': 'Microsoft Edge WebView2 Runtime',
            'SystemComponent': '1',
            'InstallLocation': r'C:\Program Files (x86)\Microsoft\EdgeWebView',
          },
          {
            // Uninstaller stub that should be excluded
            'DisplayName': 'Some App Uninstaller',
            'DisplayIcon': r'C:\Program Files\SomeApp\unins000.exe',
            'InstallLocation': r'C:\Program Files\SomeApp',
          },
        ],
      );

      final apps = await service.discoverApplications();

      expect(apps.any((a) => a.displayName == 'Google Chrome'), isTrue);
      expect(apps.any((a) => a.displayName == 'Visual Studio Code'), isTrue);
      expect(apps.any((a) => a.displayName.contains('WebView2')), isFalse);
      expect(apps.any((a) => a.displayName.contains('Uninstaller')), isFalse);

      final chrome = apps.firstWhere((a) => a.displayName == 'Google Chrome');
      expect(chrome.publisher, equals('Google LLC'));
      expect(chrome.executableName, equals('chrome.exe'));
      expect(chrome.source, equals(AppDiscoverySource.registry));
    });

    test('Normalizes well-known executable names', () async {
      final service = createMockService(
        registryEntriesProvider: () => [
          {
            'DisplayName': 'msedge.exe',
            'DisplayIcon': r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
            'InstallLocation': r'C:\Program Files (x86)\Microsoft\Edge\Application',
          },
          {
            'DisplayName': 'code.exe',
            'DisplayIcon': r'C:\Users\test\AppData\Local\Programs\Microsoft VS Code\code.exe',
            'InstallLocation': r'C:\Users\test\AppData\Local\Programs\Microsoft VS Code',
          },
        ],
      );

      final apps = await service.discoverApplications();

      expect(apps.any((a) => a.displayName == 'Microsoft Edge'), isTrue);
      expect(apps.any((a) => a.displayName == 'Visual Studio Code'), isTrue);
    });

    test('Excludes Balance self from discovery targets', () async {
      final service = createMockService(
        registryEntriesProvider: () => [
          {
            'DisplayName': 'Balance',
            'DisplayIcon': r'C:\Users\test\AppData\Local\Balance\balance.exe',
            'InstallLocation': r'C:\Users\test\AppData\Local\Balance',
          },
          {
            'DisplayName': 'Balance Desktop',
            'DisplayIcon': r'D:\fluttering_flutter\DigitalWelbeing\build\windows\runner\Release\balance.exe',
            'InstallLocation': r'D:\fluttering_flutter\DigitalWelbeing\build',
          },
          {
            'DisplayName': 'Telegram',
            'DisplayIcon': r'C:\Users\test\AppData\Roaming\Telegram Desktop\Telegram.exe',
            'InstallLocation': r'C:\Users\test\AppData\Roaming\Telegram Desktop',
          },
        ],
        selfExecutablePathProvider: () => r'C:\Users\test\AppData\Local\Balance\balance.exe',
      );

      final apps = await service.discoverApplications();

      expect(apps.any((a) => a.displayName == 'Telegram'), isTrue);
      expect(apps.any((a) => a.displayName.toLowerCase().contains('balance')), isFalse);
      expect(apps.any((a) => a.executableName?.toLowerCase() == 'balance.exe'), isFalse);
    });

    test('Excludes Windows shell and background components', () async {
      final service = createMockService(
        registryEntriesProvider: () => [
          {
            'DisplayName': 'Explorer',
            'DisplayIcon': r'C:\Windows\explorer.exe',
            'InstallLocation': r'C:\Windows',
          },
          {
            'DisplayName': 'ShellExperienceHost',
            'DisplayIcon': r'C:\Windows\SystemApps\ShellExperienceHost.exe',
            'InstallLocation': r'C:\Windows\SystemApps',
          },
          {
            'DisplayName': 'Mozilla Firefox',
            'DisplayIcon': r'C:\Program Files\Mozilla Firefox\firefox.exe',
            'InstallLocation': r'C:\Program Files\Mozilla Firefox',
          },
        ],
      );

      final apps = await service.discoverApplications();

      expect(apps.any((a) => a.displayName == 'Mozilla Firefox'), isTrue);
      expect(apps.any((a) => a.displayName.toLowerCase() == 'explorer'), isFalse);
      expect(apps.any((a) => a.displayName.toLowerCase() == 'shellexperiencehost'), isFalse);
    });

    test('Excludes synthetic test fixtures from SQLite historical tracking without deleting DB data', () async {
      final fakeRepo = FakeDiscoveryRepository([
        {'appName': 'Telegram', 'exePath': r'D:\Telegram Desktop\Telegram.exe'},
        {'appName': 'Test App 1', 'exePath': r'C:\test1.exe'},
        {'appName': 'Test App 2', 'exePath': r'C:\test2.exe'},
        {'appName': 'MidnightApp', 'exePath': r'C:\midnight.exe'},
        {'appName': 'YesterdayApp', 'exePath': r'C:\yesterday.exe'},
        {'appName': 'NormalApp', 'exePath': r'C:\normal.exe'},
        {'appName': 'Explorer', 'exePath': r'C:\Windows\explorer.exe'},
      ]);

      final service = createMockService(
        repository: fakeRepo,
      );

      final apps = await service.discoverApplications();

      // Only legitimate historical app Telegram should be included
      expect(apps.length, equals(1));
      expect(apps.first.displayName, equals('Telegram'));
      expect(apps.first.isPreviouslyTracked, isTrue);

      // Verify that the underlying fake repo still holds all raw records (data was not deleted)
      final rawRecords = await fakeRepo.getDistinctTrackedAppsWithPaths();
      expect(rawRecords.length, equals(7));
      expect(rawRecords.any((r) => r['appName'] == 'Test App 1'), isTrue);
    });

    test('Deduplicates applications across multiple discovery sources and preserves metadata', () async {
      final fakeRepo = FakeDiscoveryRepository([
        {'appName': 'Telegram', 'exePath': r'C:\Users\test\AppData\Roaming\Telegram Desktop\Telegram.exe'},
      ]);

      final service = createMockService(
        repository: fakeRepo,
        registryEntriesProvider: () => [
          {
            'DisplayName': 'Telegram Desktop',
            'DisplayIcon': r'C:\Users\test\AppData\Roaming\Telegram Desktop\Telegram.exe',
            'InstallLocation': r'C:\Users\test\AppData\Roaming\Telegram Desktop',
            'Publisher': 'Telegram FZ-LLC',
          },
        ],
      );

      final apps = await service.discoverApplications();

      final telegramMatches = apps.where((a) => a.displayName == 'Telegram').toList();
      expect(telegramMatches.length, equals(1));

      final telegram = telegramMatches.first;
      expect(telegram.publisher, equals('Telegram FZ-LLC'));
      expect(telegram.isPreviouslyTracked, isTrue);
      expect(telegram.executablePath, equals(r'C:\Users\test\AppData\Roaming\Telegram Desktop\Telegram.exe'));
    });
  });

  group('WindowsProcessManager Application Matching Tests', () {
    late WindowsProcessManager processManager;

    setUp(() {
      processManager = WindowsProcessManager();
    });

    test('Matches exact and alias executable names', () {
      expect(
        processManager.matchesProcess(
          processName: 'telegram.exe',
          appName: 'Telegram',
          targetExePath: r'D:\Telegram Desktop\Telegram.exe',
        ),
        isTrue,
      );

      expect(
        processManager.matchesProcess(
          processName: 'app.exe',
          appName: 'My App',
          processExePath: r'C:\Program Files\MyApp\app.exe',
          targetExePath: r'C:\Program Files\MyApp\app.exe',
        ),
        isTrue,
      );

      expect(
        processManager.matchesProcess(
          processName: 'msedge.exe',
          appName: 'Microsoft Edge',
        ),
        isTrue,
      );

      expect(
        processManager.matchesProcess(
          processName: 'whatsapp.root.exe',
          appName: 'WhatsApp',
        ),
        isTrue,
      );

      expect(
        processManager.matchesProcess(
          processName: 'snippingtool.exe',
          appName: 'Snipping Tool',
        ),
        isTrue,
      );

      expect(
        processManager.matchesProcess(
          processName: 'code.exe',
          appName: 'Visual Studio Code',
        ),
        isTrue,
      );

      expect(
        processManager.matchesProcess(
          processName: 'notepad.exe',
          appName: 'Telegram',
        ),
        isFalse,
      );
    });
  });
}
