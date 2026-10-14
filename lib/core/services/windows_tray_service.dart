import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

typedef ShutdownHandler = Future<void> Function();

/// Service managing Windows System Tray icon, context menu,
/// double-click restoration, and close-to-tray lifecycle for Balance.
class WindowsTrayService with TrayListener, WindowListener {
  final ShutdownHandler? onShutdown;
  final VoidCallback? onRestore;
  final VoidCallback? onCloseToTray;
  final Duration doubleClickThreshold;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isWindowHidden = false;
  bool get isWindowHidden => _isWindowHidden;

  bool _isShuttingDown = false;
  bool get isShuttingDown => _isShuttingDown;

  DateTime? _lastTrayClickTime;

  final void Function(int)? exitHandler;

  /// Visible for testing to override platform checks in unit tests.
  bool isPlatformSupported;

  WindowsTrayService({
    this.onShutdown,
    this.onRestore,
    this.onCloseToTray,
    this.doubleClickThreshold = const Duration(milliseconds: 500),
    this.exitHandler,
    bool? isPlatformSupported,
  }) : isPlatformSupported = isPlatformSupported ?? Platform.isWindows;

  /// Initializes system tray icon, context menu, and window close interception.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!isPlatformSupported) return;

    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);

      windowManager.addListener(this);
      trayManager.addListener(this);

      // Set tray icon and tooltip
      await trayManager.setIcon('assets/icons/app_icon.ico');
      await trayManager.setToolTip('Balance');

      // Create native context menu
      final menu = Menu(
        items: [
          MenuItem(
            key: 'open_balance',
            label: 'Open Balance',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_balance',
            label: 'Exit Balance',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('Failed to initialize Windows tray/window manager: $e');
    }
  }

  /// Restores and brings the Balance window to the foreground.
  Future<void> restoreWindow() async {
    _isWindowHidden = false;
    if (isPlatformSupported) {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        debugPrint('Failed to show window: $e');
      }
    }
    onRestore?.call();
  }

  /// Hides the Balance window to the system tray while keeping all background
  /// services, timers, and tracking active.
  Future<void> hideToTray() async {
    _isWindowHidden = true;
    if (isPlatformSupported) {
      try {
        await windowManager.hide();
      } catch (e) {
        debugPrint('Failed to hide window to tray: $e');
      }
    }
    onCloseToTray?.call();
  }

  /// Performs a deliberate, clean shutdown of the application:
  /// stops timers, finalizes active sessions, persists data, closes database
  /// connections, removes the tray icon, and destroys the window.
  Future<void> cleanShutdown() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;

    try {
      if (onShutdown != null) {
        await onShutdown!();
      }
    } catch (e) {
      debugPrint('Error during clean shutdown: $e');
    }

    if (isPlatformSupported) {
      try {
        await trayManager.destroy();
      } catch (e) {
        debugPrint('Error destroying tray icon: $e');
      }

      try {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      } catch (e) {
        debugPrint('Error destroying window: $e');
      }
    }

    if (exitHandler != null) {
      exitHandler!(0);
    } else {
      exit(0);
    }
  }

  /// Handles mouse clicks on the tray icon to detect double-click events.
  void handleTrayClick([DateTime? clickTime]) {
    final now = clickTime ?? DateTime.now();
    if (_lastTrayClickTime != null &&
        now.difference(_lastTrayClickTime!) < doubleClickThreshold) {
      _lastTrayClickTime = null;
      restoreWindow();
    } else {
      _lastTrayClickTime = now;
    }
  }

  // --- TrayListener callbacks ---

  @override
  void onTrayIconMouseDown() {
    handleTrayClick();
  }

  @override
  void onTrayIconRightMouseDown() {
    if (isPlatformSupported) {
      try {
        trayManager.popUpContextMenu();
      } catch (e) {
        debugPrint('Error popping up context menu: $e');
      }
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'open_balance') {
      restoreWindow();
    } else if (menuItem.key == 'exit_balance') {
      cleanShutdown();
    }
  }

  // --- WindowListener callbacks ---

  @override
  void onWindowClose() async {
    bool isPreventClose = true;
    if (isPlatformSupported) {
      try {
        isPreventClose = await windowManager.isPreventClose();
      } catch (_) {
        isPreventClose = true;
      }
    }

    if (isPreventClose) {
      await hideToTray();
    }
  }

  /// Disposes listeners and resources.
  void dispose() {
    if (isPlatformSupported) {
      try {
        windowManager.removeListener(this);
        trayManager.removeListener(this);
      } catch (_) {}
    }
  }
}
