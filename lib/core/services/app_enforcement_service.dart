import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/app_block_event.dart';
import '../models/app_limit.dart';
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

/// Dedicated Windows application-limit enforcement service.
/// Safely identifies, gracefully requests close, and falls back to terminating
/// target processes when an application's daily usage allowance is exceeded.
/// Monitors for and blocks reopening across local calendar days, and emits
/// user-facing block dialog events.
class AppEnforcementService extends ChangeNotifier {
  final ProcessManager processManager;
  final Duration gracePeriod;
  DateTime Function() _clock;

  final Set<String> _restrictedApps = {};
  final Map<String, DateTime> _lastEnforcementTime = {};
  String _activeDateKey = '';
  final Duration _cooldownDuration = const Duration(seconds: 2);

  final StreamController<AppBlockEvent> _blockEventController =
      StreamController<AppBlockEvent>.broadcast();

  /// Stream of block events emitted whenever an application limit is enforced
  /// or when a user attempts to launch an exceeded application.
  Stream<AppBlockEvent> get blockEvents => _blockEventController.stream;

  AppEnforcementService({
    ProcessManager? processManager,
    this.gracePeriod = const Duration(milliseconds: 1500),
    DateTime Function()? clock,
  })  : processManager = processManager ?? WindowsProcessManager(),
        _clock = clock ?? DateTime.now {
    _syncDateKey();
  }

  void setClock(DateTime Function() clock) {
    _clock = clock;
    _checkDailyReset();
  }

  Set<String> get restrictedApps => Set.unmodifiable(_restrictedApps);

  /// Returns whether the specified application currently has active enforcement
  /// restricting it for the current calendar day.
  bool isAppRestricted(String appName) {
    _checkDailyReset();
    return _restrictedApps.contains(appName.trim().toLowerCase());
  }

  /// Removes active restriction for an application (e.g. when limit is deleted or disabled).
  void removeRestriction(String appName) {
    final key = appName.trim().toLowerCase();
    if (_restrictedApps.remove(key)) {
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
        _restrictedApps.remove(limit.appName.trim().toLowerCase());
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
        _restrictedApps.add(key);
      } else {
        _restrictedApps.remove(key);
      }
    }

    notifyListeners();
  }

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
    _restrictedApps.add(cleanName);
    notifyListeners();

    // Check enforcement debounce/cooldown to prevent rapid thrashing loops
    final now = _clock();
    final lastTime = _lastEnforcementTime[cleanName];
    if (lastTime != null && now.difference(lastTime) < _cooldownDuration) {
      return EnforcementResult(
        appName: limit.appName,
        isEnforced: true,
        message: 'Enforcement is in active cooldown for ${limit.appName}.',
      );
    }
    _lastEnforcementTime[cleanName] = now;

    // Discover matching processes
    final processes = await processManager.findProcessesForApp(
      appName: limit.appName,
      exePath: limit.exePath,
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

    final result = EnforcementResult(
      appName: limit.appName,
      isEnforced: true,
      discoveredProcesses: processes.length,
      gracefullyClosed: gracefullyClosed,
      terminated: terminated,
      message: 'Enforced limit on ${limit.appName}. Discovered: ${processes.length}, Gracefully closed: $gracefullyClosed, Terminated: $terminated.',
    );

    // Dispatch Block Dialog event if requested and applicable
    if (triggerDialog) {
      final nextMidnight = DateTime(now.year, now.month, now.day + 1);
      final event = AppBlockEvent(
        appName: limit.appName,
        exePath: limit.exePath,
        limitDuration: limit.limitDuration,
        usedDuration: usedDuration ?? limit.limitDuration,
        resetTime: nextMidnight,
        timestamp: now,
      );
      dispatchBlockEvent(event);
    }

    return result;
  }

  /// Hook called whenever a window is foregrounded or reopened.
  /// If the foreground application is restricted, immediately executes enforcement
  /// and requests the block dialog to appear.
  Future<void> onForegroundAppDetected({
    required String appName,
    required String exePath,
    required List<AppLimit> limits,
    required Duration todayUsage,
  }) async {
    _checkDailyReset();

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

    if (todayUsage >= matchingLimit.limitDuration || _restrictedApps.contains(cleanName)) {
      debugPrint('Enforced application reopened while exceeded: $appName. Closing and prompting dialog...');
      await enforceLimit(
        matchingLimit,
        usedDuration: todayUsage,
        triggerDialog: true,
      );
    }
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
      _restrictedApps.clear();
      _lastEnforcementTime.clear();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _blockEventController.close();
    super.dispose();
  }
}
