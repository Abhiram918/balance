import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../core/services/focus_service.dart';
import '../core/services/limits_service.dart';
import '../core/services/settings_service.dart';
import '../core/widgets/app_shell.dart';
import '../core/services/windows_usage_tracker.dart';

class BalanceApp extends StatefulWidget {
  final WindowsUsageTracker tracker;
  final SettingsService settingsService;
  final FocusService focusService;
  final LimitsService limitsService;

  const BalanceApp({
    super.key,
    required this.tracker,
    required this.settingsService,
    required this.focusService,
    required this.limitsService,
  });

  @override
  State<BalanceApp> createState() => _BalanceAppState();
}

class _BalanceAppState extends State<BalanceApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.focusService.dispose();
    widget.limitsService.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await widget.tracker.stop();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsProvider(
      settingsService: widget.settingsService,
      child: TrackerProvider(
        tracker: widget.tracker,
        child: FocusProvider(
          focusService: widget.focusService,
          child: LimitsProvider(
            limitsService: widget.limitsService,
            child: ListenableBuilder(
              listenable: widget.settingsService,
              builder: (context, _) {
                return MaterialApp(
                  title: 'Balance',
                  debugShowCheckedModeBanner: false,
                  themeMode: widget.settingsService.darkMode ? ThemeMode.dark : ThemeMode.light,
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  home: const AppShell(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsProvider extends InheritedNotifier<SettingsService> {
  const SettingsProvider({
    super.key,
    required SettingsService settingsService,
    required super.child,
  }) : super(notifier: settingsService);

  static SettingsService of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SettingsProvider>()!.notifier!;
  }
}

class TrackerProvider extends InheritedNotifier<WindowsUsageTracker> {
  const TrackerProvider({
    super.key,
    required WindowsUsageTracker tracker,
    required super.child,
  }) : super(notifier: tracker);

  static WindowsUsageTracker of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TrackerProvider>()!.notifier!;
  }
}

class FocusProvider extends InheritedNotifier<FocusService> {
  const FocusProvider({
    super.key,
    required FocusService focusService,
    required super.child,
  }) : super(notifier: focusService);

  static FocusService of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FocusProvider>()!.notifier!;
  }
}

class LimitsProvider extends InheritedNotifier<LimitsService> {
  const LimitsProvider({
    super.key,
    required LimitsService limitsService,
    required super.child,
  }) : super(notifier: limitsService);

  static LimitsService of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LimitsProvider>()!.notifier!;
  }
}


