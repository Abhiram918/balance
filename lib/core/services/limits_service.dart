import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/app_block_event.dart';
import '../models/app_limit.dart';
import '../models/discovered_app.dart';
import '../models/usage_data.dart';
import 'app_enforcement_service.dart';
import 'focus_notification_service.dart';
import 'usage_calculator.dart';
import 'usage_repository.dart';
import 'windows_app_discovery_service.dart';
import 'windows_usage_tracker.dart';

/// Dedicated controller managing application usage limits, threshold evaluations,
/// SQLite persistence, deduplicated desktop warning notifications, and application enforcement.
class LimitsService extends ChangeNotifier {
  final UsageRepository repository;
  final FocusNotificationService? notificationService;
  final WindowsUsageTracker? tracker;
  final AppEnforcementService? enforcementService;
  final WindowsAppDiscoveryService? discoveryService;
  DateTime Function() _clock;

  List<AppLimit> _limits = [];
  Map<String, Duration> _todayAppUsage = {};
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDisposed = false;

  String? _cachedDateKey;
  final Set<String> _sentNotificationCache = {};

  /// Stream of application block events forwarded from [AppEnforcementService].
  Stream<AppBlockEvent> get blockEvents =>
      enforcementService?.blockEvents ?? const Stream.empty();

  LimitsService({
    required this.repository,
    this.notificationService,
    this.tracker,
    this.enforcementService,
    this.discoveryService,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    tracker?.addListener(_onTrackerChanged);
  }

  void setClock(DateTime Function() clock) {
    _clock = clock;
    enforcementService?.setClock(clock);
  }

  List<AppLimit> get limits => List.unmodifiable(_limits);
  List<AppLimit> get enabledLimits => _limits.where((l) => l.isEnabled).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _onTrackerChanged() {
    if (_isDisposed) return;
    if (tracker != null && tracker!.todaySummary != null) {
      evaluateUsage(summary: tracker!.todaySummary);

      final currentApp = tracker!.currentAppName;
      final currentExe = tracker!.currentExePath;
      if (currentApp != null && currentExe != null && enforcementService != null) {
        final used = getUsageForApp(currentApp, exePath: currentExe);
        enforcementService!.onForegroundAppDetected(
          appName: currentApp,
          exePath: currentExe,
          limits: _limits,
          todayUsage: used,
        );
      }
    }
  }

  /// Initializes the service by loading saved limits and evaluating current usage.
  Future<void> init() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _limits = await repository.getAllLimits();

      if (tracker != null && tracker!.todaySummary != null) {
        await evaluateUsage(summary: tracker!.todaySummary);
      } else {
        await evaluateUsage();
      }
    } catch (e) {
      _errorMessage = 'Failed to load app limits: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Calculates today's usage for an application.
  /// Matches by display name or executable path/name.
  Duration getUsageForApp(String appName, {String? exePath}) {
    final key = appName.trim().toLowerCase();
    for (final entry in _todayAppUsage.entries) {
      if (entry.key.trim().toLowerCase() == key) {
        return entry.value;
      }
    }

    // Match by executable path or file name if provided
    if (exePath != null && exePath.trim().isNotEmpty) {
      final fileName = exePath.split(r'\').last.toLowerCase();
      final base = fileName.endsWith('.exe')
          ? fileName.substring(0, fileName.length - 4)
          : fileName;
      for (final entry in _todayAppUsage.entries) {
        final entryKey = entry.key.trim().toLowerCase();
        if (entryKey == fileName || entryKey == base) {
          return entry.value;
        }
      }

      if (discoveryService != null) {
        final friendly = discoveryService!.getFriendlyNameForExe(exePath).toLowerCase();
        for (final entry in _todayAppUsage.entries) {
          if (entry.key.trim().toLowerCase() == friendly) {
            return entry.value;
          }
        }
      }
    }

    return Duration.zero;
  }

  /// Calculates the remaining allowance for a limit. Never returns negative.
  Duration getRemainingAllowance(AppLimit limit) {
    final used = getUsageForApp(limit.appName, exePath: limit.exePath);
    final remaining = limit.limitDuration - used;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Returns whether a limit has been reached or exceeded today.
  bool isLimitExceeded(AppLimit limit) {
    final used = getUsageForApp(limit.appName, exePath: limit.exePath);
    return used >= limit.limitDuration;
  }

  /// Returns whether usage has reached the warning threshold.
  bool isNearLimit(AppLimit limit) {
    if (limit.limitDuration <= Duration.zero) return false;
    final used = getUsageForApp(limit.appName, exePath: limit.exePath);
    return used >= limit.warningDuration && used < limit.limitDuration;
  }

  /// Returns proportional progress (0.0 to 1.0).
  double getProgress(AppLimit limit) {
    if (limit.limitDuration.inSeconds <= 0) return 1.0;
    final used = getUsageForApp(limit.appName, exePath: limit.exePath);
    return (used.inSeconds / limit.limitDuration.inSeconds).clamp(0.0, 1.0);
  }

  /// Creates a new limit. Throws [ArgumentError] if invalid or duplicate.
  Future<AppLimit> createLimit({
    required String appName,
    String? exePath,
    required Duration duration,
    int warningPercentage = 80,
    bool isEnforced = false,
  }) async {
    final cleanName = appName.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('Application name cannot be empty');
    }
    if (duration.isNegative) {
      throw ArgumentError('Limit duration cannot be negative');
    }
    if (warningPercentage < 10 || warningPercentage > 100) {
      throw ArgumentError('Warning percentage must be between 10% and 100%');
    }

    // Check for duplicate
    final existing = await repository.getLimitByAppName(cleanName);
    if (existing != null) {
      throw ArgumentError('A limit for "$cleanName" already exists');
    }

    final now = _clock();
    final newLimit = AppLimit(
      appName: cleanName,
      exePath: exePath,
      limitDuration: duration,
      warningThresholdPercentage: warningPercentage,
      isEnabled: true,
      isEnforced: isEnforced,
      createdAt: now,
      updatedAt: now,
    );

    final inserted = await repository.insertLimit(newLimit);
    _limits = await repository.getAllLimits();
    await evaluateUsage();
    notifyListeners();
    return inserted;
  }

  /// Updates an existing limit.
  Future<void> updateLimit({
    required int id,
    required Duration duration,
    required int warningPercentage,
    bool? isEnabled,
    bool? isEnforced,
  }) async {
    if (duration.isNegative) {
      throw ArgumentError('Limit duration cannot be negative');
    }
    if (warningPercentage < 10 || warningPercentage > 100) {
      throw ArgumentError('Warning percentage must be between 10% and 100%');
    }

    final index = _limits.indexWhere((l) => l.id == id);
    if (index == -1) {
      throw ArgumentError('Limit not found');
    }

    final existing = _limits[index];
    final updated = existing.copyWith(
      limitDuration: duration,
      warningThresholdPercentage: warningPercentage,
      isEnabled: isEnabled ?? existing.isEnabled,
      isEnforced: isEnforced ?? existing.isEnforced,
      updatedAt: _clock(),
    );

    await repository.updateLimit(updated);
    _limits = await repository.getAllLimits();
    await evaluateUsage();
    notifyListeners();
  }

  /// Toggles whether a limit is enforced.
  Future<void> toggleEnforcement(int id, bool isEnforced) async {
    final index = _limits.indexWhere((l) => l.id == id);
    if (index == -1) return;

    final updated = _limits[index].copyWith(
      isEnforced: isEnforced,
      updatedAt: _clock(),
    );

    if (!isEnforced) {
      enforcementService?.removeRestriction(updated.appName);
    }

    _sentNotificationCache.removeWhere((k) => k.startsWith('$id:'));
    await repository.updateLimit(updated);
    _limits = await repository.getAllLimits();
    await evaluateUsage();
    notifyListeners();
  }

  /// Toggles whether a limit is enabled.
  Future<void> toggleLimit(int id, bool isEnabled) async {
    final index = _limits.indexWhere((l) => l.id == id);
    if (index == -1) return;

    final updated = _limits[index].copyWith(
      isEnabled: isEnabled,
      updatedAt: _clock(),
    );

    if (!isEnabled) {
      enforcementService?.removeRestriction(updated.appName);
    }

    _sentNotificationCache.removeWhere((k) => k.startsWith('$id:'));
    await repository.updateLimit(updated);
    _limits = await repository.getAllLimits();
    await evaluateUsage();
    notifyListeners();
  }

  /// Deletes a limit and clears its notification logs.
  Future<void> deleteLimit(int id) async {
    final limit = _limits.where((l) => l.id == id).firstOrNull;
    if (limit != null) {
      enforcementService?.removeRestriction(limit.appName);
    }
    _sentNotificationCache.removeWhere((k) => k.startsWith('$id:'));
    await repository.deleteLimit(id);
    _limits = List<AppLimit>.from(await repository.getAllLimits());
    notifyListeners();
  }

  /// Evaluates today's usage across all limited applications and sends
  /// deduplicated warning / limit-reached notifications.
  Future<void> evaluateUsage({DailyUsageSummary? summary}) async {
    final now = _clock();
    final dateKey = DateFormat('yyyy-MM-dd').format(now);
    if (_cachedDateKey != dateKey) {
      _cachedDateKey = dateKey;
      _sentNotificationCache.clear();
    }

    DailyUsageSummary activeSummary;
    if (summary != null) {
      activeSummary = summary;
    } else {
      final sessions = await repository.getSessionsForDay(now);
      activeSummary = UsageCalculator.calculateDailySummary(
        date: now,
        sessions: sessions,
      );
    }

    // Populate app usage map
    final Map<String, Duration> usageMap = {};
    for (final app in activeSummary.allApps) {
      usageMap[app.appName] = app.duration;
    }
    _todayAppUsage = usageMap;

    // Evaluate notifications for enabled limits
    for (final limit in enabledLimits) {
      if (limit.id == null) continue;
      final used = getUsageForApp(limit.appName, exePath: limit.exePath);

      final warningCacheKey = '${limit.id!}:warning:$dateKey';
      final exceededCacheKey = '${limit.id!}:exceeded:$dateKey';

      // 1. Warning Threshold Notification
      if (limit.limitDuration > Duration.zero &&
          used >= limit.warningDuration &&
          used < limit.limitDuration) {
        final alreadySent = _sentNotificationCache.contains(warningCacheKey) ||
            await repository.hasLimitNotificationBeenSent(
              limit.id!,
              'warning',
              dateKey,
            );
        if (alreadySent) {
          _sentNotificationCache.add(warningCacheKey);
        } else {
          final sent = await notificationService?.notifyAppLimitWarning(
                appName: limit.appName,
                used: used,
                limit: limit.limitDuration,
                warningPercentage: limit.warningThresholdPercentage,
              ) ??
              false;
          if (sent) {
            _sentNotificationCache.add(warningCacheKey);
            await repository.recordLimitNotificationSent(
              limit.id!,
              'warning',
              dateKey,
              now,
            );
          }
        }
      }

      // 2. Limit Reached Notification & Enforcement
      if (used >= limit.limitDuration) {
        final alreadySent = _sentNotificationCache.contains(exceededCacheKey) ||
            await repository.hasLimitNotificationBeenSent(
              limit.id!,
              'exceeded',
              dateKey,
            );
        if (alreadySent) {
          _sentNotificationCache.add(exceededCacheKey);
        } else {
          final sent = await notificationService?.notifyAppLimitReached(
                appName: limit.appName,
                used: used,
                limit: limit.limitDuration,
              ) ??
              false;
          if (sent) {
            _sentNotificationCache.add(exceededCacheKey);
            await repository.recordLimitNotificationSent(
              limit.id!,
              'exceeded',
              dateKey,
              now,
            );
          }
        }

        // Automatic Application-Limit Enforcement
        if (limit.isEnforced) {
          await enforcementService?.enforceLimit(
            limit,
            usedDuration: used,
            triggerDialog: !alreadySent,
          );
        }
      }
    }

    enforcementService?.evaluateEnforcements(_limits, _todayAppUsage);

    notifyListeners();
  }

  /// Discovers installed and legitimate tracked applications using [WindowsAppDiscoveryService].
  Future<List<DiscoveredApp>> getDiscoveredApplications({bool forceRefresh = false}) async {
    if (discoveryService != null) {
      try {
        return await discoveryService!.discoverApplications(forceRefresh: forceRefresh);
      } catch (e) {
        debugPrint('Error retrieving discovered apps: $e');
      }
    }

    // Fallback: discover from historical repository and live tracker
    final set = <String>{};
    try {
      final historical = await repository.getDistinctTrackedApps();
      set.addAll(historical);
    } catch (e) {
      debugPrint('Error retrieving distinct tracked apps: $e');
    }

    if (tracker != null && tracker!.todaySummary != null) {
      for (final app in tracker!.todaySummary!.allApps) {
        final clean = app.appName.trim();
        if (clean.isNotEmpty) {
          set.add(clean);
        }
      }
    }

    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list
        .map((name) => DiscoveredApp(
              id: name.toLowerCase(),
              displayName: name,
              source: AppDiscoverySource.historicalTracked,
              isPreviouslyTracked: true,
            ))
        .toList();
  }

  /// Returns distinct application names for backward compatibility.
  Future<List<String>> getAvailableApplications() async {
    final discovered = await getDiscoveredApplications();
    return discovered.map((a) => a.displayName).toList();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    tracker?.removeListener(_onTrackerChanged);
    super.dispose();
  }
}
