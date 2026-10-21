import 'package:flutter/foundation.dart';
import 'usage_data.dart';

/// Predefined reporting periods for insights and analytics.
enum AnalyticsPeriod {
  today,
  last7Days,
  last30Days;

  String get label {
    switch (this) {
      case AnalyticsPeriod.today:
        return 'Today';
      case AnalyticsPeriod.last7Days:
        return 'Last 7 Days';
      case AnalyticsPeriod.last30Days:
        return 'Last 30 Days';
    }
  }

  /// Parses an [AnalyticsPeriod] from a raw string value.
  /// Matches enum names (case-insensitive) or common aliases.
  /// Returns null if [value] is null, empty, or unrecognized.
  static AnalyticsPeriod? fromString(String? value) {
    if (value == null) return null;
    final clean = value.trim().toLowerCase();
    for (final period in AnalyticsPeriod.values) {
      if (period.name.toLowerCase() == clean) {
        return period;
      }
    }
    if (clean == 'today' || clean == '1day' || clean == 'day') {
      return AnalyticsPeriod.today;
    }
    if (clean == 'last7days' || clean == 'past7days' || clean == '7days' || clean == 'week') {
      return AnalyticsPeriod.last7Days;
    }
    if (clean == 'last30days' || clean == 'past30days' || clean == '30days' || clean == 'month') {
      return AnalyticsPeriod.last30Days;
    }
    return null;
  }
}

/// A single data point representing usage for one local calendar day.
@immutable
class DailyUsagePoint {
  final DateTime date;
  final Duration duration;
  final String label; // e.g. "Mon", "Tue", "14 Oct"
  final bool isToday;
  final bool isWeekend;

  const DailyUsagePoint({
    required this.date,
    required this.duration,
    required this.label,
    required this.isToday,
    required this.isWeekend,
  });

  double get inHours => duration.inMinutes / 60.0;
  bool get hasUsage => duration > Duration.zero;

  @override
  String toString() => 'DailyUsagePoint($label, ${duration.inMinutes}m, isToday: $isToday)';
}

/// Result of analytics calculation for a requested reporting period.
@immutable
class PeriodAnalytics {
  final AnalyticsPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final Duration totalScreenTime;
  final Duration dailyAverage;
  final List<DailyUsagePoint> dailySeries;
  final List<AppUsageData> topApplications;
  final AppUsageData? mostUsedApp;
  final DailyUsagePoint? mostActiveDay;
  final int activeDaysCount;
  final int totalDaysCount;
  final Duration previousPeriodScreenTime;
  final double? percentageChangeVsPrevious;
  final Duration differenceVsPrevious;
  final Duration totalFocusTime;

  const PeriodAnalytics({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.totalScreenTime,
    required this.dailyAverage,
    required this.dailySeries,
    required this.topApplications,
    this.mostUsedApp,
    this.mostActiveDay,
    required this.activeDaysCount,
    required this.totalDaysCount,
    required this.previousPeriodScreenTime,
    this.percentageChangeVsPrevious,
    required this.differenceVsPrevious,
    required this.totalFocusTime,
  });

  bool get hasUsage => totalScreenTime > Duration.zero;

  /// Creates an empty analytics model for when no records exist.
  factory PeriodAnalytics.empty({
    required AnalyticsPeriod period,
    required DateTime startDate,
    required DateTime endDate,
    List<DailyUsagePoint> series = const [],
  }) {
    return PeriodAnalytics(
      period: period,
      startDate: startDate,
      endDate: endDate,
      totalScreenTime: Duration.zero,
      dailyAverage: Duration.zero,
      dailySeries: series,
      topApplications: const [],
      mostUsedApp: null,
      mostActiveDay: null,
      activeDaysCount: 0,
      totalDaysCount: series.isNotEmpty ? series.length : 1,
      previousPeriodScreenTime: Duration.zero,
      percentageChangeVsPrevious: null,
      differenceVsPrevious: Duration.zero,
      totalFocusTime: Duration.zero,
    );
  }
}
