import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../core/services/focus_service.dart';
import '../core/services/limits_service.dart';
import '../core/services/settings_service.dart';
import '../core/widgets/app_block_dialog_manager.dart';
import '../core/widgets/app_shell.dart';
import '../core/services/windows_usage_tracker.dart';

import '../core/services/windows_tray_service.dart';

class BalanceApp extends StatefulWidget {
  final WindowsUsageTracker tracker;
  final SettingsService settingsService;
  final FocusService focusService;
  final LimitsService limitsService;
  final WindowsTrayService? trayService;

  const BalanceApp({
    super.key,
    required this.tracker,
    required this.settingsService,
    required this.focusService,
    required this.limitsService,
    this.trayService,
  });

  @override
  State<BalanceApp> createState() => _BalanceAppState();
}

class _BalanceAppState extends State<BalanceApp> with WidgetsBindingObserver {
  ValueNotifier<bool>? _ownVisibilityNotifier;

  ValueNotifier<bool> get _effectiveVisibilityNotifier {
    if (widget.trayService != null) {
      return widget.trayService!.windowVisibilityNotifier;
    }
    return _ownVisibilityNotifier ??= ValueNotifier<bool>(true);
  }

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
    widget.trayService?.dispose();
    _ownVisibilityNotifier?.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await widget.focusService.handleAppShutdown();
    await widget.tracker.stop();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    return WindowVisibilityProvider(
      visibilityNotifier: _effectiveVisibilityNotifier,
      child: SettingsProvider(
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
                    home: AppBlockDialogManager(
                      onRestoreWindow: widget.trayService != null
                          ? () => widget.trayService!.restoreWindow()
                          : null,
                      child: const AppShell(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WindowVisibilityProvider extends InheritedNotifier<ValueNotifier<bool>> {
  const WindowVisibilityProvider({
    super.key,
    required ValueNotifier<bool> visibilityNotifier,
    required super.child,
  }) : super(notifier: visibilityNotifier);

  static ValueNotifier<bool>? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WindowVisibilityProvider>()?.notifier;
  }

  static bool isVisible(BuildContext context) {
    final notifier = context.dependOnInheritedWidgetOfExactType<WindowVisibilityProvider>()?.notifier;
    return notifier?.value ?? true;
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

  static WindowsUsageTracker? read(BuildContext context) {
    return context.getInheritedWidgetOfExactType<TrackerProvider>()?.notifier;
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



