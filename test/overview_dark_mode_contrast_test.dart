import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/app/theme/app_theme.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/models/usage_data.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/usage_calculator.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/core/widgets/app_shell.dart';
import 'package:balance/core/widgets/daily_summary_card.dart';
import 'package:balance/core/widgets/overview_date_picker_dialog.dart';
import 'package:balance/features/overview/overview_screen.dart';

class MockTrackerForContrastTest extends WindowsUsageTracker {
  bool _running = true;
  final DailyUsageSummary _summary;

  MockTrackerForContrastTest({
    required super.repository,
    required DailyUsageSummary summary,
  }) : _summary = summary;

  @override
  bool get isRunning => _running;

  @override
  DailyUsageSummary? get todaySummary => _summary;

  @override
  Future<DailyUsageSummary> getSummaryForDay(DateTime date) async {
    return _summary;
  }

  @override
  void start() {
    _running = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _running = false;
    notifyListeners();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Overview Screen Dark-Mode & Light-Mode Contrast Tests', () {
    late UsageRepository repository;
    late FocusService focusService;
    late DailyUsageSummary testSummary;

    setUp(() async {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
      focusService = FocusService(repository: repository);
      await focusService.init();

      final now = DateTime.now();
      final sessions = [
        AppSession(
          appName: 'Visual Studio Code',
          exePath: r'C:\Code.exe',
          startTime: now.subtract(const Duration(hours: 2)),
          endTime: now.subtract(const Duration(hours: 1)),
        ),
        AppSession(
          appName: 'Edge',
          exePath: r'C:\Edge.exe',
          startTime: now.subtract(const Duration(minutes: 50)),
          endTime: now.subtract(const Duration(minutes: 20)),
        ),
      ];

      testSummary = UsageCalculator.calculateDailySummary(
        date: now,
        sessions: sessions,
        focusTime: const Duration(minutes: 45),
        breaksTaken: 2,
        breakDuration: const Duration(minutes: 10),
      );
    });

    tearDown(() async {
      await repository.close();
    });

    testWidgets('1. Dark mode renders with dark surface cards and does not use light pastel backgrounds', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final tracker = MockTrackerForContrastTest(
        repository: repository,
        summary: testSummary,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: TrackerProvider(
            tracker: tracker,
            child: FocusProvider(
              focusService: focusService,
              child: AppNavigation(
                navigateTo: (_) {},
                child: const OverviewScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top metric cards: Screen Time, Focus Time, Breaks
      expect(find.text('Screen Time'), findsOneWidget);
      expect(find.text('Focus Time'), findsOneWidget);
      expect(find.text('Breaks'), findsOneWidget);
      expect(find.text('Tracking Active'), findsOneWidget);
      expect(find.text('Daily Summary'), findsOneWidget);
      expect(find.text('Activity Timeline'), findsOneWidget);
      expect(find.text('All Applications Today'), findsOneWidget);
      expect(find.text('Daily Activity'), findsOneWidget);

      // Verify no top card has light pastel background Color(0xFFEFF6FF), Color(0xFFF5F3FF), or Color(0xFFF0FDF4)
      bool foundDarkBlueCard = false;
      bool foundDarkLavenderCard = false;
      bool foundDarkMintCard = false;
      bool foundDarkGoalBox = false;

      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final container in containers) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration && decoration.color != null) {
          final color = decoration.color!;
          // Ensure no light pastel full-card background is present in dark mode
          expect(color != const Color(0xFFEFF6FF), isTrue,
              reason: 'Found light blue 0xFFEFF6FF card in dark mode');
          expect(color != const Color(0xFFF5F3FF), isTrue,
              reason: 'Found light lavender 0xFFF5F3FF card in dark mode');
          expect(color != const Color(0xFFF0FDF4), isTrue,
              reason: 'Found light mint 0xFFF0FDF4 card in dark mode');
          expect(color != const Color(0xFFF8FAFC), isTrue,
              reason: 'Found light 0xFFF8FAFC goal box in dark mode');

          if (color == AppColors.darkBlueSurface) foundDarkBlueCard = true;
          if (color == AppColors.darkLavenderSurface) foundDarkLavenderCard = true;
          if (color == AppColors.darkGreenSurface) foundDarkMintCard = true;
          if (color == const Color(0xFF1B2436)) foundDarkGoalBox = true;
        }
      }

      // Verify restored dark-mode subtle tinted card backgrounds
      expect(foundDarkBlueCard, isTrue, reason: 'Expected Screen Time subtle blue-tinted dark surface in dark mode');
      expect(foundDarkLavenderCard, isTrue, reason: 'Expected Focus Time subtle lavender-tinted dark surface in dark mode');
      expect(foundDarkMintCard, isTrue, reason: 'Expected Breaks subtle green-tinted dark surface in dark mode');
      expect(foundDarkGoalBox, isTrue, reason: 'Expected Daily Goal subtle blue-tinted dark surface in dark mode');

      // Verify Screen Time text is rendered with darkTextPrimary
      final screenTimeText = tester.widget<Text>(find.text('Screen Time'));
      expect(screenTimeText.style?.color, equals(AppColors.darkTextPrimary));

      // Test Pause button in dark mode
      expect(find.text('Pause'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      // Verify Resume button appears with high contrast
      expect(find.text('Resume'), findsOneWidget);
      final resumeText = tester.widget<Text>(find.text('Resume'));
      expect(resumeText.style?.color, equals(AppColors.darkPrimaryBlue));
    });

    testWidgets('2. Light mode preserves original light pastel card backgrounds and contrast', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final tracker = MockTrackerForContrastTest(
        repository: repository,
        summary: testSummary,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: TrackerProvider(
            tracker: tracker,
            child: FocusProvider(
              focusService: focusService,
              child: AppNavigation(
                navigateTo: (_) {},
                child: const OverviewScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In light mode, original light pastel card colors must be preserved
      bool foundPaleBlue = false;
      bool foundPaleLavender = false;
      bool foundPaleMint = false;
      bool foundPaleGoalBox = false;

      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final container in containers) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration && decoration.color != null) {
          final color = decoration.color!;
          if (color == const Color(0xFFEFF6FF)) foundPaleBlue = true;
          if (color == const Color(0xFFF5F3FF)) foundPaleLavender = true;
          if (color == const Color(0xFFF0FDF4)) foundPaleMint = true;
          if (color == const Color(0xFFF8FAFC)) foundPaleGoalBox = true;
        }
      }

      expect(foundPaleBlue, isTrue, reason: 'Expected Color(0xFFEFF6FF) in light mode');
      expect(foundPaleLavender, isTrue, reason: 'Expected Color(0xFFF5F3FF) in light mode');
      expect(foundPaleMint, isTrue, reason: 'Expected Color(0xFFF0FDF4) in light mode');
      expect(foundPaleGoalBox, isTrue, reason: 'Expected Color(0xFFF8FAFC) in light mode');
    });

    testWidgets('3. DailySummaryCard renders correctly in dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DailySummaryCard(
              data: testSummary,
              dateLabel: 'Today',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Daily Summary'), findsOneWidget);
      expect(find.text('Other Usage'), findsOneWidget);
      expect(find.text('Break Time'), findsOneWidget);
      expect(find.text('Focus Sessions'), findsOneWidget);
      expect(find.text('8h goal'), findsOneWidget);

      // Verify no light goal box in dark mode
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final container in containers) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration && decoration.color != null) {
          expect(decoration.color != const Color(0xFFF8FAFC), isTrue);
        }
      }
    });

    testWidgets('4. OverviewDatePickerDialog renders correctly in dark mode', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: OverviewDatePickerDialog(
              selectedDate: now,
              today: now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Date'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Reset to Today'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });
  });
}
