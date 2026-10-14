import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:balance/app/app.dart';
import 'package:balance/app/theme/app_colors.dart';
import 'package:balance/core/models/app_limit.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/services/focus_notification_service.dart';
import 'package:balance/core/services/limits_service.dart';
import 'package:balance/core/services/settings_service.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:balance/features/limits/limits_screen.dart';

class FakeNotificationService extends FocusNotificationService {
  @override
  Future<bool> notifyAppLimitWarning({
    required String appName,
    required Duration used,
    required Duration limit,
    required int warningPercentage,
  }) async => true;

  @override
  Future<bool> notifyAppLimitReached({
    required String appName,
    required Duration used,
    required Duration limit,
  }) async => true;
}

class FakeLimitsRepository extends UsageRepository {
  final List<String> distinctApps;
  final List<AppLimit> limits = [];
  final Map<String, String> settings = {};
  int _nextId = 1;

  FakeLimitsRepository({List<String>? initialApps})
      : distinctApps = List.from(initialApps ?? []);

  @override
  Future<List<String>> getDistinctTrackedApps() async {
    return List.unmodifiable(distinctApps);
  }

  @override
  Future<List<Map<String, String>>> getDistinctTrackedAppsWithPaths() async {
    return distinctApps.map((a) => {'appName': a, 'exePath': ''}).toList();
  }

  @override
  Future<List<AppLimit>> getAllLimits() async {
    return List.unmodifiable(limits);
  }

  @override
  Future<AppLimit?> getLimitByAppName(String appName) async {
    final lower = appName.toLowerCase();
    for (final l in limits) {
      if (l.appName.toLowerCase() == lower) {
        return l;
      }
    }
    return null;
  }

  @override
  Future<AppLimit> insertLimit(AppLimit limit) async {
    final created = limit.copyWith(id: _nextId++);
    limits.add(created);
    return created;
  }

  @override
  Future<void> updateLimit(AppLimit limit) async {
    final idx = limits.indexWhere((l) => l.id == limit.id);
    if (idx != -1) {
      limits[idx] = limit;
    }
  }

  @override
  Future<void> deleteLimit(int id) async {
    limits.removeWhere((l) => l.id == id);
  }

  @override
  Future<List<AppSession>> getSessionsForDay(DateTime date) async => [];

  @override
  Future<bool> hasLimitNotificationBeenSent(
    int limitId,
    String notificationType,
    String dateKey,
  ) async => false;

  @override
  Future<void> recordLimitNotificationSent(
    int limitId,
    String notificationType,
    String dateKey,
    DateTime timestamp,
  ) async {}

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('LimitsScreen and Dialog Widget Tests', () {
    late FakeLimitsRepository repository;
    late SettingsService settingsService;
    late LimitsService limitsService;

    setUp(() async {
      repository = FakeLimitsRepository();
      settingsService = SettingsService(repository: repository);
      await settingsService.init();

      limitsService = LimitsService(
        repository: repository,
        notificationService: FakeNotificationService(),
      );
      await limitsService.init();
    });

    tearDown(() {
      limitsService.dispose();
    });

    final testTheme = ThemeData.dark().copyWith(
      extensions: [AppThemeColors.dark],
    );

    Widget buildTestApp() {
      return LimitsProvider(
        limitsService: limitsService,
        child: MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: LimitsScreen(),
          ),
        ),
      );
    }

    testWidgets('Empty state "Set Your First Limit" button opens working dialog and creates limit', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Empty state should be visible
      expect(find.text('No app limits configured'), findsOneWidget);
      final emptyStateButton = find.text('Set Your First Limit');
      expect(emptyStateButton, findsOneWidget);

      // Click button
      await tester.tap(emptyStateButton);
      await tester.pumpAndSettle();

      // Dialog should be open without crashing
      expect(find.text('Set App Limit'), findsOneWidget);
      expect(find.text('Daily Allowance'), findsOneWidget);

      // Enter app name in TextField
      final appNameField = find.widgetWithText(TextField, 'Application Name');
      expect(appNameField, findsOneWidget);
      await tester.enterText(appNameField, 'Slack');
      await tester.pumpAndSettle();

      // Click Create Limit
      final createButton = find.text('Create Limit');
      expect(createButton, findsOneWidget);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // Dialog should close and Slack limit should now be visible on screen
      expect(find.text('Set App Limit'), findsNothing);
      expect(find.text('Slack'), findsOneWidget);
      expect(find.text('Configured Limits'), findsOneWidget);
      expect(limitsService.limits.length, equals(1));
      expect(limitsService.limits.first.appName, equals('Slack'));
    });

    testWidgets('Header "Add Limit" button opens working dialog and selects from tracked apps', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-populate tracked apps and an existing limit
      repository.distinctApps.addAll(['Discord', 'VS Code']);
      await limitsService.createLimit(
        appName: 'Chrome',
        duration: const Duration(hours: 1),
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Header Add Limit button
      final addLimitButton = find.text('Add Limit');
      expect(addLimitButton, findsOneWidget);

      // Click Add Limit button
      await tester.tap(addLimitButton);
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Set App Limit'), findsOneWidget);

      // Searchable picker should be present and show discovered apps
      expect(find.byIcon(LucideIcons.search), findsOneWidget);
      expect(find.text('Discord'), findsWidgets);
      expect(find.text('VS Code'), findsWidgets);

      // Click Create Limit (uses default selected app Discord)
      final createButton = find.text('Create Limit');
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // Dialog closed and both limits exist
      expect(find.text('Set App Limit'), findsNothing);
      expect(find.text('Chrome'), findsOneWidget);
      expect(find.text('Discord'), findsOneWidget);
      expect(limitsService.limits.length, equals(2));
      expect(limitsService.limits.any((l) => l.appName == 'Discord'), isTrue);
    });

    testWidgets('Dialog validation shows error when submitting empty name, and Cancel dismisses dialog', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Open dialog from empty state button
      await tester.tap(find.text('Set Your First Limit'));
      await tester.pumpAndSettle();
      expect(find.text('Set App Limit'), findsOneWidget);

      // Submit without entering app name
      await tester.tap(find.text('Create Limit'));
      await tester.pumpAndSettle();

      // Dialog remains open and displays validation error
      expect(find.text('Set App Limit'), findsOneWidget);
      expect(find.text('Please specify an application name.'), findsOneWidget);

      // Click Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog is dismissed and no limits are created
      expect(find.text('Set App Limit'), findsNothing);
      expect(limitsService.limits, isEmpty);
    });

    testWidgets('Dialog prevents selecting Balance as a limit target', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set Your First Limit'));
      await tester.pumpAndSettle();

      final appNameField = find.widgetWithText(TextField, 'Application Name');
      await tester.enterText(appNameField, 'Balance');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Limit'));
      await tester.pumpAndSettle();

      expect(find.text('Balance itself cannot be set as a limit target.'), findsOneWidget);
      expect(limitsService.limits, isEmpty);
    });

    testWidgets('Search filters apps in searchable picker', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      repository.distinctApps.addAll(['Telegram', 'Microsoft Edge', 'Spotify']);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set Your First Limit'));
      await tester.pumpAndSettle();

      // Initially shows Telegram, Microsoft Edge, Spotify
      expect(find.text('Telegram'), findsWidgets);
      expect(find.text('Microsoft Edge'), findsWidgets);
      expect(find.text('Spotify'), findsWidgets);

      // Type "Edge" in search
      final searchField = find.widgetWithText(TextField, 'Search applications by name or .exe...');
      await tester.enterText(searchField, 'Edge');
      await tester.pumpAndSettle();

      expect(find.text('Microsoft Edge'), findsWidgets);
      expect(find.text('Telegram'), findsNothing);
      expect(find.text('Spotify'), findsNothing);
    });
  });
}
