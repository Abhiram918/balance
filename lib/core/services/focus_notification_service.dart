import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:win32/win32.dart';
import '../models/focus_session.dart';
import 'settings_service.dart';

class FocusNotificationService {
  final SettingsService? settingsService;
  bool _initialized = false;

  FocusNotificationService({this.settingsService});

  Future<void> init() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    try {
      await localNotifier.setup(
        appName: 'Balance',
        shortcutPolicy: ShortcutPolicy.ignore,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('LocalNotifier initialization failed: $e');
      _initialized = false;
    }
  }

  Future<bool> notifySessionCompleted({
    required FocusSessionType type,
    required bool completedNaturally,
    bool soundEnabled = true,
  }) async {
    // Respect user's notification setting
    if (settingsService != null && !settingsService!.notifications) {
      return false;
    }

    final String title;
    final String body;

    if (type == FocusSessionType.focus) {
      title = completedNaturally ? 'Focus Session Completed! 🎯' : 'Focus Session Ended';
      body = completedNaturally
          ? 'Great job staying in the zone! Time to take a well-deserved break.'
          : 'Focus session was stopped early.';
    } else {
      title = 'Break Finished! ☕';
      body = 'Your break is over. Ready to start your next focus session?';
    }

    // Audible alert using Win32 API
    if (soundEnabled && Platform.isWindows) {
      try {
        MessageBeep(MB_ICONASTERISK);
      } catch (_) {}
    }

    // Desktop notification via local_notifier
    if (_initialized) {
      try {
        final notification = LocalNotification(
          title: title,
          body: body,
        );
        await notification.show();
        return true;
      } catch (e) {
        debugPrint('Failed to show desktop notification: $e');
        return false;
      }
    }
    return true;
  }

  /// Dispatches a notification when an application reaches its configured warning threshold.
  Future<bool> notifyAppLimitWarning({
    required String appName,
    required Duration used,
    required Duration limit,
    required int warningPercentage,
  }) async {
    if (settingsService != null && !settingsService!.notifications) {
      return false;
    }

    final title = '$appName Usage Warning ⚠️';
    final body = '$appName has reached $warningPercentage% of its daily limit (${_formatDuration(used)} / ${_formatDuration(limit)}).';

    if (Platform.isWindows) {
      try {
        MessageBeep(MB_ICONASTERISK);
      } catch (_) {}
    }

    return _showToast(title: title, body: body);
  }

  /// Dispatches a notification when an application reaches or exceeds its daily allowance.
  Future<bool> notifyAppLimitReached({
    required String appName,
    required Duration used,
    required Duration limit,
  }) async {
    if (settingsService != null && !settingsService!.notifications) {
      return false;
    }

    final title = '$appName Limit Reached! 🛑';
    final body = '$appName has reached its daily limit of ${_formatDuration(limit)} (${_formatDuration(used)} used).';

    if (Platform.isWindows) {
      try {
        MessageBeep(MB_ICONEXCLAMATION);
      } catch (_) {}
    }

    return _showToast(title: title, body: body);
  }

  Future<bool> _showToast({required String title, required String body}) async {
    if (_initialized) {
      try {
        final notification = LocalNotification(
          title: title,
          body: body,
        );
        await notification.show();
        return true;
      } catch (e) {
        debugPrint('Failed to show desktop notification: $e');
        return false;
      }
    }
    return true;
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }
}
