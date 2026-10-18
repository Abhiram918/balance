import 'dart:math';
import '../models/app_session.dart';
import '../models/focus_session.dart';
import '../models/usage_data.dart';

/// A time interval with start and end timestamps.
class TimeInterval {
  final DateTime start;
  final DateTime end;

  TimeInterval(this.start, this.end);

  Duration get duration => end.difference(start);
}

/// Metrics derived from focus and break sessions for a specific day.
class FocusDayMetrics {
  final Duration focusTime;
  final int breaksTaken;
  final Duration breakDuration;
  final List<TimeInterval> focusIntervals;
  final List<TimeInterval> breakIntervals;

  const FocusDayMetrics({
    required this.focusTime,
    required this.breaksTaken,
    required this.breakDuration,
    required this.focusIntervals,
    required this.breakIntervals,
  });
}

/// Pure helper for calculating daily screen time usage, application breakdowns,
/// focus/break metrics, and hourly timelines mathematically consistently without double-counting.
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

  /// Subtracts [toSubtract] intervals from [source] intervals.
  /// Returns a disjoint list of remaining intervals.
  static List<TimeInterval> subtractIntervals(
    List<TimeInterval> source,
    List<TimeInterval> toSubtract,
  ) {
    if (source.isEmpty) return [];
    if (toSubtract.isEmpty) return mergeIntervals(source);

    final mergedSub = mergeIntervals(toSubtract);
    List<TimeInterval> current = mergeIntervals(source);

    for (final sub in mergedSub) {
      final next = <TimeInterval>[];
      for (final src in current) {
        // No overlap
        if (src.end.isBefore(sub.start) ||
            src.start.isAfter(sub.end) ||
            src.end == sub.start ||
            src.start == sub.end) {
          next.add(src);
          continue;
        }

        // Sub completely covers src
        if ((sub.start.isBefore(src.start) || sub.start == src.start) &&
            (sub.end.isAfter(src.end) || sub.end == src.end)) {
          continue;
        }

        // Sub is strictly inside src: splits src into two pieces
        if (sub.start.isAfter(src.start) && sub.end.isBefore(src.end)) {
          next.add(TimeInterval(src.start, sub.start));
          next.add(TimeInterval(sub.end, src.end));
          continue;
        }

        // Sub overlaps left edge of src
        if (sub.start.isBefore(src.start) || sub.start == src.start) {
          if (sub.end.isBefore(src.end)) {
            next.add(TimeInterval(sub.end, src.end));
          }
          continue;
        }

        // Sub overlaps right edge of src
        if (sub.end.isAfter(src.end) || sub.end == src.end) {
          if (sub.start.isAfter(src.start)) {
            next.add(TimeInterval(src.start, sub.start));
          }
          continue;
        }
      }
      current = next;
    }

    return current;
  }

  /// Calculates total focus duration, break duration, break count, and intervals
  /// for a given [date] from persisted [focusSessions] and an optional [activeState].
  static FocusDayMetrics calculateFocusMetrics({
    required DateTime date,
    required List<FocusSessionRecord> focusSessions,
    ActiveFocusState? activeState,
    DateTime? now,
  }) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final List<TimeInterval> focusIntervals = [];
    final List<TimeInterval> breakIntervals = [];
    int breaksCount = 0;

    for (final session in focusSessions) {
      final clamped = clampToDay(
        session.startTime,
        session.endTime,
        startOfDay,
        endOfDay,
      );
      if (clamped == null) continue;

      // Ensure actual recorded duration is respected
      final effectiveDuration = session.actualDuration < clamped.duration
          ? session.actualDuration
          : clamped.duration;
      if (effectiveDuration <= Duration.zero) continue;

      final interval = TimeInterval(
        clamped.start,
        clamped.start.add(effectiveDuration),
      );

      if (session.type == FocusSessionType.focus) {
        focusIntervals.add(interval);
      } else if (session.type == FocusSessionType.breakSession) {
        breakIntervals.add(interval);
        breaksCount++;
      }
    }

    // Include currently running or paused active session if applicable
    if (activeState != null &&
        (activeState.status == FocusStatus.running ||
            activeState.status == FocusStatus.paused)) {
      final currentTime = now ?? DateTime.now();
      Duration elapsed = Duration.zero;

      if (activeState.status == FocusStatus.paused) {
        elapsed = activeState.targetDuration - activeState.remainingDuration;
      } else {
        // When running, remaining duration is the time remaining until expectedEndTime
        final remaining = activeState.expectedEndTime.difference(currentTime);
        final effectiveRemaining = remaining.isNegative ? Duration.zero : remaining;
        elapsed = activeState.targetDuration - effectiveRemaining;
      }

      if (elapsed > activeState.targetDuration) {
        elapsed = activeState.targetDuration;
      } else if (elapsed.isNegative) {
        elapsed = Duration.zero;
      }

      if (elapsed > Duration.zero) {
        final activeInterval = clampToDay(
          activeState.startTime,
          activeState.startTime.add(elapsed),
          startOfDay,
          endOfDay,
        );
        if (activeInterval != null) {
          if (activeState.type == FocusSessionType.focus) {
            focusIntervals.add(activeInterval);
          } else if (activeState.type == FocusSessionType.breakSession) {
            breakIntervals.add(activeInterval);
            breaksCount++;
          }
        }
      }
    }

    final mergedFocus = mergeIntervals(focusIntervals);
    Duration totalFocus = Duration.zero;
    for (final i in mergedFocus) {
      totalFocus += i.duration;
    }

    final mergedBreaks = mergeIntervals(breakIntervals);
    Duration totalBreaks = Duration.zero;
    for (final i in mergedBreaks) {
      totalBreaks += i.duration;
    }

    return FocusDayMetrics(
      focusTime: totalFocus,
      breaksTaken: breaksCount,
      breakDuration: totalBreaks,
      focusIntervals: mergedFocus,
      breakIntervals: mergedBreaks,
    );
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

  /// Computes a complete [DailyUsageSummary] from raw [AppSession]s and optional focus metrics.
  ///
  /// - Clamps sessions crossing midnight to the requested [date].
  /// - Merges overlapping intervals per app and globally to prevent double-counting.
  /// - Accurately distributes usage across all 24 hourly buckets.
  /// - Reconciles Focus, Breaks, and Other Usage without double-counting.
  /// - Excludes Balance itself from top application rankings.
  static DailyUsageSummary calculateDailySummary({
    required DateTime date,
    required List<AppSession> sessions,
    Duration goalTime = const Duration(hours: 8),
    Duration focusTime = Duration.zero,
    int breaksTaken = 0,
    Duration breakDuration = Duration.zero,
    List<TimeInterval>? focusIntervals,
    List<TimeInterval>? breakIntervals,
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
    final List<AppUsageData> userApps = [];
    final totalSeconds = totalActiveTime.inSeconds;

    for (final entry in sortedApps) {
      final appUsage = AppUsageData(
        appName: entry.key,
        duration: entry.value,
        proportionalUsage: totalSeconds > 0
            ? min(1.0, entry.value.inSeconds / totalSeconds)
            : 0.0,
      );
      allApps.add(appUsage);

      // Exclude Balance itself from user app ranking
      if (entry.key.trim().toLowerCase() != 'balance') {
        userApps.add(appUsage);
      }
    }

    // Top applications for today (excluding Balance)
    final mostUsedApps = userApps.take(5).toList();
    final hourlyActivity = calculateHourlyActivity(startOfDay, mergedGlobalIntervals);

    // Calculate reconciled time breakdown for donut chart:
    // Other Usage = recorded computer usage outside of Focus and Break intervals
    final focusList = focusIntervals ?? [];
    final breakList = breakIntervals ?? [];
    final nonOtherIntervals = [...focusList, ...breakList];
    final otherIntervals = subtractIntervals(mergedGlobalIntervals, nonOtherIntervals);

    Duration otherUsageDuration = Duration.zero;
    for (final i in otherIntervals) {
      otherUsageDuration += i.duration;
    }

    // The total reconciled time is focus + breaks + other usage
    final totalBreakdownUsage = focusTime + breakDuration + otherUsageDuration;

    final breakdown = DailyTimeBreakdown(
      totalUsage: totalBreakdownUsage,
      focusDuration: focusTime,
      breakDuration: breakDuration,
      otherUsageDuration: otherUsageDuration,
    );

    // Calculate daily activity statistics (most active hour, unique apps, longest session)
    final dailyActivity = calculateDailyActivityMetrics(
      date: date,
      sessions: sessions,
      hourlyActivity: hourlyActivity,
    );

    return DailyUsageSummary(
      date: date,
      totalActiveTime: totalActiveTime,
      goalTime: goalTime,
      focusTime: focusTime,
      breaksTaken: breaksTaken,
      breakDuration: breakDuration,
      timeBreakdown: breakdown,
      dailyActivity: dailyActivity,
      hourlyActivity: hourlyActivity,
      mostUsedApps: mostUsedApps,
      allApps: allApps,
    );
  }

  /// Formats an hour index 0..23 into a 12-hour span, e.g. "12:00 – 1:00 PM".
  static String formatHourRange(int hour) {
    final startHour = hour % 12 == 0 ? 12 : hour % 12;
    final startAmPm = hour < 12 ? 'AM' : 'PM';
    final nextHourRaw = (hour + 1) % 24;
    final nextHour = nextHourRaw % 12 == 0 ? 12 : nextHourRaw % 12;
    final nextAmPm = nextHourRaw < 12 ? 'AM' : 'PM';
    if (startAmPm == nextAmPm) {
      return '$startHour:00 – $nextHour:00 $nextAmPm';
    } else {
      return '$startHour:00 $startAmPm – $nextHour:00 $nextAmPm';
    }
  }

  /// Calculates Daily Activity metrics: most active hour, unique applications count,
  /// and longest continuous session duration & app name.
  static DailyActivityMetrics calculateDailyActivityMetrics({
    required DateTime date,
    required List<AppSession> sessions,
    List<double>? hourlyActivity,
  }) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final effectiveHourly = hourlyActivity ?? () {
      final intervals = <TimeInterval>[];
      for (final s in sessions) {
        if (s.appName.trim().toLowerCase() == 'balance') continue;
        final sStart = s.startTime.isBefore(startOfDay) ? startOfDay : s.startTime;
        final sEnd = s.endTime.isAfter(endOfDay) ? endOfDay : s.endTime;
        if (sEnd.isAfter(sStart)) {
          intervals.add(TimeInterval(sStart, sEnd));
        }
      }
      return calculateHourlyActivity(startOfDay, mergeIntervals(intervals));
    }();

    // 1. Most active hour
    int maxHour = -1;
    double maxActivity = 0.0;
    for (int h = 0; h < effectiveHourly.length; h++) {
      if (effectiveHourly[h] > maxActivity) {
        maxActivity = effectiveHourly[h];
        maxHour = h;
      }
    }
    final mostActiveHourText = maxHour >= 0 && maxActivity > 0.0
        ? formatHourRange(maxHour)
        : '12:00 – 1:00 PM';

    // 2. Distinct applications used today (excluding Balance) & Longest continuous session
    final Set<String> uniqueApps = {};
    AppSession? longestSession;
    Duration longestDuration = Duration.zero;

    for (final s in sessions) {
      if (s.appName.trim().toLowerCase() == 'balance') continue;
      final clamped = clampToDay(s.startTime, s.endTime, startOfDay, endOfDay);
      if (clamped == null || clamped.duration <= Duration.zero) continue;

      uniqueApps.add(s.appName);

      if (clamped.duration > longestDuration) {
        longestDuration = clamped.duration;
        longestSession = s;
      }
    }

    return DailyActivityMetrics(
      mostActiveHourText: mostActiveHourText,
      distinctAppsCount: uniqueApps.length,
      longestSessionDuration: longestDuration,
      longestSessionAppName: longestSession?.appName ?? 'None',
    );
  }
}
