import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/models/focus_session.dart';
import '../../core/services/focus_service.dart';
import '../../core/widgets/page_header.dart';

class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final focusService = FocusProvider.of(context);

    return Scaffold(
      body: ListenableBuilder(
        listenable: focusService,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: PageHeader(
                        title: 'Focus Mode',
                        subtitle: 'Block distractions, work in intervals, and track your focus sessions.',
                      ),
                    ),
                    if (kDebugMode)
                      _buildDevNotificationAction(context, focusService),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildModeSelector(context, focusService),
                const SizedBox(height: AppSpacing.lg),
                _buildDurationPresets(context, focusService),
                const SizedBox(height: AppSpacing.xxl),
                if (focusService.isCompleted)
                  _buildCompletionBanner(context, focusService)
                else
                  _buildTimerCircle(context, focusService),
                const SizedBox(height: AppSpacing.xxl),
                _buildControls(context, focusService),
                const SizedBox(height: AppSpacing.xxl * 1.5),
                _buildSessionHistory(context, focusService),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Segmented switch for Focus vs Break modes.
  Widget _buildModeSelector(BuildContext context, FocusService focusService) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final isLocked = focusService.isRunning || focusService.isPaused;

    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _modeButton(
              context: context,
              label: 'Focus Session',
              icon: LucideIcons.brain,
              isSelected: focusService.sessionType == FocusSessionType.focus,
              activeColor: colors.primaryAccent,
              disabled: isLocked,
              onTap: () => focusService.setSessionType(FocusSessionType.focus),
            ),
            const SizedBox(width: 4),
            _modeButton(
              context: context,
              label: 'Break Time',
              icon: LucideIcons.coffee,
              isSelected: focusService.sessionType == FocusSessionType.breakSession,
              activeColor: colors.greenAccent,
              disabled: isLocked,
              onTap: () => focusService.setSessionType(FocusSessionType.breakSession),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? activeColor
                  : colors.textSecondary.withValues(alpha: disabled ? 0.4 : 1.0),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? colors.textPrimary
                    : colors.textSecondary.withValues(alpha: disabled ? 0.4 : 1.0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Preset chips (15, 25, 45, 60 min for focus; 5, 10, 15 min for break).
  Widget _buildDurationPresets(BuildContext context, FocusService focusService) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final isLocked = focusService.isRunning || focusService.isPaused;

    final presets = focusService.sessionType == FocusSessionType.focus
        ? FocusService.focusPresets
        : FocusService.breakPresets;

    final activeColor = focusService.sessionType == FocusSessionType.focus
        ? colors.primaryAccent
        : colors.greenAccent;

    return Center(
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: presets.map((duration) {
          final isSelected = focusService.targetDuration == duration;
          return ChoiceChip(
            label: Text('${duration.inMinutes} min'),
            selected: isSelected,
            onSelected: isLocked ? null : (_) => focusService.setTargetDuration(duration),
            selectedColor: activeColor.withValues(alpha: 0.18),
            backgroundColor: colors.surfaceSecondary,
            labelStyle: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? activeColor
                  : colors.textSecondary.withValues(alpha: isLocked ? 0.4 : 1.0),
            ),
            side: BorderSide(
              color: isSelected ? activeColor : Colors.transparent,
              width: 1.5,
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Circular Countdown display with glowing ring and smooth progress indicator.
  Widget _buildTimerCircle(BuildContext context, FocusService focusService) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final isFocus = focusService.sessionType == FocusSessionType.focus;
    final accentColor = isFocus ? colors.primaryAccent : colors.greenAccent;

    final totalSeconds = focusService.remainingDuration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final timeString = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    final String statusText;
    if (focusService.isRunning) {
      statusText = isFocus ? 'Focusing in the zone...' : 'Taking a refreshing break...';
    } else if (focusService.isPaused) {
      statusText = 'Session paused';
    } else {
      statusText = isFocus ? 'Ready to focus?' : 'Ready for break?';
    }

    const double circleSize = 310;

    return Center(
      child: SizedBox(
        width: circleSize,
        height: circleSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background container with active glow
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: circleSize - 20,
              height: circleSize - 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surface,
                boxShadow: [
                  BoxShadow(
                    color: focusService.isRunning
                        ? accentColor.withValues(alpha: 0.22)
                        : Colors.black.withValues(alpha: 0.05),
                    blurRadius: focusService.isRunning ? 45 : 15,
                    spreadRadius: focusService.isRunning ? 8 : 0,
                  ),
                ],
              ),
            ),
            // Background track ring
            SizedBox(
              width: circleSize - 20,
              height: circleSize - 20,
              child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: 14,
                color: accentColor.withValues(alpha: 0.12),
              ),
            ),
            // Dynamic countdown progress ring
            SizedBox(
              width: circleSize - 20,
              height: circleSize - 20,
              child: CircularProgressIndicator(
                value: focusService.progressRemaining,
                strokeWidth: 14,
                strokeCap: StrokeCap.round,
                color: accentColor,
              ),
            ),
            // Center texts
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeString,
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: hours > 0 ? 52 : 62,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1.0,
                    color: focusService.isRunning ? accentColor : colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: focusService.isRunning
                        ? accentColor.withValues(alpha: 0.12)
                        : colors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    statusText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: focusService.isRunning ? accentColor : colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Completion card shown when a session finishes.
  Widget _buildCompletionBanner(BuildContext context, FocusService focusService) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final session = focusService.lastCompletedSession;
    final isFocus = (session?.type ?? focusService.sessionType) == FocusSessionType.focus;
    final accentColor = isFocus ? colors.primaryAccent : colors.greenAccent;

    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.12),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFocus ? LucideIcons.partyPopper : LucideIcons.checkCircle2,
                size: 40,
                color: accentColor,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isFocus ? 'Focus Session Completed!' : 'Break Completed!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isFocus
                  ? 'Outstanding focus! You completed your ${session?.plannedDuration.inMinutes ?? focusService.targetDuration.inMinutes}-minute session.'
                  : 'Break is complete. You are recharged and ready for deep work.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => focusService.reset(),
                  icon: const Icon(LucideIcons.rotateCcw, size: 18),
                  label: const Text('Back to Ready'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (isFocus) {
                      await focusService.setSessionType(FocusSessionType.breakSession);
                      focusService.setTargetDuration(const Duration(minutes: 5));
                      await focusService.start();
                    } else {
                      await focusService.setSessionType(FocusSessionType.focus);
                      focusService.setTargetDuration(const Duration(minutes: 25));
                      await focusService.start();
                    }
                  },
                  icon: Icon(isFocus ? LucideIcons.coffee : LucideIcons.flame, size: 18),
                  label: Text(isFocus ? 'Start 5m Break' : 'Start 25m Focus'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Start, Pause, Resume, and Stop controls.
  Widget _buildControls(BuildContext context, FocusService focusService) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final isFocus = focusService.sessionType == FocusSessionType.focus;
    final accentColor = isFocus ? colors.primaryAccent : colors.greenAccent;

    if (focusService.isCompleted) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Stop button with confirmation dialog
        if (focusService.isRunning || focusService.isPaused) ...[
          IconButton.filledTonal(
            iconSize: 24,
            tooltip: 'Stop Session Early',
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(14),
              backgroundColor: colors.surfaceSecondary,
              foregroundColor: colors.textSecondary,
            ),
            icon: const Icon(LucideIcons.square),
            onPressed: () => _confirmStopSession(context, focusService),
          ),
          const SizedBox(width: AppSpacing.lg),
        ],

        // Main Action Button (Start / Pause / Resume)
        if (focusService.isIdle)
          FloatingActionButton.extended(
            onPressed: () => focusService.start(),
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            icon: const Icon(LucideIcons.play),
            label: Text(
              isFocus ? 'Start Focus' : 'Start Break',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          )
        else if (focusService.isRunning)
          FloatingActionButton.extended(
            onPressed: () => focusService.pause(),
            backgroundColor: colors.surfaceSecondary,
            foregroundColor: colors.textPrimary,
            icon: const Icon(LucideIcons.pause),
            label: const Text(
              'Pause',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          )
        else if (focusService.isPaused)
          FloatingActionButton.extended(
            onPressed: () => focusService.resume(),
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            icon: const Icon(LucideIcons.play),
            label: const Text(
              'Resume',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  /// Confirmation dialog before stopping an active session.
  Future<void> _confirmStopSession(BuildContext context, FocusService focusService) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Stop Session Early?'),
          content: const Text(
            'Are you sure you want to stop this session? The time spent so far will still be recorded in your history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Keep Going'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                await focusService.stop();
              },
              child: const Text('Stop Session'),
            ),
          ],
        );
      },
    );
  }

  /// Session history list showing real database records.
  Widget _buildSessionHistory(BuildContext context, FocusService focusService) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final sessions = focusService.recentSessions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.history, size: 20, color: colors.textPrimary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Session History',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${sessions.length} recorded',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (sessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.surfaceSecondary),
            ),
            child: Column(
              children: [
                Icon(LucideIcons.timer, size: 40, color: colors.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'No sessions recorded yet',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Complete your first focus session to start building your streak.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.surfaceSecondary),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sessions.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: colors.surfaceSecondary,
              ),
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isFocus = session.type == FocusSessionType.focus;
                final dateStr = DateFormat('MMM d, h:mm a').format(session.startTime);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isFocus
                          ? colors.primaryAccent.withValues(alpha: 0.12)
                          : colors.greenAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isFocus ? LucideIcons.brain : LucideIcons.coffee,
                      size: 20,
                      color: isFocus ? colors.primaryAccent : colors.greenAccent,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        isFocus ? 'Focus Session' : 'Break',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: session.completedNaturally
                              ? colors.greenAccent.withValues(alpha: 0.15)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          session.completedNaturally ? 'Completed' : 'Stopped Early',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: session.completedNaturally
                                ? colors.greenAccent
                                : Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '$dateStr • Planned: ${session.plannedDuration.inMinutes}m • Actual: ${_formatMinutesSeconds(session.actualDuration)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  trailing: Text(
                    _formatMinutesSeconds(session.actualDuration),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  static String _formatMinutesSeconds(Duration duration) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    if (mins > 0 && secs > 0) {
      return '${mins}m ${secs}s';
    } else if (mins > 0) {
      return '${mins}m';
    } else {
      return '${secs}s';
    }
  }

  /// Temporary development-only notification test action.
  /// Allows testing Windows desktop notifications and audio chime without waiting for a timer to finish.
  Widget _buildDevNotificationAction(BuildContext context, FocusService focusService) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final settings = SettingsProvider.of(context);

    return PopupMenuButton<FocusSessionType>(
      tooltip: 'Development Only: Test desktop completion notification',
      onSelected: (type) async {
        final sent = await focusService.triggerTestNotification(type: type);
        if (!context.mounted) return;

        final sessionLabel = type == FocusSessionType.focus ? 'Focus' : 'Break';
        if (!settings.notifications) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Test $sessionLabel notification suppressed: notifications are turned OFF in Settings.',
              ),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sent
                    ? 'Test $sessionLabel completion notification triggered (audio chime & Windows desktop toast).'
                    : 'Test $sessionLabel notification triggered, but delivery was suppressed or desktop notifications uninitialized.',
              ),
              backgroundColor: colors.surfaceSecondary,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: FocusSessionType.focus,
          child: Row(
            children: [
              Icon(LucideIcons.brain, size: 16),
              SizedBox(width: 8),
              Text('Test Focus Notification'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: FocusSessionType.breakSession,
          child: Row(
            children: [
              Icon(LucideIcons.coffee, size: 16),
              SizedBox(width: 8),
              Text('Test Break Notification'),
            ],
          ),
        ),
      ],
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colors.primaryAccent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bellRing, size: 15, color: colors.primaryAccent),
            const SizedBox(width: 8),
            Text(
              'Test Notification',
              style: TextStyle(
                color: colors.primaryAccent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'DEV',
                style: TextStyle(
                  color: colors.primaryAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: colors.primaryAccent),
          ],
        ),
      ),
    );
  }
}
