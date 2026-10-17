import 'dart:math';
import 'package:intl/intl.dart';
import '../models/app_limit.dart';
import '../models/app_session.dart';
import '../models/application_analytics_models.dart';
import 'limits_service.dart';
import 'usage_calculator.dart';
import 'usage_repository.dart';
import 'windows_usage_tracker.dart';

/// Service responsible for calculating real, data-driven application usage analytics,
/// hourly & daily bar charts, multi-day aggregations, application list filtering,
/// and individual application analytics from SQLite and live tracking.
class ApplicationAnalyticsService {
  final UsageRepository repository;
  final WindowsUsageTracker? tracker;
  final LimitsService? limitsService;

  ApplicationAnalyticsService({
    required this.repository,
    this.tracker,
    this.limitsService,
  });

  /// Computes complete analytics for the main Applications page across [selection].
  ///
  /// An optional [referenceDate] can be supplied for deterministic unit testing.
  Future<ApplicationsAnalyticsResult> getApplicationsAnalytics({
    required DateRangeSelection selection,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Fetch sessions for the selected range from SQLite
    final rawSessions = await repository.getSessionsForRange(
      selection.startDate,
      selection.rangeEndExclusive,
    );
    final sessions = List<AppSession>.from(rawSessions);

    // 2. Merge in-progress live session if active and today falls within selection
    _mergeLiveSession(sessions, selection, today);

    // 3. Compute chart bars and application items
    return computeApplicationsAnalytics(
      selection: selection,
      sessions: sessions,
      referenceDate: now,
    );
  }

  /// Pure computation for the main Applications page analytics from a list of [sessions].
  ApplicationsAnalyticsResult computeApplicationsAnalytics({
    required DateRangeSelection selection,
    required List<AppSession> sessions,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Generate chart bars
    final List<UsageBarData> chartBars;
    if (selection.isHourly) {
      chartBars = aggregateHourlyUsage(
        date: selection.startDate,
        sessions: sessions,
        now: now,
      );
    } else {
      chartBars = aggregateDailyUsage(
        selection: selection,
        sessions: sessions,
        today: today,
      );
    }

    // 2. Aggregate per-application usage and session counts
    final apps = aggregateAppList(
      selection: selection,
      sessions: sessions,
    );

    // 3. Compute total screen time across all apps in this period
    // Use merged global intervals to ensure no double-counting
    final allIntervals = <TimeInterval>[];
    for (final s in sessions) {
      final clamped = UsageCalculator.clampToDay(
        s.startTime,
        s.endTime,
        selection.startDate,
        selection.rangeEndExclusive,
      );
      if (clamped != null) {
        allIntervals.add(clamped);
      }
    }
    final mergedGlobal = UsageCalculator.mergeIntervals(allIntervals);
    Duration totalUsage = Duration.zero;
    for (final interval in mergedGlobal) {
      totalUsage += interval.duration;
    }

    // 4. Summaries from limitsService
    final totalLimitedApps = limitsService?.enabledLimits.length ?? 0;
    final totalLimitReachedApps = limitsService?.enabledLimits
            .where((l) => limitsService!.isLimitExceeded(l))
            .length ??
        0;

    return ApplicationsAnalyticsResult(
      selection: selection,
      totalUsage: totalUsage,
      totalLimitedApps: totalLimitedApps,
      totalLimitReachedApps: totalLimitReachedApps,
      chartBars: chartBars,
      applications: apps,
    );
  }

  /// Computes detailed analytics for a single application across [selection].
  Future<SingleAppAnalyticsResult> getSingleAppAnalytics({
    required String appName,
    String? exePath,
    required DateRangeSelection selection,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Fetch sessions for the selected range
    final rawSessions = await repository.getSessionsForRange(
      selection.startDate,
      selection.rangeEndExclusive,
    );
    final sessions = List<AppSession>.from(rawSessions);

    // 2. Merge live session if applicable
    _mergeLiveSession(sessions, selection, today);

    // 3. Filter sessions specifically for this application
    final appKey = appName.trim().toLowerCase();
    final appSessions = sessions.where((s) {
      return s.appName.trim().toLowerCase() == appKey;
    }).toList();

    return computeSingleAppAnalytics(
      appName: appName,
      exePath: exePath,
      selection: selection,
      appSessions: appSessions,
      referenceDate: now,
    );
  }

  /// Pure computation of single-application analytics from its specific [appSessions].
  SingleAppAnalyticsResult computeSingleAppAnalytics({
    required String appName,
    String? exePath,
    required DateRangeSelection selection,
    required List<AppSession> appSessions,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Generate chart bars for this app only
    final List<UsageBarData> chartBars;
    if (selection.isHourly) {
      chartBars = aggregateHourlyUsage(
        date: selection.startDate,
        sessions: appSessions,
        now: now,
      );
    } else {
      chartBars = aggregateDailyUsage(
        selection: selection,
        sessions: appSessions,
        today: today,
      );
    }

    // 2. Calculate total usage for this app in the period
    final intervals = <TimeInterval>[];
    for (final s in appSessions) {
      final clamped = UsageCalculator.clampToDay(
        s.startTime,
        s.endTime,
        selection.startDate,
        selection.rangeEndExclusive,
      );
      if (clamped != null) {
        intervals.add(clamped);
      }
    }
    final merged = UsageCalculator.mergeIntervals(intervals);
    Duration totalUsage = Duration.zero;
    for (final i in merged) {
      totalUsage += i.duration;
    }

    // 3. Count sessions overlapping this period
    final sessionCount = intervals.length;

    // 4. Daily average
    final daysCount = max(1, selection.daysCount);
    final dailyAverage = Duration(microseconds: totalUsage.inMicroseconds ~/ daysCount);

    // 5. App limit information
    final limit = _findLimitForApp(appName, exePath);
    Duration? remainingAllowance;
    bool isLimitReached = false;

    if (limit != null && limitsService != null) {
      remainingAllowance = limitsService!.getRemainingAllowance(limit);
      isLimitReached = limit.isEnabled && limitsService!.isLimitExceeded(limit);
    }

    // 6. Sort sessions most recent first
    final sortedSessions = List<AppSession>.from(appSessions)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    return SingleAppAnalyticsResult(
      appName: appName,
      exePath: exePath,
      selection: selection,
      totalUsage: totalUsage,
      sessionCount: sessionCount,
      dailyAverage: dailyAverage,
      limit: limit,
      remainingAllowance: remainingAllowance,
      isLimitReached: isLimitReached,
      chartBars: chartBars,
      sessions: sortedSessions,
    );
  }

  /// Aggregates usage across 24 hourly buckets for a single calendar date.
  /// Handles ongoing/incomplete hour and boundary splitting correctly.
  static List<UsageBarData> aggregateHourlyUsage({
    required DateTime date,
    required List<AppSession> sessions,
    DateTime? now,
  }) {
    final currentNow = now ?? DateTime.now();
    final isDateToday = date.year == currentNow.year &&
        date.month == currentNow.month &&
        date.day == currentNow.day;
    final currentHour = isDateToday ? currentNow.hour : -1;

    final List<UsageBarData> bars = [];

    for (int h = 0; h < 24; h++) {
      final hourStart = DateTime(date.year, date.month, date.day, h);
      final hourEnd = DateTime(date.year, date.month, date.day, h + 1);

      final hourIntervals = <TimeInterval>[];
      for (final s in sessions) {
        final clamped = UsageCalculator.clampToDay(
          s.startTime,
          s.endTime,
          hourStart,
          hourEnd,
        );
        if (clamped != null) {
          hourIntervals.add(clamped);
        }
      }

      final merged = UsageCalculator.mergeIntervals(hourIntervals);
      Duration hourDuration = Duration.zero;
      for (final i in merged) {
        hourDuration += i.duration;
      }

      final isCurrent = isDateToday && h == currentHour;
      final label = _formatHourAxisLabel(h);
      final fullLabel = UsageCalculator.formatHourRange(h);

      bars.add(
        UsageBarData(
          index: h,
          label: label,
          fullLabel: fullLabel,
          duration: hourDuration,
          timestamp: hourStart,
          isCurrent: isCurrent,
        ),
      );
    }

    return bars;
  }

  /// Aggregates usage across each calendar day in a multi-day range.
  /// Correctly handles zero-usage days, live sessions, and month/year boundaries.
  static List<UsageBarData> aggregateDailyUsage({
    required DateRangeSelection selection,
    required List<AppSession> sessions,
    required DateTime today,
  }) {
    final List<UsageBarData> bars = [];
    final daysCount = selection.daysCount;

    for (int i = 0; i < daysCount; i++) {
      final dayStart = DateTime(
        selection.startDate.year,
        selection.startDate.month,
        selection.startDate.day + i,
      );
      final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);

      final dayIntervals = <TimeInterval>[];
      for (final s in sessions) {
        final clamped = UsageCalculator.clampToDay(
          s.startTime,
          s.endTime,
          dayStart,
          dayEnd,
        );
        if (clamped != null) {
          dayIntervals.add(clamped);
        }
      }

      final merged = UsageCalculator.mergeIntervals(dayIntervals);
      Duration dayDuration = Duration.zero;
      for (final interval in merged) {
        dayDuration += interval.duration;
      }

      final isCurrentDay = dayStart.year == today.year &&
          dayStart.month == today.month &&
          dayStart.day == today.day;

      final label = _formatDayAxisLabel(dayStart, selection);
      final fullLabel = DateFormat('EEEE, MMMM d, yyyy').format(dayStart);

      bars.add(
        UsageBarData(
          index: i,
          label: label,
          fullLabel: fullLabel,
          duration: dayDuration,
          timestamp: dayStart,
          isCurrent: isCurrentDay,
        ),
      );
    }

    return bars;
  }

  /// Aggregates sessions into a list of [AppItemAnalytics] grouped by application name.
  List<AppItemAnalytics> aggregateAppList({
    required DateRangeSelection selection,
    required List<AppSession> sessions,
  }) {
    final Map<String, List<TimeInterval>> appIntervals = {};
    final Map<String, String?> appExePaths = {};
    final Map<String, int> appSessionCounts = {};

    for (final s in sessions) {
      final name = s.appName.trim();
      if (name.isEmpty) continue;

      final clamped = UsageCalculator.clampToDay(
        s.startTime,
        s.endTime,
        selection.startDate,
        selection.rangeEndExclusive,
      );
      if (clamped == null) continue;

      appIntervals.putIfAbsent(name, () => []).add(clamped);
      appSessionCounts[name] = (appSessionCounts[name] ?? 0) + 1;
      if (s.exePath.trim().isNotEmpty && appExePaths[name] == null) {
        appExePaths[name] = s.exePath;
      }
    }

    // Merge intervals per app to calculate non-overlapping per-app duration
    final Map<String, Duration> appDurations = {};
    Duration totalOfApps = Duration.zero;

    for (final entry in appIntervals.entries) {
      final merged = UsageCalculator.mergeIntervals(entry.value);
      Duration sum = Duration.zero;
      for (final i in merged) {
        sum += i.duration;
      }
      appDurations[entry.key] = sum;
      totalOfApps += sum;
    }

    final totalSeconds = totalOfApps.inSeconds;
    final List<AppItemAnalytics> result = [];

    for (final entry in appDurations.entries) {
      final name = entry.key;
      final dur = entry.value;
      final count = appSessionCounts[name] ?? 0;
      final exe = appExePaths[name];
      final limit = _findLimitForApp(name, exe);

      result.add(
        AppItemAnalytics(
          appName: name,
          exePath: exe,
          totalDuration: dur,
          sessionCount: count,
          proportionalUsage: totalSeconds > 0
              ? min(1.0, dur.inSeconds / totalSeconds)
              : 0.0,
          limit: limit,
        ),
      );
    }

    // Default sort: Most used descending
    result.sort((a, b) {
      final cmp = b.totalDuration.compareTo(a.totalDuration);
      if (cmp != 0) return cmp;
      return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
    });

    return result;
  }

  AppLimit? _findLimitForApp(String appName, String? exePath) {
    if (limitsService == null) return null;
    final key = appName.trim().toLowerCase();
    for (final l in limitsService!.limits) {
      if (l.appName.trim().toLowerCase() == key) {
        return l;
      }
    }
    if (exePath != null && exePath.trim().isNotEmpty) {
      final fileName = exePath.split(r'\').last.toLowerCase();
      final base = fileName.endsWith('.exe')
          ? fileName.substring(0, fileName.length - 4)
          : fileName;
      for (final l in limitsService!.limits) {
        final lKey = l.appName.trim().toLowerCase();
        if (lKey == fileName || lKey == base) {
          return l;
        }
      }
    }
    return null;
  }

  void _mergeLiveSession(
    List<AppSession> sessions,
    DateRangeSelection selection,
    DateTime today,
  ) {
    if (tracker == null) return;
    final live = tracker!.liveSession;
    if (live == null) return;

    // Check if live session intersects the active date selection
    if (live.startTime.isBefore(selection.rangeEndExclusive) &&
        live.endTime.isAfter(selection.startDate)) {
      if (live.id != null) {
        final idx = sessions.indexWhere((s) => s.id == live.id);
        if (idx >= 0) {
          sessions[idx] = live;
        } else {
          sessions.add(live);
        }
      } else {
        if (live.endTime.isAfter(live.startTime)) {
          sessions.add(live);
        }
      }
    }
  }

  static String _formatHourAxisLabel(int hour) {
    // Show 12-hour format: 12 AM, 3 AM, 6 AM, 9 AM, 12 PM, 3 PM, 6 PM, 9 PM
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h $ampm';
  }

  static String _formatDayAxisLabel(DateTime date, DateRangeSelection selection) {
    if (selection.preset == DateFilterPreset.past7Days) {
      return DateFormat('E').format(date); // Mon, Tue, Wed
    } else if (selection.preset == DateFilterPreset.past30Days) {
      return DateFormat('d MMM').format(date); // 12 Oct
    } else {
      if (selection.daysCount <= 7) {
        return DateFormat('E d').format(date); // Mon 12
      } else {
        return DateFormat('d MMM').format(date);
      }
    }
  }
}
