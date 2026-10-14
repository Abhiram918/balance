import 'package:flutter/foundation.dart';
import 'usage_repository.dart';
import 'windows_startup_manager.dart';

/// Service managing user settings persistence, theme, and startup configuration.
class SettingsService extends ChangeNotifier {
  final UsageRepository repository;

  bool _darkMode = true; // Preserving dark appearance as default
  double _idleTimeoutMinutes = 2.0;
  bool _notifications = true;
  bool _launchOnStartup = false;
  bool _isInitialized = false;

  SettingsService({required this.repository});

  bool get darkMode => _darkMode;
  double get idleTimeoutMinutes => _idleTimeoutMinutes;
  bool get notifications => _notifications;
  bool get launchOnStartup => _launchOnStartup;
  bool get isInitialized => _isInitialized;

  /// Loads saved settings from the database and checks startup registration.
  Future<void> init() async {
    try {
      final savedDark = await repository.getSetting('darkMode');
      if (savedDark != null) {
        _darkMode = savedDark == 'true';
      }

      final savedIdle = await repository.getSetting('idleTimeoutMinutes');
      if (savedIdle != null) {
        final parsed = double.tryParse(savedIdle);
        if (parsed != null && parsed >= 1.0 && parsed <= 15.0) {
          _idleTimeoutMinutes = parsed;
        }
      }

      final savedNotif = await repository.getSetting('notifications');
      if (savedNotif != null) {
        _notifications = savedNotif == 'true';
      }

      // Verify the actual registration state on Windows
      _launchOnStartup = WindowsStartupManager.isStartupEnabled();
    } catch (_) {
      // Fall back to safe defaults if reading fails
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Sets dark mode and persists preference.
  Future<void> setDarkMode(bool value) async {
    if (_darkMode == value) return;
    _darkMode = value;
    notifyListeners();
    await repository.setSetting('darkMode', value.toString());
  }

  /// Sets idle timeout in minutes and persists preference.
  Future<void> setIdleTimeoutMinutes(double value) async {
    if (_idleTimeoutMinutes == value) return;
    _idleTimeoutMinutes = value;
    notifyListeners();
    await repository.setSetting('idleTimeoutMinutes', value.toString());
  }

  /// Sets notifications enabled state and persists preference.
  Future<void> setNotifications(bool value) async {
    if (_notifications == value) return;
    _notifications = value;
    notifyListeners();
    await repository.setSetting('notifications', value.toString());
  }

  /// Configures launch on startup using the Windows Registry Run key.
  /// Only updates state and persistence if registration succeeds.
  Future<bool> setLaunchOnStartup(bool value) async {
    final success = await WindowsStartupManager.setStartupEnabled(value);
    if (success) {
      _launchOnStartup = value;
      notifyListeners();
      await repository.setSetting('launchOnStartup', value.toString());
      return true;
    } else {
      // Refresh to actual verified state
      _launchOnStartup = WindowsStartupManager.isStartupEnabled();
      notifyListeners();
      return false;
    }
  }
}
