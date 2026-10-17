import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'app_limit.dart';
import 'app_session.dart';

/// Predefined presets for application analytics date filtering.
enum DateFilterPreset {
  today,
  past7Days,
  past30Days,
  customDate,
  customRange;

  String get label {
    switch (this) {
      case DateFilterPreset.today:
        return 'Today';
      case DateFilterPreset.past7Days:
        return 'Past 7 Days';
      case DateFilterPreset.past30Days:
        return 'Past 30 Days';
      case DateFilterPreset.customDate:
        return 'Custom Date';
      case DateFilterPreset.customRange:
        return 'Custom Date Range';
    }
  }
}

/// Represents the active date selection for analytics, normalized to local midnight boundaries.
@immutable
class DateRangeSelection {
  final DateFilterPreset preset;
  final DateTime startDate; // Start of day (00:00:00.000)
  final DateTime endDate;   // Start of day for the end date (00:00:00.000)

  DateRangeSelection({
    required this.preset,
    required DateTime startDate,
    required DateTime endDate,
  })  : startDate = DateTime(startDate.year, startDate.month, startDate.day),
        endDate = DateTime(endDate.year, endDate.month, endDate.day) {
    assert(!this.endDate.isBefore(this.startDate), 'End date cannot precede start date');
  }

  /// Factory for Today preset.
  factory DateRangeSelection.today([DateTime? referenceDate]) {
    final ref = referenceDate ?? DateTime.now();
    final d = DateTime(ref.year, ref.month, ref.day);
    return DateRangeSelection(
      preset: DateFilterPreset.today,
      startDate: d,
      endDate: d,
    );
  }

  /// Factory for Past 7 Days (Today and preceding 6 calendar days = 7 days total).
  factory DateRangeSelection.past7Days([DateTime? referenceDate]) {
    final ref = referenceDate ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final start = DateTime(today.year, today.month, today.day - 6);
    return DateRangeSelection(
      preset: DateFilterPreset.past7Days,
      startDate: start,
      endDate: today,
    );
  }

  /// Factory for Past 30 Days (Today and preceding 29 calendar days = 30 days total).
  factory DateRangeSelection.past30Days([DateTime? referenceDate]) {
    final ref = referenceDate ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final start = DateTime(today.year, today.month, today.day - 29);
    return DateRangeSelection(
      preset: DateFilterPreset.past30Days,
      startDate: start,
      endDate: today,
    );
  }

  /// Factory for a Custom single date.
  factory DateRangeSelection.customDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return DateRangeSelection(
      preset: DateFilterPreset.customDate,
      startDate: d,
      endDate: d,
    );
  }

  /// Factory for a Custom date range.
  factory DateRangeSelection.customRange(DateTime start, DateTime end) {
    var s = DateTime(start.year, start.month, start.day);
    var e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) {
      final tmp = s;
      s = e;
      e = tmp;
    }
    return DateRangeSelection(
      preset: DateFilterPreset.customRange,
      startDate: s,
      endDate: e,
    );
  }

  /// The exclusive end timestamp of the range (start of the day following endDate).
  DateTime get rangeEndExclusive => DateTime(endDate.year, endDate.month, endDate.day + 1);

  /// Whether the selection represents a single calendar day.
  bool get isSingleDay =>
      startDate.year == endDate.year &&
      startDate.month == endDate.month &&
      startDate.day == endDate.day;

  /// Whether the bar chart for this selection should display hourly bars (24 hours).
  bool get isHourly => preset == DateFilterPreset.today || preset == DateFilterPreset.customDate;

  /// Total number of calendar days in this range (inclusive).
  int get daysCount {
    return endDate.difference(startDate).inDays + 1;
  }

  /// Formatted user-facing display label for the date selector button.
  String get formattedDisplayLabel {
    final fmt = DateFormat('MMM d, yyyy');
    switch (preset) {
      case DateFilterPreset.today:
        return 'Today, ${fmt.format(startDate)}';
      case DateFilterPreset.past7Days:
        return 'Past 7 Days (${DateFormat('MMM d').format(startDate)} – ${DateFormat('MMM d').format(endDate)})';
      case DateFilterPreset.past30Days:
        return 'Past 30 Days (${DateFormat('MMM d').format(startDate)} – ${DateFormat('MMM d').format(endDate)})';
      case DateFilterPreset.customDate:
        return fmt.format(startDate);
      case DateFilterPreset.customRange:
        if (isSingleDay) {
          return fmt.format(startDate);
        }
        return '${DateFormat('MMM d, yyyy').format(startDate)} – ${DateFormat('MMM d, yyyy').format(endDate)}';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateRangeSelection &&
          runtimeType == other.runtimeType &&
          preset == other.preset &&
          startDate == other.startDate &&
          endDate == other.endDate;

  @override
  int get hashCode => preset.hashCode ^ startDate.hashCode ^ endDate.hashCode;
}

/// A single bar data point for the aggregate or per-app usage chart.
@immutable
class UsageBarData {
  final int index;
  final String label;
  final String fullLabel;
  final Duration duration;
  final DateTime timestamp;
  final bool isCurrent;

  const UsageBarData({
    required this.index,
    required this.label,
    required this.fullLabel,
    required this.duration,
    required this.timestamp,
    required this.isCurrent,
  });

  double get inHours => duration.inMinutes / 60.0;
  double get inMinutesDouble => duration.inSeconds / 60.0;

  @override
  String toString() => 'UsageBarData($label, ${duration.inMinutes}m)';
}

/// Analytics summary for an individual application row in the Applications list.
@immutable
class AppItemAnalytics {
  final String appName;
  final String? exePath;
  final Duration totalDuration;
  final int sessionCount;
  final double proportionalUsage; // 0.0 to 1.0 relative to total screen time in period
  final AppLimit? limit;

  const AppItemAnalytics({
    required this.appName,
    this.exePath,
    required this.totalDuration,
    required this.sessionCount,
    required this.proportionalUsage,
    this.limit,
  });

  bool get hasLimit => limit != null;
  bool get isLimitEnabled => limit?.isEnabled == true;

  AppItemAnalytics copyWith({
    String? appName,
    String? exePath,
    Duration? totalDuration,
    int? sessionCount,
    double? proportionalUsage,
    AppLimit? limit,
  }) {
    return AppItemAnalytics(
      appName: appName ?? this.appName,
      exePath: exePath ?? this.exePath,
      totalDuration: totalDuration ?? this.totalDuration,
      sessionCount: sessionCount ?? this.sessionCount,
      proportionalUsage: proportionalUsage ?? this.proportionalUsage,
      limit: limit ?? this.limit,
    );
  }
}

/// Aggregated analytics result for the main Applications page.
@immutable
class ApplicationsAnalyticsResult {
  final DateRangeSelection selection;
  final Duration totalUsage;
  final int totalLimitedApps;
  final int totalLimitReachedApps;
  final List<UsageBarData> chartBars;
  final List<AppItemAnalytics> applications;

  const ApplicationsAnalyticsResult({
    required this.selection,
    required this.totalUsage,
    required this.totalLimitedApps,
    required this.totalLimitReachedApps,
    required this.chartBars,
    required this.applications,
  });

  factory ApplicationsAnalyticsResult.empty(DateRangeSelection selection) {
    return ApplicationsAnalyticsResult(
      selection: selection,
      totalUsage: Duration.zero,
      totalLimitedApps: 0,
      totalLimitReachedApps: 0,
      chartBars: const [],
      applications: const [],
    );
  }
}

/// Aggregated analytics result for the individual Application Details page.
@immutable
class SingleAppAnalyticsResult {
  final String appName;
  final String? exePath;
  final DateRangeSelection selection;
  final Duration totalUsage;
  final int sessionCount;
  final Duration dailyAverage;
  final AppLimit? limit;
  final Duration? remainingAllowance;
  final bool isLimitReached;
  final List<UsageBarData> chartBars;
  final List<AppSession> sessions; // Sorted most recent first

  const SingleAppAnalyticsResult({
    required this.appName,
    this.exePath,
    required this.selection,
    required this.totalUsage,
    required this.sessionCount,
    required this.dailyAverage,
    this.limit,
    this.remainingAllowance,
    required this.isLimitReached,
    required this.chartBars,
    required this.sessions,
  });

  factory SingleAppAnalyticsResult.empty({
    required String appName,
    String? exePath,
    required DateRangeSelection selection,
    AppLimit? limit,
    Duration? remainingAllowance,
    bool isLimitReached = false,
  }) {
    return SingleAppAnalyticsResult(
      appName: appName,
      exePath: exePath,
      selection: selection,
      totalUsage: Duration.zero,
      sessionCount: 0,
      dailyAverage: Duration.zero,
      limit: limit,
      remainingAllowance: remainingAllowance,
      isLimitReached: isLimitReached,
      chartBars: const [],
      sessions: const [],
    );
  }
}
