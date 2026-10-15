import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/models/usage_data.dart';
import '../../core/widgets/activity_chart.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_usage_tile.dart';
import '../../core/widgets/daily_summary_card.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/rounded_metric_card.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final tracker = TrackerProvider.of(context);
    final focusService = FocusProvider.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([tracker, focusService]),
      builder: (context, _) {
        final data = tracker.todaySummary ?? DailyUsageSummary(
          date: DateTime.now(),
          totalActiveTime: Duration.zero,
          goalTime: const Duration(hours: 8),
          focusTime: Duration.zero,
          breaksTaken: 0,
          hourlyActivity: List.filled(24, 0.0),
          mostUsedApps: [],
          allApps: [],
        );

        // Format date like "Monday, Oct 10"
        final dateStr = DateFormat('EEEE, MMM d').format(data.date);

        return Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Your digital day',
                  subtitle: 'Here\'s how your time is adding up today.',
                  contextualDate: dateStr,
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildStatusBanner(context, colors, tracker),
                const SizedBox(height: AppSpacing.xl),

                // Responsive Layout Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column
                          Expanded(
                            flex: 6,
                            child: Column(
                              children: [
                                DailySummaryCard(data: data),
                                const SizedBox(height: AppSpacing.md),
                                _buildActivityChartCard(context, colors, data),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          // Right Column
                          Expanded(
                            flex: 4,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildMetricCard(
                                        context,
                                        colors,
                                        'Focus Time',
                                        _formatDuration(data.focusTime),
                                        colors.cardLavender,
                                        LucideIcons.brain,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: _buildMetricCard(
                                        context,
                                        colors,
                                        'Breaks',
                                        '${data.breaksTaken}',
                                        colors.cardMint,
                                        LucideIcons.coffee,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _buildAppsCard(context, colors, data),
                              ],
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          DailySummaryCard(data: data),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  context,
                                  colors,
                                  'Focus Time',
                                  _formatDuration(data.focusTime),
                                  colors.cardLavender,
                                  LucideIcons.brain,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _buildMetricCard(
                                  context,
                                  colors,
                                  'Breaks',
                                  '${data.breaksTaken}',
                                  colors.cardMint,
                                  LucideIcons.coffee,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildActivityChartCard(context, colors, data),
                          const SizedBox(height: AppSpacing.md),
                          _buildAppsCard(context, colors, data),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBanner(BuildContext context, AppThemeColors colors, tracker) {
    final isRunning = tracker.isRunning;
    final hasError = tracker.hasError;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hasError ? Colors.red.shade100 : (isRunning ? colors.cardMint : Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            hasError ? LucideIcons.alertTriangle : (isRunning ? LucideIcons.activity : LucideIcons.pauseCircle),
            color: hasError ? Colors.red.shade900 : (isRunning ? Colors.green.shade900 : Colors.grey.shade700),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasError ? 'Tracking Error' : (isRunning ? 'Tracking Active' : 'Tracking Paused'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hasError ? Colors.red.shade900 : (isRunning ? Colors.green.shade900 : Colors.grey.shade700),
                  ),
                ),
                if (hasError)
                  Text(
                    tracker.errorMessage,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                  ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (isRunning) {
                tracker.stop();
              } else {
                tracker.start();
              }
            },
            icon: Icon(isRunning ? LucideIcons.pause : LucideIcons.play),
            label: Text(isRunning ? 'Pause' : 'Resume'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRunning ? Colors.white : colors.primaryAccent,
              foregroundColor: isRunning ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityChartCard(
    BuildContext context,
    AppThemeColors colors,
    DailyUsageSummary data,
  ) {
    return RoundedMetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Timeline',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          ActivityChart(hourlyData: data.hourlyActivity),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    AppThemeColors colors,
    String title,
    String value,
    Color bgColor,
    IconData icon,
  ) {
    return RoundedMetricCard(
      backgroundColor: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.textPrimary.withValues(alpha: 0.8), size: 28),
          const SizedBox(height: AppSpacing.lg),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.displayMedium?.copyWith(fontSize: 32),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.textPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppsCard(
    BuildContext context,
    AppThemeColors colors,
    DailyUsageSummary data,
  ) {
    // Exclude Balance from user applications
    final apps = data.allApps.where((a) => a.appName.trim().toLowerCase() != 'balance').toList();

    return RoundedMetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'All Applications Today',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () {
                  AppNavigation.of(context).navigateTo(1);
                },
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (apps.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.mousePointer2,
                      size: 48,
                      color: colors.textSecondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No application usage recorded today.\nInteract with apps to see them here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...apps.take(5).map((app) => AppUsageTile(appData: app)),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return '0h 0m';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }
}
