import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../models/usage_data.dart';

class AppUsageTile extends StatelessWidget {
  final AppUsageData appData;

  const AppUsageTile({super.key, required this.appData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    final hours = appData.duration.inHours;
    final minutes = appData.duration.inMinutes.remainder(60);
    final timeString = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.apps, // Fallback icon
              color: colors.primaryAccent,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appData.appName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: appData.proportionalUsage,
                    minHeight: 4,
                    backgroundColor: colors.surfaceSecondary,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colors.primaryAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            timeString,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
