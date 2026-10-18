import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/services/app_enforcement_service.dart';
import 'core/services/focus_notification_service.dart';
import 'core/services/focus_service.dart';
import 'core/services/limits_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/usage_repository.dart';
import 'core/services/windows_app_discovery_service.dart';
import 'core/services/windows_tray_service.dart';
import 'core/services/windows_usage_tracker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final repository = UsageRepository();
  final settingsService = SettingsService(repository: repository);
  await settingsService.init();

  final notificationService = FocusNotificationService(settingsService: settingsService);
  await notificationService.init();

  final enforcementService = AppEnforcementService(
    notificationService: notificationService,
  );

  final focusService = FocusService(
    repository: repository,
    notificationService: notificationService,
    enforcementService: enforcementService,
  );
  await focusService.init();

  final discoveryService = WindowsAppDiscoveryService(repository: repository);

  final tracker = WindowsUsageTracker(
    repository: repository,
    discoveryService: discoveryService,
    focusService: focusService,
  );
  tracker.setIdleThreshold(Duration(minutes: settingsService.idleTimeoutMinutes.toInt()));
  await tracker.init();
  tracker.start();

  final limitsService = LimitsService(
    repository: repository,
    notificationService: notificationService,
    tracker: tracker,
    enforcementService: enforcementService,
    discoveryService: discoveryService,
  );
  await limitsService.init();

  final trayService = WindowsTrayService(
    onShutdown: () async {
      await tracker.stop();
      await focusService.handleAppShutdown();
      enforcementService.dispose();
      await repository.close();
    },
  );
  await trayService.init();
  
  runApp(BalanceApp(
    tracker: tracker,
    settingsService: settingsService,
    focusService: focusService,
    limitsService: limitsService,
    trayService: trayService,
  ));
}


