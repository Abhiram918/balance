import 'dart:math';
import 'package:intl/intl.dart';
import '../models/analytics_data.dart';
import '../models/app_session.dart';
import '../models/focus_session.dart';
import '../models/usage_data.dart';
import 'usage_calculator.dart';
import 'usage_repository.dart';
import 'windows_usage_tracker.dart';

/// Dedicated, testable service that calculates real, data-driven analytics
/// and insights from local SQLite usage records.
class UsageAnalyticsService {
  final UsageRepository repository;
  final WindowsUsageTracker? tracker;

  static const String insightsPeriodSettingKey = 'insights_selected_period';

  Future<void>? _pendingSaveOp;

  /// Exposes any pending asynchronous save operation for deterministic testing.
  Future<void> get pendingSaveOp => _pendingSaveOp ?? Future.value();

  UsageAnalyticsService({
    required this.repository,
    this.tracker,
  });

  /// Retrieves the saved [AnalyticsPeriod] preference from the repository.
  ///
  /// Falls back to [AnalyticsPeriod.last7Days] if no preference is saved,
  /// if the database cannot be queried, or if the stored value is invalid.
  Future<AnalyticsPeriod> getSavedPeriod() async {
    try {
      final savedValue = await repository.getSetting(insightsPeriodSettingKey);
      final parsed = AnalyticsPeriod.fromString(savedValue);
      if (parsed != null) {
        return parsed;
      }
    } catch (_) {
      // Gracefully fall back on database error
    }
    return AnalyticsPeriod.last7Days;
  }

  /// Persists the user's selected [AnalyticsPeriod] to the repository.
  Future<void> savePeriod(AnalyticsPeriod period) {
    final op = () async {
      try {
        await repository.setSetting(insightsPeriodSettingKey, period.name);
      } catch (_) {
        // Gracefully ignore persistence errors
      }
    }();
    _pendingSaveOp = op;
    return op;
  }

  /// Computes complete analytics for the requested reporting period.
  ///
  /// An optional [referenceDate] can be supplied for deterministic testing.
  Future<PeriodAnalytics> getAnalytics({
    required AnalyticsPeriod period,
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = DateTime(now.year, now.month, now.day + 1);

    final int daysCount;
    switch (period) {
      case AnalyticsPeriod.today:
        daysCount = 1;
        break;
      case AnalyticsPeriod.last7Days:
        daysCount = 7;
        break;
      case AnalyticsPeriod.last30Days:
        daysCount = 30;
        break;
    }

    final periodStart = DateTime(todayStart.year, todayStart.month, todayStart.day - (daysCount - 1));
    final periodEnd = tomorrowStart;

    // Previous period for comparison
    final prevPeriodStart = DateTime(periodStart.year, periodStart.month, periodStart.day - daysCount);
    final prevPeriodEnd = periodStart;

    // 1. Fetch sessions for the current period
    final rawSessions = await repository.getSessionsForRange(periodStart, periodEnd);
    final sessions = List<AppSession>.from(rawSessions);

    // Merge in-progress live session if tracker is active and today is in range
    _mergeLiveSession(sessions, todayStart, tomorrowStart);

    // 2. Fetch sessions for the previous period to calculate real comparison
    final prevRawSessions = await repository.getSessionsForRange(prevPeriodStart, prevPeriodEnd);
    final prevSessions = List<AppSession>.from(prevRawSessions);

    // 3. Fetch focus sessions for the period (excluding breaks)
    Duration totalFocusTime = Duration.zero;
    try {
      final focusRecords = await repository.getFocusSessionsForRange(periodStart, periodEnd);
      for (final rec in focusRecords) {
        if (rec.type == FocusSessionType.focus) {
          totalFocusTime += rec.actualDuration;
        }
      }
    } catch (_) {}

    // 4. Calculate daily usage points across each day in the window
    final List<DailyUsagePoint> dailySeries = [];
    final Map<String, List<TimeInterval>> appIntervals = {};
    Duration totalScreenTime = Duration.zero;
    DailyUsagePoint? mostActiveDay;
    int activeDaysCount = 0;

    for (int i = 0; i < daysCount; i++) {
      final dayStart = DateTime(periodStart.year, periodStart.month, periodStart.day + i);
      final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
      final isToday = dayStart.year == todayStart.year &&
          dayStart.month == todayStart.month &&
          dayStart.day == todayStart.day;
      final isWeekend = dayStart.weekday == DateTime.saturday || dayStart.weekday == DateTime.sunday;

      // Filter sessions overlapping this day
      final daySessions = sessions
          .where((s) => s.startTime.isBefore(dayEnd) && s.endTime.isAfter(dayStart))
          .toList();

      final daySummary = UsageCalculator.calculateDailySummary(
        date: dayStart,
        sessions: daySessions,
      );

      final dayDuration = daySummary.totalActiveTime;
      totalScreenTime += dayDuration;

      if (dayDuration > Duration.zero) {
        activeDaysCount++;
        if (mostActiveDay == null || dayDuration > mostActiveDay.duration) {
          mostActiveDay = DailyUsagePoint(
            date: dayStart,
            duration: dayDuration,
            label: _formatDayLabel(dayStart, period, isToday),
            isToday: isToday,
            isWeekend: isWeekend,
          );
        }
      }

      dailySeries.add(
        DailyUsagePoint(
          date: dayStart,
          duration: dayDuration,
          label: _formatDayLabel(dayStart, period, isToday),
          isToday: isToday,
          isWeekend: isWeekend,
        ),
      );
    }

    // 5. Calculate daily average over all calendar days (including 0-usage days)
    final dailyAverage = daysCount > 0
        ? Duration(microseconds: totalScreenTime.inMicroseconds ~/ daysCount)
        : Duration.zero;

    // 6. Calculate Top Applications across the period
    final List<TimeInterval> allClampedIntervals = [];
    for (final session in sessions) {
      final clamped = UsageCalculator.clampToDay(
        session.startTime,
        session.endTime,
        periodStart,
        periodEnd,
      );
      if (clamped == null) continue;

      appIntervals.putIfAbsent(session.appName, () => []).add(clamped);
      allClampedIntervals.add(clamped);
    }

    final Map<String, Duration> appTotals = {};
    for (final entry in appIntervals.entries) {
      final merged = UsageCalculator.mergeIntervals(entry.value);
      Duration appSum = Duration.zero;
      for (final interval in merged) {
        appSum += interval.duration;
      }
      if (appSum > Duration.zero) {
        appTotals[entry.key] = appSum;
      }
    }

    final sortedApps = appTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalPeriodSeconds = totalScreenTime.inSeconds;
    final List<AppUsageData> topApplications = [];

    for (final entry in sortedApps) {
      topApplications.add(
        AppUsageData(
          appName: entry.key,
          duration: entry.value,
          proportionalUsage: totalPeriodSeconds > 0
              ? min(1.0, entry.value.inSeconds / totalPeriodSeconds)
              : 0.0,
        ),
      );
    }

    final AppUsageData? mostUsedApp = topApplications.isNotEmpty ? topApplications.first : null;

    // 7. Calculate previous period total & comparison
    Duration prevPeriodScreenTime = Duration.zero;
    final List<TimeInterval> prevIntervals = [];
    for (final session in prevSessions) {
      final clamped = UsageCalculator.clampToDay(
        session.startTime,
        session.endTime,
        prevPeriodStart,
        prevPeriodEnd,
      );
      if (clamped != null) {
        prevIntervals.add(clamped);
      }
    }
    final mergedPrev = UsageCalculator.mergeIntervals(prevIntervals);
    for (final interval in mergedPrev) {
      prevPeriodScreenTime += interval.duration;
    }

    final differenceVsPrevious = totalScreenTime - prevPeriodScreenTime;
    double? percentageChange;
    if (prevPeriodScreenTime > Duration.zero) {
      percentageChange = ((totalScreenTime.inSeconds - prevPeriodScreenTime.inSeconds) /
              prevPeriodScreenTime.inSeconds) *
          100.0;
    } else if (totalScreenTime == Duration.zero) {
      percentageChange = 0.0;
    } else {
      percentageChange = null; // No previous baseline
    }

    return PeriodAnalytics(
      period: period,
      startDate: periodStart,
      endDate: periodEnd,
      totalScreenTime: totalScreenTime,
      dailyAverage: dailyAverage,
      dailySeries: dailySeries,
      topApplications: topApplications,
      mostUsedApp: mostUsedApp,
      mostActiveDay: mostActiveDay,
      activeDaysCount: activeDaysCount,
      totalDaysCount: daysCount,
      previousPeriodScreenTime: prevPeriodScreenTime,
      percentageChangeVsPrevious: percentageChange,
      differenceVsPrevious: differenceVsPrevious,
      totalFocusTime: totalFocusTime,
    );
  }

  void _mergeLiveSession(
    List<AppSession> sessions,
    DateTime todayStart,
    DateTime tomorrowStart,
  ) {
    if (tracker == null) return;
    final live = tracker!.liveSession;
    if (live == null) return;

    if (live.startTime.isBefore(tomorrowStart) && live.endTime.isAfter(todayStart)) {
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

  String _formatDayLabel(DateTime date, AnalyticsPeriod period, bool isToday) {
    if (period == AnalyticsPeriod.last7Days) {
      return DateFormat('E').format(date); // Mon, Tue, Wed, etc.
    } else if (period == AnalyticsPeriod.last30Days) {
      return DateFormat('d MMM').format(date); // 12 Oct
    } else {
      return isToday ? 'Today' : DateFormat('d MMM').format(date);
    }
  }
}
