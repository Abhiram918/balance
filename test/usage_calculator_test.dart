import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/services/usage_calculator.dart';

void main() {
  group('UsageCalculator Tests', () {
    final testDate = DateTime(2026, 10, 11);

    test('Clamps sessions starting before midnight to start of day', () {
      final session = AppSession(
        appName: 'NightOwl',
        exePath: r'C:\nightowl.exe',
        startTime: DateTime(2026, 10, 10, 23, 40), // 20m yesterday
        endTime: DateTime(2026, 10, 11, 0, 30),    // 30m today
      );

      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: [session],
      );

      expect(summary.totalActiveTime, equals(const Duration(minutes: 30)));
      expect(summary.allApps.first.duration, equals(const Duration(minutes: 30)));
      expect(summary.hourlyActivity[0], closeTo(30 / 60, 0.001));
    });

    test('Clamps sessions ending after midnight to end of day', () {
      final session = AppSession(
        appName: 'LateApp',
        exePath: r'C:\late.exe',
        startTime: DateTime(2026, 10, 11, 23, 15), // 45m today
        endTime: DateTime(2026, 10, 12, 0, 30),    // 30m tomorrow
      );

      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: [session],
      );

      expect(summary.totalActiveTime, equals(const Duration(minutes: 45)));
      expect(summary.hourlyActivity[23], closeTo(45 / 60, 0.001));
    });

    test('Correctly distributes multi-hour session across hourly buckets', () {
      // Session from 10:15 to 12:45 (2h 30m total = 150m)
      // Hour 10 (10:15 - 11:00): 45m -> 45/60 = 0.75
      // Hour 11 (11:00 - 12:00): 60m -> 60/60 = 1.00
      // Hour 12 (12:00 - 12:45): 45m -> 45/60 = 0.75
      final session = AppSession(
        appName: 'DeepWork',
        exePath: r'C:\work.exe',
        startTime: DateTime(2026, 10, 11, 10, 15),
        endTime: DateTime(2026, 10, 11, 12, 45),
      );

      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: [session],
      );

      expect(summary.totalActiveTime, equals(const Duration(hours: 2, minutes: 30)));
      expect(summary.hourlyActivity[10], closeTo(0.75, 0.001));
      expect(summary.hourlyActivity[11], closeTo(1.0, 0.001));
      expect(summary.hourlyActivity[12], closeTo(0.75, 0.001));
      expect(summary.hourlyActivity[9], equals(0.0));
      expect(summary.hourlyActivity[13], equals(0.0));

      // Hourly sum in hours = 0.75 + 1.0 + 0.75 = 2.5 hours = exactly total active time!
      final sumHourlyHours = summary.hourlyActivity.reduce((a, b) => a + b);
      expect(sumHourlyHours, closeTo(2.5, 0.001));
    });

    test('Merges overlapping intervals and avoids double-counting', () {
      // Two overlapping sessions for the same app:
      // Session 1: 14:00 - 14:30 (30m)
      // Session 2: 14:15 - 14:45 (30m)
      // Total non-overlapping active time should be 14:00 - 14:45 = 45m
      final session1 = AppSession(
        appName: 'Browser',
        exePath: r'C:\browser.exe',
        startTime: DateTime(2026, 10, 11, 14, 0),
        endTime: DateTime(2026, 10, 11, 14, 30),
      );
      final session2 = AppSession(
        appName: 'Browser',
        exePath: r'C:\browser.exe',
        startTime: DateTime(2026, 10, 11, 14, 15),
        endTime: DateTime(2026, 10, 11, 14, 45),
      );

      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: [session1, session2],
      );

      expect(summary.totalActiveTime, equals(const Duration(minutes: 45)));
      expect(summary.allApps.first.duration, equals(const Duration(minutes: 45)));
      expect(summary.hourlyActivity[14], closeTo(45 / 60, 0.001));
    });

    test('Handles empty sessions cleanly', () {
      final summary = UsageCalculator.calculateDailySummary(
        date: testDate,
        sessions: [],
      );

      expect(summary.totalActiveTime, equals(Duration.zero));
      expect(summary.allApps, isEmpty);
      expect(summary.mostUsedApps, isEmpty);
      expect(summary.hourlyActivity.every((h) => h == 0.0), isTrue);
    });
  });
}
