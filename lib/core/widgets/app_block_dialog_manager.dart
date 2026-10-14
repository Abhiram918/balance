import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app.dart';
import '../models/app_block_event.dart';
import '../services/limits_service.dart';
import 'app_block_dialog.dart';

/// Top-level overlay manager that listens for application limit block events
/// and presents the [AppBlockDialog].
///
/// Ensures:
/// - Valid BuildContext is always used for presentation.
/// - Events are handled globally regardless of which screen is active.
/// - Duplicate simultaneous dialogs are never stacked.
/// - Later reopen attempts can display the dialog again after dismissal.
/// - Subscriptions are properly disposed without leaks.
class AppBlockDialogManager extends StatefulWidget {
  final LimitsService? limitsService;
  final Widget child;

  const AppBlockDialogManager({
    super.key,
    this.limitsService,
    required this.child,
  });

  @override
  State<AppBlockDialogManager> createState() => _AppBlockDialogManagerState();
}

class _AppBlockDialogManagerState extends State<AppBlockDialogManager> {
  StreamSubscription<AppBlockEvent>? _subscription;
  LimitsService? _activeService;
  bool _isDialogOpen = false;
  String? _currentBlockedAppName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSubscription();
  }

  @override
  void didUpdateWidget(covariant AppBlockDialogManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limitsService != widget.limitsService) {
      _updateSubscription();
    }
  }

  void _updateSubscription() {
    final service = widget.limitsService ?? LimitsProvider.of(context);
    if (_activeService != service) {
      _subscription?.cancel();
      _activeService = service;
      _subscription = service.blockEvents.listen(_handleBlockEvent);
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

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => AppBlockDialog(
          event: event,
          onDismiss: () => Navigator.of(dialogCtx).pop(),
        ),
      );
    } finally {
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
