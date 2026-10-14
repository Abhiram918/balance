import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/features/focus/focus_screen.dart';

class FakeUsageRepository extends UsageRepository {
  ActiveFocusState? _active;
  final List<FocusSessionRecord> _sessions = [];
  final Map<String, String> _settings = {};

  @override
  Future<ActiveFocusState?> getActiveFocusState() async => _active;

  @override
  Future<void> saveActiveFocusState(ActiveFocusState state) async {
    _active = state;
  }

  @override
  Future<void> clearActiveFocusState() async {
    _active = null;
  }

  @override
  Future<FocusSessionRecord> insertFocusSession(FocusSessionRecord session) async {
    final record = FocusSessionRecord(
      id: _sessions.length + 1,
      type: session.type,
      plannedDuration: session.plannedDuration,
      actualDuration: session.actualDuration,
      startTime: session.startTime,
      endTime: session.endTime,
      completedNaturally: session.completedNaturally,
    );
    _sessions.insert(0, record);
    return record;
  }

  @override
  Future<List<FocusSessionRecord>> getRecentFocusSessions({int limit = 10}) async {
    return List.unmodifiable(_sessions.take(limit));
  }

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('Focus Navigation and Widget Survival Tests', () {
    late FakeUsageRepository repository;
    late SettingsService settingsService;
    late WindowsUsageTracker tracker;
    late FocusService focusService;

    setUp(() async {
      repository = FakeUsageRepository();
      settingsService = SettingsService(repository: repository);
      await settingsService.init();

      tracker = WindowsUsageTracker(repository: repository);
      await tracker.init();

      focusService = FocusService(repository: repository);
      await focusService.init();
    });

    tearDown(() {
      focusService.dispose();
      tracker.stop();
    });

    final testTheme = ThemeData.dark().copyWith(
      extensions: [AppThemeColors.dark],
    );

    testWidgets('Timer state survives navigating to other screens and back', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Simple navigation harness to test widget mount/unmount survival
      int selectedTab = 0;
      await tester.pumpWidget(
        SettingsProvider(
          settingsService: settingsService,
          child: TrackerProvider(
            tracker: tracker,
            child: FocusProvider(
              focusService: focusService,
              child: MaterialApp(
                theme: testTheme,
                home: StatefulBuilder(
                  builder: (context, setState) {
                    return Scaffold(
                      body: Column(
                        children: [
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: () => setState(() => selectedTab = 0),
                                child: const Text('Tab Focus'),
                              ),
                              ElevatedButton(
                                onPressed: () => setState(() => selectedTab = 1),
                                child: const Text('Tab Other'),
                              ),
                            ],
                          ),
                          Expanded(
                            child: selectedTab == 0
                                ? const FocusScreen()
                                : const Center(child: Text('Other Content')),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify on FocusScreen
      expect(find.byType(FocusScreen), findsOneWidget);
      expect(find.text('Start Focus'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);

      // Start focus timer
      await tester.tap(find.text('Start Focus'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(focusService.status, equals(FocusStatus.running));
      expect(find.text('Pause'), findsOneWidget);

      // Navigate away to Tab Other
      await tester.tap(find.text('Tab Other'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify FocusScreen widget is completely unmounted
      expect(find.byType(FocusScreen), findsNothing);
      expect(find.text('Other Content'), findsOneWidget);

      // Verify FocusService is STILL running in background!
      expect(focusService.status, equals(FocusStatus.running));
      expect(focusService.isRunning, isTrue);

      // Navigate back to Tab Focus
      await tester.tap(find.text('Tab Focus'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify FocusScreen is mounted again and shows running state
      expect(find.byType(FocusScreen), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(focusService.isRunning, isTrue);

      // Pause the session
      await tester.tap(find.text('Pause'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(focusService.status, equals(FocusStatus.paused));
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('Stop confirmation dialog works properly', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        SettingsProvider(
          settingsService: settingsService,
          child: TrackerProvider(
            tracker: tracker,
            child: FocusProvider(
              focusService: focusService,
              child: MaterialApp(
                theme: testTheme,
                home: const FocusScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Start timer
      await tester.tap(find.text('Start Focus'));
      await tester.pump(const Duration(milliseconds: 100));

      // Stop button (IconButton tooltip 'Stop Session Early')
      final stopButtonFinder = find.byTooltip('Stop Session Early');
      expect(stopButtonFinder, findsOneWidget);
      await tester.tap(stopButtonFinder);
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog appears
      expect(find.text('Stop Session Early?'), findsOneWidget);
      expect(find.text('Keep Going'), findsOneWidget);
      expect(find.text('Stop Session'), findsOneWidget);

      // Tap 'Keep Going'
      await tester.tap(find.text('Keep Going'));
      await tester.pump(const Duration(milliseconds: 300));

      // Session remains running
      expect(focusService.isRunning, isTrue);

      // Tap stop again, then confirm
      await tester.tap(stopButtonFinder);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Stop Session'));
      await tester.pump(const Duration(milliseconds: 300));

      // Session stopped
      expect(focusService.status, equals(FocusStatus.idle));
      expect(find.text('Start Focus'), findsOneWidget);
      expect(focusService.recentSessions.length, equals(1));
    });
  });
}
