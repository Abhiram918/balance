class AppUsageData {
  final String appName;
  final String? iconPath; // Use a built-in icon or placeholder for now
  final Duration duration;
  final Duration? dailyLimit;
  final double proportionalUsage;

  AppUsageData({
    required this.appName,
    this.iconPath,
    required this.duration,
    this.dailyLimit,
    required this.proportionalUsage,
  });
}

class FocusSessionData {
  final DateTime startTime;
  final Duration duration;
  final String? label;

  FocusSessionData({
    required this.startTime,
    required this.duration,
    this.label,
  });
}

class DailyUsageSummary {
  final DateTime date;
  final Duration totalActiveTime;
  final Duration goalTime;
  final Duration focusTime;
  final int breaksTaken;
  final List<double> hourlyActivity; // 24 items, values 0.0 - 1.0
  final List<AppUsageData> mostUsedApps;
  final List<AppUsageData> allApps;

  DailyUsageSummary({
    required this.date,
    required this.totalActiveTime,
    required this.goalTime,
    required this.focusTime,
    required this.breaksTaken,
    required this.hourlyActivity,
    required this.mostUsedApps,
    required this.allApps,
  });

  // Demo Data Generator
  static DailyUsageSummary generateDemoData() {
    final now = DateTime.now();
    return DailyUsageSummary(
      date: now,
      totalActiveTime: const Duration(hours: 4, minutes: 23),
      goalTime: const Duration(hours: 6),
      focusTime: const Duration(hours: 2, minutes: 15),
      breaksTaken: 4,
      hourlyActivity: [
        0, 0, 0, 0, 0, 0, // 0-5
        0, 0.1, 0.4, 0.8, 0.6, 0.3, // 6-11
        0.5, 0.9, 0.4, 0.2, 0.7, 0.8, // 12-17
        0.5, 0.3, 0.1, 0, 0, 0, // 18-23
      ],
      mostUsedApps: [
        AppUsageData(
          appName: 'VS Code',
          duration: const Duration(hours: 2, minutes: 10),
          proportionalUsage: 0.5,
          dailyLimit: const Duration(hours: 4),
        ),
        AppUsageData(
          appName: 'Browser',
          duration: const Duration(hours: 1, minutes: 5),
          proportionalUsage: 0.25,
        ),
        AppUsageData(
          appName: 'Design Tool',
          duration: const Duration(minutes: 45),
          proportionalUsage: 0.15,
        ),
      ],
      allApps: [],
    );
  }
}
