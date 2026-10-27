import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../app/app.dart';
import '../models/app_block_event.dart';
import '../services/app_enforcement_service.dart';
import '../services/limits_service.dart';
import 'app_block_dialog.dart';

/// Top-level overlay manager that listens for application restriction events
/// (daily limits and focus mode blocks) and presents the [AppBlockDialog].
///
/// Ensures:
/// - Valid BuildContext is always used for presentation.
/// - Events are handled globally regardless of which screen is active.
/// - Duplicate simultaneous dialogs are never stacked.
/// - Later reopen attempts can display the dialog again after dismissal.
/// - Temporarily elevates window to topmost so warning is visible over blocked app.
/// - Always restores normal always-on-top state in finally block when dismissed.
/// - Subscriptions are properly disposed without leaks.
class AppBlockDialogManager extends StatefulWidget {
  final LimitsService? limitsService;
  final AppEnforcementService? enforcementService;
  final FutureOr<void> Function()? onRestoreWindow;
  final FutureOr<void> Function(bool alwaysOnTop)? onSetAlwaysOnTop;
  final FutureOr<bool> Function()? onGetAlwaysOnTop;
  final bool? isPlatformSupported;
  final Widget child;

  const AppBlockDialogManager({
    super.key,
    this.limitsService,
    this.enforcementService,
    this.onRestoreWindow,
    this.onSetAlwaysOnTop,
    this.onGetAlwaysOnTop,
    this.isPlatformSupported,
    required this.child,
  });

  @override
  State<AppBlockDialogManager> createState() => _AppBlockDialogManagerState();
}

class _AppBlockDialogManagerState extends State<AppBlockDialogManager> {
  StreamSubscription<AppBlockEvent>? _subscription;
  Stream<AppBlockEvent>? _activeStream;
  bool _isDialogOpen = false;
  String? _currentBlockedAppName;

  bool get _isPlatformSupported =>
      widget.isPlatformSupported ??
      (!Platform.environment.containsKey('FLUTTER_TEST') && Platform.isWindows);

  Future<bool> _queryInitialAlwaysOnTop() async {
    if (widget.onGetAlwaysOnTop != null) {
      try {
        return await widget.onGetAlwaysOnTop!();
      } catch (_) {
        return false;
      }
    }
    if (_isPlatformSupported) {
      try {
        return await windowManager.isAlwaysOnTop();
      } catch (e) {
        debugPrint('Failed to query isAlwaysOnTop: $e');
      }
    }
    return false;
  }

  Future<void> _applyAlwaysOnTop(bool isAlwaysOnTop) async {
    if (widget.onSetAlwaysOnTop != null) {
      try {
        await widget.onSetAlwaysOnTop!(isAlwaysOnTop);
      } catch (e) {
        debugPrint('onSetAlwaysOnTop callback error: $e');
      }
      return;
    }
    if (_isPlatformSupported) {
      try {
        await windowManager.setAlwaysOnTop(isAlwaysOnTop);
      } catch (e) {
        debugPrint('windowManager.setAlwaysOnTop($isAlwaysOnTop) error: $e');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSubscription();
  }

  @override
  void didUpdateWidget(covariant AppBlockDialogManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limitsService != widget.limitsService ||
        oldWidget.enforcementService != widget.enforcementService) {
      _updateSubscription();
    }
  }

  void _updateSubscription() {
    Stream<AppBlockEvent>? stream;
    if (widget.enforcementService != null) {
      stream = widget.enforcementService!.blockEvents;
    } else if (widget.limitsService != null) {
      stream = widget.limitsService!.blockEvents;
    } else {
      try {
        final provider = LimitsProvider.of(context);
        stream = provider.blockEvents;
      } catch (_) {
        stream = null;
      }
    }

    if (_activeStream != stream) {
      _subscription?.cancel();
      _activeStream = stream;
      if (stream != null) {
        _subscription = stream.listen(_handleBlockEvent);
      }
    }
  }

  void _handleBlockEvent(AppBlockEvent event) {
    if (!mounted) return;

    // Avoid opening duplicate copies of the same dialog if multiple detection events arrive
    if (_isDialogOpen &&
        _currentBlockedAppName?.trim().toLowerCase() ==
            event.appName.trim().toLowerCase()) {
      return;
    }

    _showBlockDialog(event);
  }

  Future<void> _showBlockDialog(AppBlockEvent event) async {
    _isDialogOpen = true;
    _currentBlockedAppName = event.appName;
    bool wasAlwaysOnTop = false;

    try {
      wasAlwaysOnTop = await _queryInitialAlwaysOnTop();

      if (widget.onRestoreWindow != null) {
        await widget.onRestoreWindow!();
      }

      // Temporarily elevate the Balance window above normal application windows
      // so the warning is immediately visible over the blocked app.
      await _applyAlwaysOnTop(true);

      if (_isPlatformSupported) {
        try {
          await windowManager.focus();
        } catch (_) {}
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => AppBlockDialog(
          event: event,
          onDismiss: () => Navigator.of(dialogCtx).pop(),
        ),
      );
    } catch (e) {
      debugPrint('Error presenting app block dialog: $e');
    } finally {
      // Guaranteed to restore normal always-on-top state even if dialog is dismissed
      // or presentation throws an error.
      try {
        await _applyAlwaysOnTop(wasAlwaysOnTop);
      } catch (e) {
        debugPrint('Error restoring window alwaysOnTop state: $e');
      }

      if (mounted) {
        _isDialogOpen = false;
        _currentBlockedAppName = null;
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
