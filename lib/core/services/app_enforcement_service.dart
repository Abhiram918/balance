import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
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
/// Monitors for and blocks reopening across local calendar days.
class AppEnforcementService extends ChangeNotifier {
  final ProcessManager processManager;
  final Duration gracePeriod;
  DateTime Function() _clock;

  final Set<String> _restrictedApps = {};
  final Map<String, DateTime> _lastEnforcementTime = {};
  String _activeDateKey = '';
  final Duration _cooldownDuration = const Duration(seconds: 2);

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
  Future<EnforcementResult> enforceLimit(AppLimit limit) async {
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

    if (processes.isEmpty) {
      return EnforcementResult(
        appName: limit.appName,
        isEnforced: true,
        discoveredProcesses: 0,
        message: 'No running instances of ${limit.appName} found.',
      );
    }

    int gracefullyClosed = 0;
    int terminated = 0;

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

    return EnforcementResult(
      appName: limit.appName,
      isEnforced: true,
      discoveredProcesses: processes.length,
      gracefullyClosed: gracefullyClosed,
      terminated: terminated,
      message: 'Enforced limit on ${limit.appName}. Discovered: ${processes.length}, Gracefully closed: $gracefullyClosed, Terminated: $terminated.',
    );
  }

  /// Hook called whenever a window is foregrounded or reopened.
  /// If the foreground application is restricted, immediately executes enforcement.
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
      if (l.appName.trim().toLowerCase() == cleanName) {
        matchingLimit = l;
        break;
      }
    }

    if (matchingLimit == null || !matchingLimit.isEnabled || !matchingLimit.isEnforced) {
      return;
    }

    if (todayUsage >= matchingLimit.limitDuration || _restrictedApps.contains(cleanName)) {
      debugPrint('Enforced application reopened while exceeded: $appName. Closing...');
      await enforceLimit(matchingLimit);
    }
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
}
