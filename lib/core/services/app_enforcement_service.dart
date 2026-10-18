import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/app_block_event.dart';
import '../models/app_limit.dart';
import '../models/focus_preset.dart';
import 'focus_notification_service.dart';
import 'windows_process_manager.dart';

/// Result summary of an enforcement operation.
class EnforcementResult {
  final String appName;
  final bool isEnforced;
  final int discoveredProcesses;
  final int gracefullyClosed;
  final int terminated;
  final String? message;

  const EnforcementResult({
    required this.appName,
    required this.isEnforced,
    this.discoveredProcesses = 0,
    this.gracefullyClosed = 0,
    this.terminated = 0,
    this.message,
  });

  bool get hadAction => discoveredProcesses > 0;
}

/// Dedicated Windows application restriction and enforcement service.
///
/// Independently manages two restriction sources:
/// 1. Daily app limits (exceeded usage allowance reset daily at midnight).
/// 2. Focus Mode sessions (per-preset blocked apps enforced while active focus is running).
///
/// Ensures:
/// - Focus restrictions never clear or alter daily limit restrictions.
/// - Ending, pausing, or recovering focus sessions leaves daily limit restrictions intact.
/// - Daily midnight resets clear daily limits without clearing active focus session restrictions.
/// - Graceful window close (WM_CLOSE) with fallback to process termination.
/// - Throttled desktop notifications and user warning dialogs without spam.
class AppEnforcementService extends ChangeNotifier {
  final ProcessManager processManager;
  final Duration gracePeriod;
  final FocusNotificationService? notificationService;
  DateTime Function() _clock;

  // 1. Daily limits state
  final Set<String> _dailyLimitRestrictedApps = {};
  final Map<String, DateTime> _lastDailyEnforcementTime = {};
  String _activeDateKey = '';

  // 2. Focus session restrictions state
  final List<FocusPresetBlockedApp> _focusBlockedApps = [];
  bool _isFocusEnforcing = false;
  String? _activeFocusPresetName;
  Duration? _activeFocusRemainingDuration;
  final Map<String, DateTime> _lastFocusEnforcementTime = {};
  final Map<String, DateTime> _lastFocusNotificationTime = {};

  final Duration _cooldownDuration = const Duration(seconds: 2);
  final Duration _notificationCooldownDuration = const Duration(seconds: 30);

  final StreamController<AppBlockEvent> _blockEventController =
      StreamController<AppBlockEvent>.broadcast();

  /// Stream of block events emitted whenever an application is enforced or reopened.
  Stream<AppBlockEvent> get blockEvents => _blockEventController.stream;

  AppEnforcementService({
    ProcessManager? processManager,
    this.gracePeriod = const Duration(milliseconds: 1500),
    this.notificationService,
    DateTime Function()? clock,
  })  : processManager = processManager ?? WindowsProcessManager(),
        _clock = clock ?? DateTime.now {
    _syncDateKey();
  }

  void setClock(DateTime Function() clock) {
    _clock = clock;
    _checkDailyReset();
  }

  /// Combined set of all currently restricted application names across both daily limits
  /// and active focus session.
  Set<String> get restrictedApps {
    _checkDailyReset();
    final combined = <String>{..._dailyLimitRestrictedApps};
    if (_isFocusEnforcing) {
      for (final app in _focusBlockedApps) {
        combined.add(app.appName.trim().toLowerCase());
      }
    }
    return Set.unmodifiable(combined);
  }

  /// Application names currently restricted specifically by daily limits.
  Set<String> get dailyLimitRestrictedApps {
    _checkDailyReset();
    return Set.unmodifiable(_dailyLimitRestrictedApps);
  }

  /// Blocked applications currently configured for active focus mode.
  List<FocusPresetBlockedApp> get focusBlockedApps => List.unmodifiable(_focusBlockedApps);

  /// Whether Focus Mode enforcement is currently actively restricting applications.
  bool get isFocusEnforcing => _isFocusEnforcing;

  /// Active focus preset name (if focus enforcement is active).
  String? get activeFocusPresetName => _activeFocusPresetName;

  /// Active focus remaining duration (if focus enforcement is active).
  Duration? get activeFocusRemainingDuration => _activeFocusRemainingDuration;

  /// Returns whether the specified application currently has active daily limit restriction.
  bool isDailyLimitRestricted(String appName) {
    _checkDailyReset();
    return _dailyLimitRestrictedApps.contains(appName.trim().toLowerCase());
  }

  /// Returns whether the specified application is restricted by active Focus Mode.
  bool isFocusRestricted(String appName, {String? exePath}) {
    if (!_isFocusEnforcing || _focusBlockedApps.isEmpty) return false;
    for (final blocked in _focusBlockedApps) {
      if (matchesBlockedApp(
        blockedApp: blocked,
        targetAppName: appName,
        targetExePath: exePath ?? '',
      )) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether the specified application currently has active enforcement
  /// restricting it from either daily limits or an active focus session.
  bool isAppRestricted(String appName, {String? exePath}) {
    return isDailyLimitRestricted(appName) || isFocusRestricted(appName, exePath: exePath);
  }

  /// Removes active daily limit restriction for an application.
  /// Never modifies focus session restrictions.
  void removeRestriction(String appName) {
    final key = appName.trim().toLowerCase();
    if (_dailyLimitRestrictedApps.remove(key)) {
      notifyListeners();
    }
  }

  /// Dispatches an [AppBlockEvent] to all listening UI overlays.
  void dispatchBlockEvent(AppBlockEvent event) {
    if (!_blockEventController.isClosed) {
      _blockEventController.add(event);
    }
  }

  /// Recalculates and updates active daily restrictions across all limits based on recorded usage.
  void evaluateEnforcements(List<AppLimit> limits, Map<String, Duration> usageMap) {
    _checkDailyReset();

    for (final limit in limits) {
      if (!limit.isEnabled || !limit.isEnforced) {
        _dailyLimitRestrictedApps.remove(limit.appName.trim().toLowerCase());
        continue;
      }

      final key = limit.appName.trim().toLowerCase();
      Duration used = Duration.zero;
      for (final entry in usageMap.entries) {
        if (entry.key.trim().toLowerCase() == key) {
          used = entry.value;
          break;
        }
      }

      if (used >= limit.limitDuration) {
        _dailyLimitRestrictedApps.add(key);
      } else {
        _dailyLimitRestrictedApps.remove(key);
      }
    }

    notifyListeners();
  }

  // --- Focus Mode Restriction Management ---

  /// Updates focus session restrictions.
  /// When [isEnforcing] is true, activates focus restrictions. If [closeRunningNow] is true,
  /// immediately discovers and closes running instances of all blocked apps.
  Future<void> setFocusRestrictions({
    required List<FocusPresetBlockedApp> blockedApps,
    String? presetName,
    Duration? remainingDuration,
    bool isEnforcing = true,
    bool closeRunningNow = true,
  }) async {
    _focusBlockedApps
      ..clear()
      ..addAll(blockedApps);
    _isFocusEnforcing = isEnforcing;
    _activeFocusPresetName = presetName;
    _activeFocusRemainingDuration = remainingDuration;
    notifyListeners();

    if (_isFocusEnforcing && closeRunningNow && _focusBlockedApps.isNotEmpty) {
      await enforceAllFocusApps();
    }
  }

  /// Clears focus session restrictions (e.g. when session ends, pauses, or resets).
  /// Preserves all daily limit restrictions completely intact.
  void clearFocusRestrictions() {
    if (!_isFocusEnforcing && _focusBlockedApps.isEmpty) return;
    _isFocusEnforcing = false;
    _focusBlockedApps.clear();
    _activeFocusPresetName = null;
    _activeFocusRemainingDuration = null;
    _lastFocusEnforcementTime.clear();
    notifyListeners();
  }

  /// Discovers and closes running instances of all currently active focus-blocked apps.
  Future<void> enforceAllFocusApps() async {
    if (!_isFocusEnforcing) return;
    for (final app in _focusBlockedApps) {
      await _closeProcessesForApp(
        appName: app.appName,
        exePath: app.exePath,
      );
    }
  }

  /// Enforces Focus Mode restriction on a specific application.
  /// Closes running instances, dispatches the Focus Block Dialog event, and
  /// sends a desktop notification (throttled to avoid spam).
  Future<EnforcementResult> enforceFocusApp(
    FocusPresetBlockedApp app, {
    String? presetName,
    Duration? remainingDuration,
    bool triggerDialog = true,
    bool triggerNotification = true,
  }) async {
    final cleanName = app.appName.trim().toLowerCase();
    final now = _clock();

    // Check enforcement cooldown to prevent rapid thrashing loops
    final lastTime = _lastFocusEnforcementTime[cleanName];
    if (lastTime != null && now.difference(lastTime) < _cooldownDuration) {
      return EnforcementResult(
        appName: app.appName,
        isEnforced: true,
        message: 'Focus enforcement is in active cooldown for ${app.appName}.',
      );
    }
    _lastFocusEnforcementTime[cleanName] = now;

    final closeResult = await _closeProcessesForApp(
      appName: app.appName,
      exePath: app.exePath,
    );

    final result = EnforcementResult(
      appName: app.appName,
      isEnforced: true,
      discoveredProcesses: closeResult.discovered,
      gracefullyClosed: closeResult.gracefullyClosed,
      terminated: closeResult.terminated,
      message:
          'Enforced focus block on ${app.appName}. Discovered: ${closeResult.discovered}, Gracefully closed: ${closeResult.gracefullyClosed}, Terminated: ${closeResult.terminated}.',
    );

    // Dispatch Block Dialog event if requested
    if (triggerDialog) {
      final effectiveRemaining =
          remainingDuration ?? _activeFocusRemainingDuration ?? Duration.zero;
      final event = AppBlockEvent(
        appName: app.appName,
        exePath: app.exePath,
        reason: AppBlockReason.focusSession,
        focusPresetName: presetName ?? _activeFocusPresetName,
        remainingFocusDuration: effectiveRemaining,
        resetTime: now.add(effectiveRemaining),
        timestamp: now,
      );
      dispatchBlockEvent(event);
    }

    // Trigger desktop notification if requested and not throttled
    if (triggerNotification && notificationService != null) {
      final lastNotif = _lastFocusNotificationTime[cleanName];
      if (lastNotif == null || now.difference(lastNotif) >= _notificationCooldownDuration) {
        _lastFocusNotificationTime[cleanName] = now;
        await notificationService!.notifyFocusAppBlocked(
          appName: app.appName,
          presetName: presetName ?? _activeFocusPresetName,
        );
      }
    }

    return result;
  }

  // --- Daily Limit Enforcement ---

  /// Enforces a daily limit by closing all running instances of the restricted application.
  /// Dispatches an [AppBlockEvent] to request the Flutter dialog popup.
  Future<EnforcementResult> enforceLimit(
    AppLimit limit, {
    Duration? usedDuration,
    bool triggerDialog = true,
  }) async {
    _checkDailyReset();

    if (!limit.isEnabled || !limit.isEnforced) {
      return EnforcementResult(
        appName: limit.appName,
        isEnforced: false,
        message: 'Enforcement is disabled for this limit.',
      );
    }

    final cleanName = limit.appName.trim().toLowerCase();
    _dailyLimitRestrictedApps.add(cleanName);
    notifyListeners();

    // Check enforcement debounce/cooldown to prevent rapid thrashing loops
    final now = _clock();
    final lastTime = _lastDailyEnforcementTime[cleanName];
    if (lastTime != null && now.difference(lastTime) < _cooldownDuration) {
      return EnforcementResult(
        appName: limit.appName,
        isEnforced: true,
        message: 'Enforcement is in active cooldown for ${limit.appName}.',
      );
    }
    _lastDailyEnforcementTime[cleanName] = now;

    final closeResult = await _closeProcessesForApp(
      appName: limit.appName,
      exePath: limit.exePath,
    );

    final result = EnforcementResult(
      appName: limit.appName,
      isEnforced: true,
      discoveredProcesses: closeResult.discovered,
      gracefullyClosed: closeResult.gracefullyClosed,
      terminated: closeResult.terminated,
      message:
          'Enforced limit on ${limit.appName}. Discovered: ${closeResult.discovered}, Gracefully closed: ${closeResult.gracefullyClosed}, Terminated: ${closeResult.terminated}.',
    );

    // Dispatch Block Dialog event if requested and applicable
    if (triggerDialog) {
      final nextMidnight = DateTime(now.year, now.month, now.day + 1);
      final event = AppBlockEvent(
        appName: limit.appName,
        exePath: limit.exePath,
        reason: AppBlockReason.dailyLimit,
        limitDuration: limit.limitDuration,
        usedDuration: usedDuration ?? limit.limitDuration,
        resetTime: nextMidnight,
        timestamp: now,
      );
      dispatchBlockEvent(event);
    }

    return result;
  }

  // --- Foreground Detection Hook ---

  /// Hook called whenever a window is foregrounded or reopened.
  /// Checks focus session restrictions first, then daily limit restrictions.
  Future<void> onForegroundAppDetected({
    required String appName,
    required String exePath,
    required List<AppLimit> limits,
    required Duration todayUsage,
  }) async {
    _checkDailyReset();

    // 1. Check Focus Mode restrictions
    if (_isFocusEnforcing && _focusBlockedApps.isNotEmpty) {
      FocusPresetBlockedApp? matchingBlockedApp;
      for (final blocked in _focusBlockedApps) {
        if (matchesBlockedApp(
          blockedApp: blocked,
          targetAppName: appName,
          targetExePath: exePath,
        )) {
          matchingBlockedApp = blocked;
          break;
        }
      }

      if (matchingBlockedApp != null) {
        debugPrint('Focus-blocked application detected: $appName. Closing and prompting dialog...');
        await enforceFocusApp(
          matchingBlockedApp,
          presetName: _activeFocusPresetName,
          remainingDuration: _activeFocusRemainingDuration,
          triggerDialog: true,
          triggerNotification: true,
        );
        return;
      }
    }

    // 2. Check Daily Limit restrictions
    final cleanName = appName.trim().toLowerCase();
    AppLimit? matchingLimit;
    for (final l in limits) {
      if (_matchesApp(l, appName, exePath)) {
        matchingLimit = l;
        break;
      }
    }

    if (matchingLimit == null || !matchingLimit.isEnabled || !matchingLimit.isEnforced) {
      return;
    }

    if (todayUsage >= matchingLimit.limitDuration || _dailyLimitRestrictedApps.contains(cleanName)) {
      debugPrint('Enforced application reopened while exceeded: $appName. Closing and prompting dialog...');
      await enforceLimit(
        matchingLimit,
        usedDuration: todayUsage,
        triggerDialog: true,
      );
    }
  }

  // --- Process Close Helper ---

  Future<({int discovered, int gracefullyClosed, int terminated})> _closeProcessesForApp({
    required String appName,
    String? exePath,
  }) async {
    final processes = await processManager.findProcessesForApp(
      appName: appName,
      exePath: exePath,
    );

    int gracefullyClosed = 0;
    int terminated = 0;

    if (processes.isNotEmpty) {
      // 1. Attempt graceful close on all discovered processes
      for (final process in processes) {
        try {
          final closed = await processManager.closeProcessGracefully(process);
          if (closed) {
            gracefullyClosed++;
          }
        } catch (e) {
          debugPrint('Graceful close error for ${process.exeName}: $e');
        }
      }

      // 2. Wait for the grace period to allow the app to save/exit gracefully
      if (gracePeriod > Duration.zero) {
        await Future.delayed(gracePeriod);
      }

      // 3. Fall back to terminating any processes that remain alive
      for (final process in processes) {
        try {
          final isRunning = await processManager.isProcessRunning(process.pid);
          if (isRunning) {
            final killed = await processManager.terminateProcess(process.pid);
            if (killed) {
              terminated++;
            }
          }
        } catch (e) {
          debugPrint('Termination error for PID ${process.pid}: $e');
        }
      }
    }

    return (
      discovered: processes.length,
      gracefullyClosed: gracefullyClosed,
      terminated: terminated,
    );
  }

  // --- App Matching Helpers ---

  bool matchesBlockedApp({
    required FocusPresetBlockedApp blockedApp,
    required String targetAppName,
    required String targetExePath,
  }) {
    final cleanBlocked = blockedApp.appName.trim().toLowerCase();
    final cleanTarget = targetAppName.trim().toLowerCase();
    if (cleanBlocked.isEmpty) return false;
    if (cleanBlocked == cleanTarget) return true;

    if (blockedApp.exePath != null &&
        blockedApp.exePath!.trim().isNotEmpty &&
        targetExePath.trim().isNotEmpty) {
      if (blockedApp.exePath!.trim().toLowerCase() == targetExePath.trim().toLowerCase()) {
        return true;
      }
    }

    if (targetExePath.isNotEmpty) {
      final exeName = targetExePath.split(r'\').last.toLowerCase();
      final baseName = exeName.endsWith('.exe')
          ? exeName.substring(0, exeName.length - 4)
          : exeName;
      if (cleanBlocked == exeName || cleanBlocked == baseName) {
        return true;
      }
    }

    // Common alias matching
    if (cleanBlocked == 'google chrome' && cleanTarget == 'chrome') return true;
    if (cleanBlocked == 'visual studio code' && cleanTarget == 'code') return true;
    if (cleanBlocked == 'telegram desktop' && cleanTarget == 'telegram') return true;
    if (cleanBlocked == 'microsoft edge' && cleanTarget == 'msedge') return true;
    if (cleanBlocked == 'whatsapp' && (cleanTarget == 'whatsapp.root' || cleanTarget == 'whatsapp')) return true;
    if (cleanBlocked == 'snipping tool' && cleanTarget == 'snippingtool') return true;
    if (cleanBlocked == 'mozilla firefox' && cleanTarget == 'firefox') return true;

    return false;
  }

  bool _matchesApp(AppLimit limit, String appName, String exePath) {
    final cleanLimitApp = limit.appName.trim().toLowerCase();
    final cleanTargetApp = appName.trim().toLowerCase();
    if (cleanLimitApp == cleanTargetApp) return true;

    if (limit.exePath != null && limit.exePath!.isNotEmpty && exePath.isNotEmpty) {
      if (limit.exePath!.trim().toLowerCase() == exePath.trim().toLowerCase()) {
        return true;
      }
    }

    if (exePath.isNotEmpty) {
      final exeName = exePath.split(r'\').last.toLowerCase();
      final baseName = exeName.endsWith('.exe')
          ? exeName.substring(0, exeName.length - 4)
          : exeName;
      if (cleanLimitApp == exeName || cleanLimitApp == baseName) {
        return true;
      }
    }

    return false;
  }

  void _syncDateKey() {
    _activeDateKey = DateFormat('yyyy-MM-dd').format(_clock());
  }

  void _checkDailyReset() {
    final currentDateKey = DateFormat('yyyy-MM-dd').format(_clock());
    if (currentDateKey != _activeDateKey) {
      _activeDateKey = currentDateKey;
      _dailyLimitRestrictedApps.clear();
      _lastDailyEnforcementTime.clear();
      // Note: Focus session restrictions are intentionally NOT cleared on calendar midnight reset.
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _blockEventController.close();
    super.dispose();
  }
}
