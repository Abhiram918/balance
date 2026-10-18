import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../models/app_block_event.dart';

/// Reusable user-facing dialog explaining that an application's daily usage limit
/// has been reached and that access remains blocked until the daily reset.
class AppBlockDialog extends StatelessWidget {
  final AppBlockEvent event;
  final VoidCallback onDismiss;

  const AppBlockDialog({
    super.key,
    required this.event,
    required this.onDismiss,
  });

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return '0m';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}m';
    }
  }

  String _formatResetTime(DateTime resetTime) {
    final timeStr = DateFormat('h:mm a').format(resetTime);
    // If reset time is exactly midnight or beginning of day
    if (resetTime.hour == 0 && resetTime.minute == 0) {
      return 'Resets at midnight ($timeStr)';
    }
    return 'Resets at $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.innerRadius),
            border: Border.all(
              color: colors.surfaceSecondary,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header icon and title
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: event.isFocusBlock
                          ? colors.primaryAccent.withValues(alpha: 0.15)
                          : colors.cardPeach,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      event.isFocusBlock ? LucideIcons.target : LucideIcons.shieldAlert,
                      color: event.isFocusBlock ? colors.primaryAccent : const Color(0xFFE05638),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      event.isFocusBlock ? 'Focus mode restriction' : 'Daily limit reached',
                      key: const Key('block_dialog_title'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Message explaining the block
              Text(
                event.isFocusBlock
                    ? "${event.appName} is blocked during your active focus session${event.focusPresetName != null && event.focusPresetName!.trim().isNotEmpty ? ' (${event.focusPresetName})' : ''}. Stay in the zone!"
                    : "You've reached your daily limit for ${event.appName}. You can't access this app again until your daily limit resets.",
                key: const Key('block_dialog_message'),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Summary container
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: event.isFocusBlock
                    ? Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                LucideIcons.target,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Focus preset:',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                event.focusPresetName ?? 'Focus Mode',
                                key: const Key('block_dialog_preset_name'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.clock,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Remaining focus:',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatDuration(event.remainingFocusDuration ?? Duration.zero),
                                key: const Key('block_dialog_remaining_duration'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16, thickness: 0.5),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.shieldCheck,
                                size: 16,
                                color: colors.primaryAccent,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Unblocks when focus session ends',
                                  key: const Key('block_dialog_reset_time'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: colors.primaryAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                LucideIcons.clock,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Daily limit:',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatDuration(event.limitDuration),
                                key: const Key('block_dialog_limit_duration'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.barChart2,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Used today:',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatDuration(event.usedDuration),
                                key: const Key('block_dialog_used_duration'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16, thickness: 0.5),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.rotateCcw,
                                size: 16,
                                color: colors.primaryAccent,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  _formatResetTime(event.resetTime),
                                  key: const Key('block_dialog_reset_time'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: colors.primaryAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Dismissal button ("Got it")
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('block_dialog_got_it_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primaryAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onDismiss,
                  child: const Text(
                    'Got it',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
