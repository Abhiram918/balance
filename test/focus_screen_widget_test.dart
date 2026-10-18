import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/discovered_app.dart';
import 'package:balance/core/models/focus_preset.dart';
import 'package:balance/core/models/focus_session.dart';
import 'package:balance/core/services/focus_service.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/core/services/windows_app_discovery_service.dart';
import 'package:balance/core/services/windows_usage_tracker.dart';
import 'package:balance/features/focus/focus_screen.dart';
import 'package:balance/features/focus/widgets/focus_app_picker_dialog.dart';
import 'package:balance/features/focus/widgets/focus_preset_dialog.dart';
import 'package:balance/features/focus/widgets/focus_preset_selector.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FocusScreen Phase 4 Widget Tests', () {
    late Directory tempDir;
    late String dbPath;
    late UsageRepository repository;
    late SettingsService settingsService;
    late WindowsUsageTracker tracker;
    late FocusService focusService;
    late WindowsAppDiscoveryService discoveryService;
    late DateTime simulatedTime;

    DateTime clock() => simulatedTime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('focus_widget_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}test_focus.db';
      repository = UsageRepository(dbName: dbPath);
      simulatedTime = DateTime(2026, 10, 18, 10, 0, 0);

      settingsService = SettingsService(repository: repository);
      await settingsService.init();

      tracker = WindowsUsageTracker(repository: repository);
      await tracker.init();

      focusService = FocusService(repository: repository, clock: clock);
      await focusService.init();

      discoveryService = WindowsAppDiscoveryService(
        repository: repository,
        startMenuDirectoriesProvider: () => [],
        registryEntriesProvider: () => [
          {'DisplayName': 'Steam', 'DisplayIcon': 'C:\\Steam\\steam.exe'},
          {'DisplayName': 'Discord', 'DisplayIcon': 'C:\\Discord\\discord.exe'},
          {'DisplayName': 'Visual Studio Code', 'DisplayIcon': 'C:\\VSCode\\code.exe'},
          {'DisplayName': 'Windows Explorer', 'DisplayIcon': 'C:\\Windows\\explorer.exe'},
          {'DisplayName': 'Balance', 'DisplayIcon': 'C:\\Balance\\balance.exe'},
        ],
        windowsAppsDirectoryProvider: () => [],
        selfExecutablePathProvider: () => 'C:\\Balance\\balance.exe',
      );
    });

    tearDown(() async {
      focusService.dispose();
      tracker.stop();
      await repository.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    final testTheme = ThemeData.dark().copyWith(
      extensions: [AppThemeColors.dark],
    );

    Widget buildTestHarness() {
      return SettingsProvider(
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
      );
    }

    testWidgets('1. Preset selection and displayed configuration updates idle timer accurately', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Verify preset selector is present
      expect(find.byType(FocusPresetSelector), findsOneWidget);
      expect(find.text('Focus Presets'), findsOneWidget);

      // Verify built-in presets are displayed
      expect(find.text('Standard Pomodoro'), findsOneWidget);
      expect(find.text('Deep Work'), findsOneWidget);
      expect(find.text('Quick Sprint'), findsOneWidget);

      // Verify standard pomodoro initial state: 25:00
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('25m Focus'), findsOneWidget);
      expect(find.text('4 cycles'), findsWidgets);

      // Select Deep Work preset (50 min focus)
      await tester.tap(find.text('Deep Work'));
      await tester.pumpAndSettle();

      // Verify idle timer updated to 50:00
      expect(focusService.selectedPreset?.name, equals('Deep Work'));
      expect(focusService.targetDuration, equals(const Duration(minutes: 50)));
      expect(find.text('50:00'), findsOneWidget);

      // Select Quick Sprint preset (15 min focus)
      await tester.tap(find.text('Quick Sprint'));
      await tester.pumpAndSettle();

      // Verify idle timer updated to 15:00
      expect(focusService.selectedPreset?.name, equals('Quick Sprint'));
      expect(focusService.targetDuration, equals(const Duration(minutes: 15)));
      expect(find.text('15:00'), findsOneWidget);
    });

    testWidgets('2. While session is active, selecting another preset does not mutate running session', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Start Standard Pomodoro (25 min)
      await tester.tap(find.text('Start Focus'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(focusService.isRunning, isTrue);
      expect(focusService.targetDuration, equals(const Duration(minutes: 25)));

      // Attempt to tap "Deep Work" while running
      await tester.tap(find.text('Deep Work'));
      await tester.pump(const Duration(milliseconds: 300));

      // Running session must still have 25m target duration and Standard Pomodoro settings
      expect(focusService.isRunning, isTrue);
      expect(focusService.targetDuration, equals(const Duration(minutes: 25)));
      expect(find.text('Cannot switch preset during an active session.'), findsOneWidget);
    });

    testWidgets('3. Creating a custom preset with validation and saving it persists to list', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Tap "New Preset"
      await tester.tap(find.text('New Preset'));
      await tester.pumpAndSettle();

      // Verify create dialog opened
      expect(find.text('Create Custom Focus Preset'), findsOneWidget);
      expect(find.text('Preset Name *'), findsOneWidget);

      // Attempt saving without name -> shows validation error
      await tester.tap(find.text('Create Preset'));
      await tester.pumpAndSettle();
      expect(find.text('Preset name cannot be empty.'), findsOneWidget);

      // Enter duplicate name ignoring case/whitespace
      await tester.enterText(find.widgetWithText(TextFormField, 'Preset Name *'), '   standard pomodoro   ');
      await tester.tap(find.text('Create Preset'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already exists'), findsOneWidget);

      // Enter valid unique name
      await tester.enterText(find.widgetWithText(TextFormField, 'Preset Name *'), 'Morning Code Sprint');
      await tester.tap(find.text('Create Preset'));
      await tester.pumpAndSettle();

      // Verify new preset exists and appears in the list
      expect(focusService.presets.any((p) => p.name == 'Morning Code Sprint'), isTrue);
      expect(find.text('Morning Code Sprint'), findsOneWidget);

      // Select it and verify
      await tester.tap(find.text('Morning Code Sprint'));
      await tester.pumpAndSettle();
      expect(focusService.selectedPreset?.name, equals('Morning Code Sprint'));
    });

    testWidgets('4. Application picker selects applications and protects system processes', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Open New Preset dialog
      await tester.tap(find.text('New Preset'));
      await tester.pumpAndSettle();

      // Tap "Add Apps" button
      await tester.tap(find.text('Add Apps'));
      await tester.pumpAndSettle();

      // Verify FocusAppPickerDialog opened
      expect(find.text('Select Applications to Block'), findsOneWidget);
      expect(find.byType(FocusAppPickerDialog), findsOneWidget);

      // Discovered apps should be loaded: Steam, Discord, VS Code
      expect(find.text('Steam'), findsOneWidget);
      expect(find.text('Discord'), findsOneWidget);

      // Protected apps (Balance, Windows Explorer) should have Protected badge
      expect(find.text('Protected'), findsWidgets);

      // Select Steam
      await tester.tap(find.text('Steam'));
      await tester.pumpAndSettle();

      // Switch to Manual tab and add custom game
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Application Name *'), 'Minecraft');
      await tester.enterText(find.widgetWithText(TextField, 'Executable Name or Path (Optional)'), 'minecraft.exe');
      await tester.tap(find.text('Add to Block List'));
      await tester.pumpAndSettle();

      // Tap Done
      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      // Verify chips appear in Preset Dialog
      expect(find.text('Steam'), findsOneWidget);
      expect(find.text('Minecraft'), findsOneWidget);

      // Remove a chip (Minecraft)
      final deleteBtnFinder = find.descendant(
        of: find.widgetWithText(Chip, 'Minecraft'),
        matching: find.byIcon(LucideIcons.x),
      );
      await tester.tap(deleteBtnFinder);
      await tester.pumpAndSettle();

      expect(find.text('Minecraft'), findsNothing);
      expect(find.text('Steam'), findsOneWidget);
    });

    testWidgets('5. Active focus, paused, and completed states display accurate phase and blocking info', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Create preset with 1 blocked app
      final customPreset = FocusPreset(
        name: 'Work With Blocked App',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 15),
        cyclesBeforeLongBreak: 4,
        unblockDuringBreaks: true,
        blockedApps: const [
          FocusPresetBlockedApp(appName: 'DistractionApp', exePath: 'distract.exe'),
        ],
      );
      await focusService.createPreset(customPreset);
      await focusService.selectPreset(customPreset);

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Start focus session
      await tester.tap(find.text('Start Focus'));
      await tester.pump(const Duration(milliseconds: 100));

      // Active session banner must be shown
      expect(find.text('Work With Blocked App'), findsWidgets);
      expect(find.text('Focus Phase'), findsOneWidget);
      expect(find.text('Cycle 1 of 4'), findsOneWidget);
      expect(find.text('1 distraction app(s) restricted'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);

      // Pause session
      await tester.tap(find.text('Pause'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      // Resume session
      await tester.tap(find.text('Resume'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(focusService.isRunning, isTrue);

      // Simulate timer ticking down to 0
      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      focusService.tick();
      await focusService.pendingDbOp;
      await tester.pumpAndSettle();

      // Completion banner should be shown
      expect(find.text('Focus Session Completed!'), findsOneWidget);
      expect(find.textContaining('Next: Short Break'), findsWidgets);
      expect(find.text('Back to Ready'), findsOneWidget);
      expect(find.textContaining('Start Short Break'), findsOneWidget);
    });

    testWidgets('6. Manual transition and skip break action in Pomodoro cycle', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Start focus and advance to completion
      await tester.tap(find.text('Start Focus'));
      await tester.pump(const Duration(milliseconds: 100));

      simulatedTime = simulatedTime.add(const Duration(minutes: 25, seconds: 1));
      focusService.tick();
      await focusService.pendingDbOp;
      await tester.pumpAndSettle();

      // Completed banner is shown
      expect(find.text('Focus Session Completed!'), findsOneWidget);

      // Tap "Start Short Break"
      await tester.tap(find.textContaining('Start Short Break'));
      await tester.pump(const Duration(milliseconds: 100));

      // Now running Short Break
      expect(focusService.isRunning, isTrue);
      expect(focusService.sessionType, equals(FocusSessionType.breakSession));
      expect(find.text('Short Break'), findsOneWidget);

      // Skip Break action must be visible
      expect(find.text('Skip Break'), findsOneWidget);

      // Tap "Skip Break"
      await tester.tap(find.text('Skip Break'));
      await tester.pumpAndSettle();

      // Advanced to cycle 2 Focus
      expect(focusService.sessionType, equals(FocusSessionType.focus));
      expect(focusService.currentCycle, equals(2));
      expect(focusService.isIdle, isTrue);
      expect(find.text('Start Focus'), findsOneWidget);
    });

    testWidgets('7. Preset break policy displays accurate unblock information', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Create preset with unblockDuringBreaks: false
      final strictPreset = FocusPreset(
        name: 'Strict Preset',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 15),
        cyclesBeforeLongBreak: 4,
        unblockDuringBreaks: false,
        blockedApps: const [
          FocusPresetBlockedApp(appName: 'SocialMedia', exePath: 'social.exe'),
        ],
      );
      await focusService.createPreset(strictPreset);
      await focusService.selectPreset(strictPreset);

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Switch to Break Time
      await tester.tap(find.text('Break Time'));
      await tester.pumpAndSettle();

      // Start break
      await tester.tap(find.text('Start Break'));
      await tester.pump(const Duration(milliseconds: 100));

      // With unblockDuringBreaks: false, restrictions must be maintained
      expect(find.text('Restrictions maintained (1 apps blocked)'), findsOneWidget);

      await focusService.stop();
      await tester.pumpAndSettle();

      // Switch back to Standard Pomodoro (which has unblockDuringBreaks: true)
      final standard = focusService.presets.firstWhere((p) => p.name == 'Standard Pomodoro');
      await focusService.selectPreset(standard);

      await tester.tap(find.text('Break Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Break'));
      await tester.pump(const Duration(milliseconds: 100));

      // With unblockDuringBreaks: true, shows unblocked message
      expect(find.text('Apps unblocked during break — recharge!'), findsOneWidget);
    });
  });
}
