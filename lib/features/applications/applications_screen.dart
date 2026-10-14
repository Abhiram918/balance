import 'package:flutter/material.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/app_usage_tile.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ApplicationsScreen extends StatelessWidget {
  const ApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final tracker = TrackerProvider.of(context);
    final data = tracker.todaySummary;

    final apps = data?.allApps ?? [];

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              title: 'Applications',
              subtitle: 'Detailed view of all your application usage today.',
            ),
            const SizedBox(height: AppSpacing.xl),
            if (apps.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    children: [
                      Icon(LucideIcons.appWindow, size: 64, color: colors.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'No application usage recorded yet.',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: apps.map((app) => AppUsageTile(appData: app)).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
