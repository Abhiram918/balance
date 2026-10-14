import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

class ScreenTimeRing extends StatelessWidget {
  final Duration activeTime;
  final Duration goalTime;
  final double size;

  const ScreenTimeRing({
    super.key,
    required this.activeTime,
    required this.goalTime,
    this.size = 220,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    final progress = (activeTime.inMinutes / goalTime.inMinutes).clamp(
      0.0,
      1.0,
    );
    final hours = activeTime.inHours;
    final minutes = activeTime.inMinutes.remainder(60);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Ring
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 16,
              color: colors.primaryAccent.withValues(alpha: 0.15),
            ),
          ),
          // Progress Ring
          SizedBox(
            width: size,
            height: size,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOutQuart,
              builder: (context, value, _) {
                return CircularProgressIndicator(
                  value: value,
                  strokeWidth: 16,
                  strokeCap: StrokeCap.round,
                  color: colors.primaryAccent,
                );
              },
            ),
          ),
          // Inner Content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${hours}h ${minutes}m',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 40,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'of ${goalTime.inHours}h goal',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
