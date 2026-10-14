import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/discovered_app.dart';
import 'lnk_resolver.dart';
import 'usage_repository.dart';

/// Dedicated, reusable Windows application discovery service.
///
/// Discovers installed desktop applications across:
/// 1. Current user and All Users Start Menu shortcuts (.lnk resolution)
/// 2. Windows Registry Uninstall keys (HKCU, HKLM 64-bit, and HKLM WOW6432Node 32-bit)
/// 3. Packaged Windows applications (WindowsApps execution aliases / AppX)
/// 4. Historical tracked applications from SQLite (excluding synthetic test entries)
///
/// Features:
/// - Deduplicates applications discovered across multiple sources
/// - Normalizes display names (e.g. msedge.exe -> Microsoft Edge)
/// - Excludes Balance itself by executable path and stable application identity
/// - Excludes Windows shell components, system background processes, and uninstaller stubs
/// - Filters synthetic test fixtures without deleting legitimate usage history
/// - Fully testable with mock providers without requiring Windows administrator privileges
class WindowsAppDiscoveryService {
  final UsageRepository? repository;

  // Custom injectable providers for unit testing across platforms
  final List<String> Function()? startMenuDirectoriesProvider;
  final List<Map<String, String>> Function()? registryEntriesProvider;
  final List<String> Function()? windowsAppsDirectoryProvider;
  final String Function()? selfExecutablePathProvider;
  final bool Function(String path)? fileExistsProvider;

  List<DiscoveredApp>? _cachedApps;
  DateTime? _lastDiscoveryTime;
  final Duration cacheDuration;

  WindowsAppDiscoveryService({
    this.repository,
    this.startMenuDirectoriesProvider,
    this.registryEntriesProvider,
    this.windowsAppsDirectoryProvider,
    this.selfExecutablePathProvider,
    this.fileExistsProvider,
    this.cacheDuration = const Duration(minutes: 5),
  });

  /// Protected process and shell components that must NEVER be shown or targeted.
  static const Set<String> _excludedExeNames = {
    'explorer.exe',
    'shellexperiencehost.exe',
    'sihost.exe',
    'shellhost.exe',
    'searchhost.exe',
    'searchapp.exe',
    'searchui.exe',
    'searchindexer.exe',
    'startmenuexperiencehost.exe',
    'dwm.exe',
    'csrss.exe',
    'smss.exe',
    'lsass.exe',
    'services.exe',
    'wininit.exe',
    'winlogon.exe',
    'svchost.exe',
    'system',
    'taskmgr.exe',
    'taskhostw.exe',
    'taskhost.exe',
    'cmd.exe',
    'powershell.exe',
    'pwsh.exe',
    'conhost.exe',
    'ctfmon.exe',
    'fontdrvhost.exe',
    'rundll32.exe',
    'dllhost.exe',
    'appverif.exe',
    'msiexec.exe',
    'balance.exe',
    'digital_wellbeing.exe',
    'flutter_tester.exe',
  };

  /// Common uninstaller and updater binary keywords to filter out.
  static const List<String> _uninstallerKeywords = [
    'unins000.exe',
    'uninstall.exe',
    'uninst.exe',
    'setup.exe',
    'deploytool.exe',
    'accapplauncher.exe',
    'camusage.exe',
  ];

  /// Well-known executable names mapped to human-friendly display names.
  static const Map<String, String> _wellKnownAppNames = {
    'msedge.exe': 'Microsoft Edge',
    'chrome.exe': 'Google Chrome',
    'firefox.exe': 'Mozilla Firefox',
    'opera.exe': 'Opera Browser',
    'brave.exe': 'Brave Browser',
    'code.exe': 'Visual Studio Code',
    'telegram.exe': 'Telegram',
    'whatsapp.exe': 'WhatsApp',
    'whatsapp.root.exe': 'WhatsApp',
    'snippingtool.exe': 'Snipping Tool',
    'spotify.exe': 'Spotify',
    'discord.exe': 'Discord',
    'slack.exe': 'Slack',
    'notepad.exe': 'Notepad',
    'notepad++.exe': 'Notepad++',
    'mspaint.exe': 'Paint',
    'wt.exe': 'Windows Terminal',
    'steam.exe': 'Steam',
    'vlc.exe': 'VLC media player',
    'winrar.exe': 'WinRAR',
    'devenv.exe': 'Visual Studio',
    'studio64.exe': 'Android Studio',
    'pycharm64.exe': 'PyCharm',
    'idea64.exe': 'IntelliJ IDEA',
    'postman.exe': 'Postman',
    'figma.exe': 'Figma',
    'githubdesktop.exe': 'GitHub Desktop',
    'mongodbcompass.exe': 'MongoDB Compass',
    'localsend_app.exe': 'LocalSend',
    'powertoys.exe': 'PowerToys',
    'winword.exe': 'Microsoft Word',
    'excel.exe': 'Microsoft Excel',
    'powerpnt.exe': 'Microsoft PowerPoint',
    'onenote.exe': 'Microsoft OneNote',
    'outlook.exe': 'Microsoft Outlook',
    'olk.exe': 'Outlook',
    'msaccess.exe': 'Microsoft Access',
    'mspub.exe': 'Microsoft Publisher',
  };

  /// Discovers installed and legitimate tracked applications.
  Future<List<DiscoveredApp>> discoverApplications({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedApps != null &&
        _lastDiscoveryTime != null &&
        now.difference(_lastDiscoveryTime!) < cacheDuration) {
      return _cachedApps!;
    }

    final discoveredMap = <String, DiscoveredApp>{};
    final selfExe = _getSelfExecutablePath();

    // 1. Discover applications from Start Menu shortcuts
    await _discoverFromStartMenu(discoveredMap, selfExe);

    // 2. Discover applications from Windows Registry
    await _discoverFromRegistry(discoveredMap, selfExe);

    // 3. Discover packaged Windows applications (WindowsApps)
    await _discoverFromPackagedApps(discoveredMap, selfExe);

    // 4. Supplement with legitimate historical tracked applications
    await _discoverFromHistoricalTracking(discoveredMap, selfExe);

    // Filter, deduplicate, and sort alphabetically
    final result = discoveredMap.values
        .where((app) => !_isExcludedApp(app.displayName, app.executablePath, selfExe))
        .toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    _cachedApps = List.unmodifiable(result);
    _lastDiscoveryTime = now;
    return _cachedApps!;
  }

  /// Resolves a friendly display name for an executable path or name.
  String getFriendlyNameForExe(String exePath) {
    final exeName = p.basename(exePath).toLowerCase();
    if (_wellKnownAppNames.containsKey(exeName)) {
      return _wellKnownAppNames[exeName]!;
    }

    if (_cachedApps != null) {
      for (final app in _cachedApps!) {
        if (app.executableName?.toLowerCase() == exeName ||
            app.executablePath?.toLowerCase() == exePath.toLowerCase()) {
          return app.displayName;
        }
      }
    }

    // Fallback: capitalize base name without .exe
    final base = exeName.endsWith('.exe')
        ? exeName.substring(0, exeName.length - 4)
        : exeName;
    if (base.isEmpty) return 'Unknown Application';
    return base[0].toUpperCase() + base.substring(1);
  }

  /// Checks whether an application is excluded (Balance, system shell, test fixture, or uninstaller).
  bool isExcluded(String appName, String? exePath) {
    return _isExcludedApp(appName, exePath, _getSelfExecutablePath());
  }

  // --- Discovery Sources ---

  Future<void> _discoverFromStartMenu(
    Map<String, DiscoveredApp> discoveredMap,
    String selfExe,
  ) async {
    final dirs = _getStartMenuDirectories();

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!_fileExists(dirPath)) continue;

      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is File && entity.path.toLowerCase().endsWith('.lnk')) {
            try {
              final resolution = LnkResolver.resolve(entity);
              if (resolution != null) {
                final targetPath = resolution.targetPath;
                if (!targetPath.toLowerCase().endsWith('.exe')) continue;
                if (!_fileExists(targetPath)) continue;

                final rawName = resolution.name ?? p.basenameWithoutExtension(entity.path);
                final displayName = _cleanDisplayName(rawName, targetPath);
                final exeName = p.basename(targetPath);

                if (_isExcludedApp(displayName, targetPath, selfExe)) continue;

                final key = _makeAppKey(displayName, targetPath);
                final existing = discoveredMap[key];

                discoveredMap[key] = DiscoveredApp(
                  id: key,
                  displayName: displayName,
                  executablePath: targetPath,
                  executableName: exeName,
                  iconPath: resolution.iconLocation,
                  source: AppDiscoverySource.startMenu,
                  isPreviouslyTracked: existing?.isPreviouslyTracked ?? false,
                  installLocation: p.dirname(targetPath),
                );
              }
            } catch (e) {
              debugPrint('Error parsing shortcut ${entity.path}: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning Start Menu directory $dirPath: $e');
      }
    }
  }

  Future<void> _discoverFromRegistry(
    Map<String, DiscoveredApp> discoveredMap,
    String selfExe,
  ) async {
    final entries = _getRegistryEntries();

    for (final entry in entries) {
      try {
        final rawDisplayName = entry['DisplayName']?.trim() ?? '';
        if (rawDisplayName.isEmpty) continue;

        final systemComponent = entry['SystemComponent'] == '1';
        if (systemComponent) continue;

        final displayIcon = entry['DisplayIcon']?.trim();
        final installLocation = entry['InstallLocation']?.trim();
        final publisher = entry['Publisher']?.trim();

        // Resolve executable path from DisplayIcon or InstallLocation
        String? exePath = _resolveExeFromRegistry(displayIcon, installLocation);
        if (exePath != null && !_fileExists(exePath)) {
          exePath = null;
        }

        final displayName = _cleanDisplayName(rawDisplayName, exePath);
        if (_isExcludedApp(displayName, exePath, selfExe)) continue;

        // Skip registry items that cannot be resolved to a legitimate executable
        // and have no install location, preventing dummy uninstall keys
        if (exePath == null && (installLocation == null || !_fileExists(installLocation))) {
          continue;
        }

        final key = _makeAppKey(displayName, exePath);
        final existing = discoveredMap[key];

        discoveredMap[key] = DiscoveredApp(
          id: key,
          displayName: existing?.displayName ?? displayName,
          executablePath: existing?.executablePath ?? exePath,
          executableName: existing?.executableName ?? (exePath != null ? p.basename(exePath) : null),
          publisher: publisher ?? existing?.publisher,
          source: existing?.source ?? AppDiscoverySource.registry,
          isPreviouslyTracked: existing?.isPreviouslyTracked ?? false,
          installLocation: installLocation ?? existing?.installLocation,
        );
      } catch (e) {
        debugPrint('Error processing registry entry: $e');
      }
    }
  }

  Future<void> _discoverFromPackagedApps(
    Map<String, DiscoveredApp> discoveredMap,
    String selfExe,
  ) async {
    final dirs = _getWindowsAppsDirectories();

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!_fileExists(dirPath)) continue;

      try {
        final entities = dir.listSync(followLinks: false);
        for (final entity in entities) {
          final fileName = p.basename(entity.path);
          if (fileName.toLowerCase().endsWith('.exe')) {
            final exeName = fileName;
            final exePath = entity.path;
            final displayName = _cleanDisplayName(
              _wellKnownAppNames[exeName.toLowerCase()] ?? p.basenameWithoutExtension(exeName),
              exePath,
            );

            if (_isExcludedApp(displayName, exePath, selfExe)) continue;

            final key = _makeAppKey(displayName, exePath);
            final existing = discoveredMap[key];

            discoveredMap[key] = DiscoveredApp(
              id: key,
              displayName: existing?.displayName ?? displayName,
              executablePath: existing?.executablePath ?? exePath,
              executableName: exeName,
              source: existing?.source ?? AppDiscoverySource.packagedApp,
              isPreviouslyTracked: existing?.isPreviouslyTracked ?? false,
              installLocation: p.dirname(exePath),
            );
          }
        }
      } catch (e) {
        debugPrint('Error scanning WindowsApps directory $dirPath: $e');
      }
    }
  }

  Future<void> _discoverFromHistoricalTracking(
    Map<String, DiscoveredApp> discoveredMap,
    String selfExe,
  ) async {
    if (repository == null) return;

    try {
      final tracked = await repository!.getDistinctTrackedAppsWithPaths();

      for (final record in tracked) {
        final rawName = record['appName']?.trim() ?? '';
        final rawExe = record['exePath']?.trim() ?? '';

        if (rawName.isEmpty) continue;

        // Skip synthetic test fixtures
        if (_isSyntheticTestFixture(rawName, rawExe)) continue;

        // Skip Balance itself and system shell processes
        if (_isExcludedApp(rawName, rawExe, selfExe)) continue;

        final displayName = _cleanDisplayName(rawName, rawExe);
        final key = _makeAppKey(displayName, rawExe.isNotEmpty ? rawExe : null);

        final existing = discoveredMap[key];
        if (existing != null) {
          discoveredMap[key] = existing.copyWith(isPreviouslyTracked: true);
        } else {
          // If legitimate executable exists on disk or was tracked previously
          final exeExists = rawExe.isNotEmpty && _fileExists(rawExe);
          final exeName = rawExe.isNotEmpty ? p.basename(rawExe) : null;

          discoveredMap[key] = DiscoveredApp(
            id: key,
            displayName: displayName,
            executablePath: exeExists ? rawExe : (rawExe.isNotEmpty ? rawExe : null),
            executableName: exeName,
            source: AppDiscoverySource.historicalTracked,
            isPreviouslyTracked: true,
          );
        }
      }
    } catch (e) {
      debugPrint('Error retrieving historical tracked apps for discovery: $e');
    }
  }

  // --- Filtering & Normalization Helpers ---

  String _cleanDisplayName(String name, String? exePath) {
    var clean = name.trim();

    // 1. Check well-known executable mapping
    if (exePath != null && exePath.isNotEmpty) {
      final exeLower = p.basename(exePath).toLowerCase();
      if (_wellKnownAppNames.containsKey(exeLower)) {
        return _wellKnownAppNames[exeLower]!;
      }
    }

    // 2. Remove common shortcut suffixes
    if (clean.toLowerCase().endsWith(' - shortcut')) {
      clean = clean.substring(0, clean.length - 11).trim();
    }

    // 3. Strip trailing .exe if present in title
    if (clean.toLowerCase().endsWith('.exe')) {
      clean = clean.substring(0, clean.length - 4).trim();
    }

    // 4. Normalize common names
    final lower = clean.toLowerCase();
    if (lower == 'msedge') return 'Microsoft Edge';
    if (lower == 'whatsapp.root') return 'WhatsApp';
    if (lower == 'snippingtool') return 'Snipping Tool';
    if (lower == 'telegram desktop') return 'Telegram';
    if (lower == 'visual studio code (user)') return 'Visual Studio Code';

    return clean;
  }

  bool _isExcludedApp(String appName, String? exePath, String selfExe) {
    final nameLower = appName.trim().toLowerCase();

    // 1. Balance self-exclusion (by path, executable name, or app title)
    if (_isBalanceSelf(nameLower, exePath, selfExe)) {
      return true;
    }

    // 2. Windows shell components and critical system processes
    if (exePath != null && exePath.isNotEmpty) {
      final exeLower = p.basename(exePath).toLowerCase();
      if (_excludedExeNames.contains(exeLower)) return true;

      for (final kw in _uninstallerKeywords) {
        if (exeLower == kw) return true;
      }

      final pathLower = exePath.toLowerCase();
      if (pathLower.contains(r'\windows\system32\') ||
          pathLower.contains(r'\windows\syswow64\') ||
          pathLower.contains(r'\windows\systemapps\')) {
        if (exeLower.endsWith('host.exe') ||
            exeLower.startsWith('search') ||
            exeLower.startsWith('shell') ||
            exeLower == 'explorer.exe') {
          return true;
        }
      }
    }

    // Exclude by name if shell component
    if (nameLower == 'explorer' ||
        nameLower == 'shellexperiencehost' ||
        nameLower == 'shellhost' ||
        nameLower == 'searchhost' ||
        nameLower == 'system') {
      return true;
    }

    // 3. Synthetic test fixtures
    if (_isSyntheticTestFixture(appName, exePath)) {
      return true;
    }

    return false;
  }

  bool _isBalanceSelf(String appNameLower, String? exePath, String selfExe) {
    if (appNameLower == 'balance' ||
        appNameLower == 'balance desktop' ||
        appNameLower == 'digital wellbeing' ||
        appNameLower == 'digitalwelbeing') {
      return true;
    }

    if (exePath != null && exePath.isNotEmpty) {
      final exeLower = p.basename(exePath).toLowerCase();
      if (exeLower == 'balance.exe' || exeLower == 'digital_wellbeing.exe') {
        return true;
      }

      if (selfExe.isNotEmpty) {
        if (p.canonicalize(exePath).toLowerCase() == p.canonicalize(selfExe).toLowerCase()) {
          return true;
        }
      }
    }

    return false;
  }

  bool _isSyntheticTestFixture(String appName, String? exePath) {
    final lowerName = appName.trim().toLowerCase();

    // Match synthetic test fixture names
    if (lowerName == 'test app 1' ||
        lowerName == 'test app 2' ||
        lowerName == 'yesterdayapp' ||
        lowerName == 'midnightapp' ||
        lowerName == 'normalapp' ||
        lowerName.startsWith('test app ')) {
      return true;
    }

    // Match synthetic dummy paths (e.g. C:\test1.exe, C:\midnight.exe)
    if (exePath != null && exePath.isNotEmpty) {
      final pLower = exePath.toLowerCase();
      if (pLower == r'c:\test1.exe' ||
          pLower == r'c:\test2.exe' ||
          pLower == r'c:\midnight.exe' ||
          pLower == r'c:\normal.exe' ||
          pLower == r'c:\yesterday.exe' ||
          pLower == r'c:\old.exe' ||
          pLower == r'c:\v2.exe') {
        return true;
      }
    }

    return false;
  }

  String _makeAppKey(String displayName, String? exePath) {
    if (exePath != null && exePath.isNotEmpty) {
      // Use normalized executable path as primary stable identifier
      return p.canonicalize(exePath).toLowerCase();
    }
    return displayName.trim().toLowerCase();
  }

  String? _resolveExeFromRegistry(String? displayIcon, String? installLocation) {
    if (displayIcon != null && displayIcon.isNotEmpty) {
      var icon = displayIcon;
      if (icon.contains(',')) {
        icon = icon.substring(0, icon.lastIndexOf(',')).trim();
      }
      icon = LnkResolver.cleanPath(icon);
      if (icon.toLowerCase().endsWith('.exe')) {
        // Exclude uninstaller executables
        final exeName = p.basename(icon).toLowerCase();
        if (!_uninstallerKeywords.contains(exeName) && _fileExists(icon)) {
          return icon;
        }
      }
    }

    if (installLocation != null && installLocation.isNotEmpty) {
      final cleanLoc = LnkResolver.cleanPath(installLocation);
      final dir = Directory(cleanLoc);
      if (_fileExists(cleanLoc)) {
        try {
          final files = dir.listSync().whereType<File>().where(
                (f) => f.path.toLowerCase().endsWith('.exe'),
              );
          for (final f in files) {
            final exeName = p.basename(f.path).toLowerCase();
            if (!_uninstallerKeywords.contains(exeName) && !_excludedExeNames.contains(exeName)) {
              return f.path;
            }
          }
        } catch (_) {}
      }
    }

    return null;
  }

  // --- Environment & Provider Helpers ---

  String _getSelfExecutablePath() {
    if (selfExecutablePathProvider != null) {
      return selfExecutablePathProvider!();
    }
    try {
      return Platform.resolvedExecutable;
    } catch (_) {
      return '';
    }
  }

  List<String> _getStartMenuDirectories() {
    if (startMenuDirectoriesProvider != null) {
      return startMenuDirectoriesProvider!();
    }

    final dirs = <String>[];
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      dirs.add(p.join(appData, 'Microsoft', 'Windows', 'Start Menu', 'Programs'));
      dirs.add(p.join(appData, 'Microsoft', 'Windows', 'Start Menu'));
    }

    final programData = Platform.environment['PROGRAMDATA'];
    if (programData != null && programData.isNotEmpty) {
      dirs.add(p.join(programData, 'Microsoft', 'Windows', 'Start Menu', 'Programs'));
      dirs.add(p.join(programData, 'Microsoft', 'Windows', 'Start Menu'));
    }

    return dirs;
  }

  List<String> _getWindowsAppsDirectories() {
    if (windowsAppsDirectoryProvider != null) {
      return windowsAppsDirectoryProvider!();
    }

    final dirs = <String>[];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      dirs.add(p.join(localAppData, 'Microsoft', 'WindowsApps'));
    }

    return dirs;
  }

  List<Map<String, String>> _getRegistryEntries() {
    if (registryEntriesProvider != null) {
      return registryEntriesProvider!();
    }

    final entries = <Map<String, String>>[];
    final roots = [
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall',
      r'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall',
      r'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    ];

    for (final root in roots) {
      try {
        final res = Process.runSync('reg', ['query', root, '/s']);
        if (res.exitCode != 0) continue;

        final lines = (res.stdout as String).split('\r\n');
        Map<String, String>? current;

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith(r'HKEY_')) {
            if (current != null && current.containsKey('DisplayName')) {
              entries.add(current);
            }
            current = <String, String>{};
          } else if (current != null && trimmed.isNotEmpty) {
            final match = RegExp(r'^(\S+)\s+(REG_[A-Z_]+)\s*(.*)$').firstMatch(trimmed);
            if (match != null) {
              final valName = match.group(1);
              final valData = match.group(3)?.trim() ?? '';
              if (valName != null) {
                current[valName] = valData;
              }
            }
          }
        }
        if (current != null && current.containsKey('DisplayName')) {
          entries.add(current);
        }
      } catch (e) {
        debugPrint('Registry query error on root $root: $e');
      }
    }

    return entries;
  }

  bool _fileExists(String path) {
    if (fileExistsProvider != null) {
      return fileExistsProvider!(path);
    }
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }
}
