import 'dart:math';
import '../models/app_session.dart';
import '../models/usage_data.dart';

/// A time interval with start and end timestamps.
class TimeInterval {
  final DateTime start;
  final DateTime end;

  TimeInterval(this.start, this.end);

  Duration get duration => end.difference(start);
}

/// Pure helper for calculating daily screen time usage, application breakdowns,
/// and hourly timelines mathematically consistently without double-counting.
class UsageCalculator {
  /// Clamps an interval to the boundaries of [startOfDay, endOfDay).
  static TimeInterval? clampToDay(
    DateTime start,
    DateTime end,
    DateTime startOfDay,
    DateTime endOfDay,
  ) {
    if (!end.isAfter(start)) return null;
    final clampedStart = start.isBefore(startOfDay) ? startOfDay : start;
    final clampedEnd = end.isAfter(endOfDay) ? endOfDay : end;
    if (!clampedEnd.isAfter(clampedStart)) return null;
    return TimeInterval(clampedStart, clampedEnd);
  }

  /// Merges overlapping or contiguous time intervals into a sorted,
  /// disjoint list of intervals.
  static List<TimeInterval> mergeIntervals(List<TimeInterval> intervals) {
    if (intervals.isEmpty) return [];
    final sorted = List<TimeInterval>.from(intervals)
      ..sort((a, b) => a.start.compareTo(b.start));

    final merged = <TimeInterval>[sorted.first];
    for (int i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      final last = merged.last;

      if (current.start.isBefore(last.end) || current.start == last.end) {
        if (current.end.isAfter(last.end)) {
          merged[merged.length - 1] = TimeInterval(last.start, current.end);
        }
      } else {
        merged.add(current);
      }
    }
    return merged;
  }

  /// Calculates the 24 hourly activity buckets (each value in 0.0 - 1.0)
  /// by partitioning each interval across hour boundaries [00:00, 01:00, ..., 23:00].
  ///
  /// This ensures that multi-hour sessions are distributed across the exact hours
  /// they occurred rather than dumped into the starting hour.
  static List<double> calculateHourlyActivity(
    DateTime startOfDay,
    List<TimeInterval> mergedIntervals,
  ) {
    final hourlyActivity = List<double>.filled(24, 0.0);
    const microsPerHour = 3600000000; // Duration.microsecondsPerHour

    for (int h = 0; h < 24; h++) {
      final hourStart = startOfDay.add(Duration(hours: h));
      final hourEnd = hourStart.add(const Duration(hours: 1));
      int activeMicrosInHour = 0;

      for (final interval in mergedIntervals) {
        if (interval.end.isBefore(hourStart) || interval.start.isAfter(hourEnd)) {
          continue;
        }
        final overlapStart = interval.start.isAfter(hourStart) ? interval.start : hourStart;
        final overlapEnd = interval.end.isBefore(hourEnd) ? interval.end : hourEnd;
        if (overlapEnd.isAfter(overlapStart)) {
          activeMicrosInHour += overlapEnd.difference(overlapStart).inMicroseconds;
        }
      }

      hourlyActivity[h] = (activeMicrosInHour / microsPerHour).clamp(0.0, 1.0);
    }

    return hourlyActivity;
  }

  /// Computes a complete [DailyUsageSummary] from a collection of raw [AppSession]s.
  ///
  /// - Clamps sessions crossing midnight to the requested [date].
  /// - Merges overlapping intervals per app and globally to prevent double-counting.
  /// - Accurately distributes usage across all 24 hourly buckets.
  /// - Maintains mathematical consistency: total active time matches the sum
  ///   of disjoint active periods.
  static DailyUsageSummary calculateDailySummary({
    required DateTime date,
    required List<AppSession> sessions,
    Duration goalTime = const Duration(hours: 8),
    Duration focusTime = Duration.zero,
    int breaksTaken = 0,
  }) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final Map<String, List<TimeInterval>> appIntervals = {};
    final List<TimeInterval> allIntervals = [];

    for (final session in sessions) {
      final clamped = clampToDay(
        session.startTime,
        session.endTime,
        startOfDay,
        endOfDay,
      );
      if (clamped == null) continue;

      appIntervals.putIfAbsent(session.appName, () => []).add(clamped);
      allIntervals.add(clamped);
    }

    // Merge global intervals to calculate true non-overlapping active time
    final mergedGlobalIntervals = mergeIntervals(allIntervals);
    Duration totalActiveTime = Duration.zero;
    for (final interval in mergedGlobalIntervals) {
      totalActiveTime += interval.duration;
    }

    // Merge per-app intervals to prevent double-counting per app
    final Map<String, Duration> appDurations = {};
    for (final entry in appIntervals.entries) {
      final mergedAppIntervals = mergeIntervals(entry.value);
      Duration appTotal = Duration.zero;
      for (final interval in mergedAppIntervals) {
        appTotal += interval.duration;
      }
      appDurations[entry.key] = appTotal;
    }

    // Sort apps by descending duration
    final sortedApps = appDurations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final List<AppUsageData> allApps = [];
    final totalSeconds = totalActiveTime.inSeconds;

    for (final entry in sortedApps) {
      allApps.add(
        AppUsageData(
          appName: entry.key,
          duration: entry.value,
          proportionalUsage: totalSeconds > 0
              ? min(1.0, entry.value.inSeconds / totalSeconds)
              : 0.0,
        ),
      );
    }

    final mostUsedApps = allApps.take(5).toList();
    final hourlyActivity = calculateHourlyActivity(startOfDay, mergedGlobalIntervals);

    return DailyUsageSummary(
      date: date,
      totalActiveTime: totalActiveTime,
      goalTime: goalTime,
      focusTime: focusTime,
      breaksTaken: breaksTaken,
      hourlyActivity: hourlyActivity,
      mostUsedApps: mostUsedApps,
      allApps: allApps,
    );
  }
}
