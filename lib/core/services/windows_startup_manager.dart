import 'dart:io';

/// Manages per-user Windows Startup registration via the Run registry key.
/// Safe and does not require administrator privileges.
class WindowsStartupManager {
  static const String appName = 'Balance';
  static const String runKeyPath = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Checks if Balance is currently registered in Windows Startup.
  static bool isStartupEnabled() {
    if (!Platform.isWindows) return false;
    try {
      final result = Process.runSync('reg', [
        'query',
        runKeyPath,
        '/v',
        appName,
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Registers or unregisters Balance from Windows Startup.
  /// Handles paths with spaces safely by enclosing the executable path in double quotes.
  static Future<bool> setStartupEnabled(bool enable) async {
    if (!Platform.isWindows) return false;
    try {
      if (enable) {
        final exePath = Platform.resolvedExecutable;
        final result = await Process.run('reg', [
          'add',
          runKeyPath,
          '/v',
          appName,
          '/t',
          'REG_SZ',
          '/d',
          '"$exePath"',
          '/f',
        ]);
        return result.exitCode == 0;
      } else {
        final result = await Process.run('reg', [
          'delete',
          runKeyPath,
          '/v',
          appName,
          '/f',
        ]);
        return result.exitCode == 0 || !isStartupEnabled();
      }
    } catch (_) {
      return false;
    }
  }
}
