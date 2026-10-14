import 'package:flutter/material.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_colors.dart';

class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? contextualDate;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.contextualDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (contextualDate != null) ...[
          Text(
            contextualDate!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.primaryAccent,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(title, style: theme.textTheme.displayMedium),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
