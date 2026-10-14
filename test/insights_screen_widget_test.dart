import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/analytics_data.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/usage_analytics_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/features/insights/insights_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('InsightsScreen Widget Tests', () {
    late UsageRepository repository;
    late WindowsUsageTracker tracker;
    late UsageAnalyticsService analyticsService;

    final refDate = DateTime(2026, 10, 14, 15, 0);

    setUp(() async {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
      await repository.database;

      tracker = WindowsUsageTracker(
        repository: repository,
        foregroundWindowProvider: () => null,
        idleTimeProvider: () => Duration.zero,
      );

      analyticsService = UsageAnalyticsService(
        repository: repository,
        tracker: tracker,
      );
    });

    tearDown(() async {
      await repository.close();
    });

    final testTheme = ThemeData.dark().copyWith(
      extensions: [AppThemeColors.dark],
    );

    Widget buildTestApp({UsageAnalyticsService? service, DateTime? referenceDate}) {
      return TrackerProvider(
        tracker: tracker,
        child: MaterialApp(
          theme: testTheme,
          home: Scaffold(
            body: InsightsScreen(
              analyticsService: service ?? analyticsService,
              referenceDate: referenceDate ?? refDate,
            ),
          ),
        ),
      );
    }

    testWidgets('Displays real data and replaces hardcoded placeholders', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Insert real recorded sessions for Telegram and VS Code on refDate (Oct 14)
      await repository.insertSession(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 9, 0),
        endTime: DateTime(2026, 10, 14, 11, 0), // 2h today
      ));
      await repository.insertSession(AppSession(
        appName: 'Telegram',
        exePath: r'C:\telegram.exe',
        startTime: DateTime(2026, 10, 14, 11, 30),
        endTime: DateTime(2026, 10, 14, 12, 0), // 30m today
      ));

      // Insert a completed focus session
      await repository.insertFocusSession(FocusSessionRecord(
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 25),
        startTime: DateTime(2026, 10, 14, 13, 0),
        endTime: DateTime(2026, 10, 14, 13, 25),
        completedNaturally: true,
      ));

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Insights'), findsOneWidget);

      // Verify hardcoded placeholders are completely gone
      expect(find.text('5h 12m'), findsNothing);
      expect(find.text('Productivity'), findsNothing);
      expect(find.text('84%'), findsNothing);

      // Total usage is 2h 30m. Daily average over 7 days = 150m / 7 = 21m.
      expect(find.text('21m'), findsWidgets);
      expect(find.text('7-Day Daily Average'), findsOneWidget);

      // Most used app should be VS Code (2h)
      expect(find.text('VS Code'), findsWidgets);
      expect(find.text('Most Used Application'), findsOneWidget);

      // Focus sessions metric
      expect(find.text('Focus Sessions'), findsOneWidget);
      expect(find.text('25m'), findsWidgets);

      // Application Breakdown section
      expect(find.text('Application Breakdown'), findsOneWidget);
      expect(find.text('Telegram'), findsWidgets);
      expect(find.text('2h'), findsWidgets);
      expect(find.text('30m'), findsWidgets);
    });

    testWidgets('Empty state appears when no usage records exist', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('0m'), findsWidgets);
      expect(find.text('None'), findsWidgets);
      expect(find.text('No application usage recorded for this period.'), findsOneWidget);
    });

    testWidgets('Period switching updates displayed analytics and subtitle', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Check default Last 7 Days
      expect(find.text('Last 7 Days'), findsOneWidget);
      expect(find.text('Your weekly digital habits and trends over the last 7 calendar days.'), findsOneWidget);

      // Tap Today
      final todayPill = find.text('Today');
      expect(todayPill, findsOneWidget);
      await tester.tap(todayPill);
      await tester.pumpAndSettle();

      expect(find.text('Your digital usage and active breakdown for today.'), findsOneWidget);
      expect(find.text("Today's Usage"), findsOneWidget);

      // Tap Last 30 Days
      final thirtyDaysPill = find.text('Last 30 Days');
      expect(thirtyDaysPill, findsOneWidget);
      await tester.tap(thirtyDaysPill);
      await tester.pumpAndSettle();

      expect(find.text('Your 30-day digital trends and long-term usage patterns.'), findsOneWidget);
      expect(find.text('Daily Screen Time (Last 30 Days)'), findsOneWidget);
    });

    testWidgets('Regression: Background refresh does NOT hide the dashboard with loading spinner', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await repository.insertSession(AppSession(
        appName: 'VS Code',
        exePath: r'C:\vscode.exe',
        startTime: DateTime(2026, 10, 14, 9, 0),
        endTime: DateTime(2026, 10, 14, 10, 0),
      ));

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Dashboard is now fully rendered
      expect(find.text('7-Day Daily Average'), findsOneWidget);
      expect(find.text('VS Code'), findsWidgets);
      expect(find.text('Analyzing recorded usage...'), findsNothing);

      // Simulate live tracker notification (the event that previously caused flickering)
      tracker.notifyListeners();
      await tester.pump(); // Pump frame immediately after notification

      // The dashboard MUST remain visible and MUST NOT flicker back to loading state
      expect(find.text('7-Day Daily Average'), findsOneWidget);
      expect(find.text('VS Code'), findsWidgets);
      expect(find.text('Analyzing recorded usage...'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('7-Day Daily Average'), findsOneWidget);
      expect(find.text('Analyzing recorded usage...'), findsNothing);
    });

    testWidgets('Regression: Repeated tracker notifications do not cause continuous loading flicker', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Fire 10 consecutive tracker ticks (simulating 20 seconds of live tracking)
      for (int i = 0; i < 10; i++) {
        tracker.notifyListeners();
        await tester.pump(const Duration(milliseconds: 100));
        // Verify loading state is NEVER shown while dashboard is already loaded
        expect(find.text('Analyzing recorded usage...'), findsNothing);
      }

      await tester.pumpAndSettle();
      expect(find.text('Insights'), findsOneWidget);
    });

    testWidgets('Regression: Disposing screen cleans up tracker listeners without errors', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Navigate away / replace with empty container (triggers dispose)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Other Screen')),
        ),
      );
      await tester.pumpAndSettle();

      // Tracker notification after dispose should not throw or cause errors
      expect(() => tracker.notifyListeners(), returnsNormally);
    });
  });
}
