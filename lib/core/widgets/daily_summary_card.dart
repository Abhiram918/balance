import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../models/usage_data.dart';
import 'app_shell.dart';

/// Clean, data-driven Daily Summary card replacing the legacy Overview screen time tile.
///
/// Features:
/// - Prominent total computer usage figure and daily screen time goal progress.
/// - Donut chart and legend for Focus, Breaks, and Other Usage without double-counting.
/// - Top Applications list with proportional progress bars and View All action.
class DailySummaryCard extends StatelessWidget {
  final DailyUsageSummary data;

  const DailySummaryCard({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.surfaceSecondary.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, colors),
          const SizedBox(height: AppSpacing.lg),
          _buildUsageHero(context, colors),
          const SizedBox(height: AppSpacing.xl),
          _buildBreakdownSection(context, colors),
          const SizedBox(height: AppSpacing.xl),
          Divider(
            height: 1,
            thickness: 1,
            color: colors.surfaceSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildTopApplicationsSection(context, colors),
        ],
      ),
    );
  }

  /// Card Header with Title and "Today" badge
  Widget _buildHeader(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.barChart2,
              size: 20,
              color: colors.primaryAccent,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Daily Summary',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.primaryAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Today',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.primaryAccent,
            ),
          ),
        ),
      ],
    );
  }

  /// Prominent Total Usage figure and goal progress bar
  Widget _buildUsageHero(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);
    final total = data.totalActiveTime;
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);

    final goalMinutes = data.goalTime.inMinutes > 0 ? data.goalTime.inMinutes : 480;
    final progressFraction = (total.inMinutes / goalMinutes).clamp(0.0, 1.0);
    final percentage = (progressFraction * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${hours}h ${minutes.toString().padLeft(2, '0')}m',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 36,
                letterSpacing: -0.5,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'total screen time',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progressFraction,
                  minHeight: 8,
                  backgroundColor: colors.surfaceSecondary,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progressFraction >= 1.0 ? Colors.amber.shade600 : colors.primaryAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              '$percentage% of ${data.goalTime.inHours}h goal',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Time Breakdown: Donut Chart on left, Legend on right
  Widget _buildBreakdownSection(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);
    final breakdown = data.timeBreakdown;

    final focusSec = breakdown?.focusDuration.inSeconds ?? data.focusTime.inSeconds;
    final breakSec = breakdown?.breakDuration.inSeconds ?? data.breakDuration.inSeconds;
    final otherSec = breakdown?.otherUsageDuration.inSeconds ??
        max(0, data.totalActiveTime.inSeconds - focusSec - breakSec);
    final totalSec = focusSec + breakSec + otherSec;

    final hasData = totalSec > 0;

    // Palette: Focus (Primary Indigo), Breaks (Emerald Green), Other Usage (Sky Blue)
    final focusColor = colors.primaryAccent;
    const breakColor = Color(0xFF10B981); // Emerald Mint
    const otherColor = Color(0xFF38BDF8); // Sky Blue

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Donut Chart
        SizedBox(
          width: 130,
          height: 130,
          child: hasData
              ? PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    startDegreeOffset: -90,
                    sections: [
                      if (focusSec > 0)
                        PieChartSectionData(
                          color: focusColor,
                          value: focusSec.toDouble(),
                          title: '',
                          radius: 18,
                        ),
                      if (breakSec > 0)
                        PieChartSectionData(
                          color: breakColor,
                          value: breakSec.toDouble(),
                          title: '',
                          radius: 18,
                        ),
                      if (otherSec > 0)
                        PieChartSectionData(
                          color: otherColor,
                          value: otherSec.toDouble(),
                          title: '',
                          radius: 18,
                        ),
                    ],
                  ),
                )
              : Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 10,
                          color: colors.surfaceSecondary,
                        ),
                      ),
                      Icon(
                        LucideIcons.clock,
                        size: 24,
                        color: colors.textSecondary.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.xl),

        // Legend with exact durations and percentages
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendRow(
                context: context,
                colors: colors,
                color: focusColor,
                label: 'Focus Sessions',
                duration: Duration(seconds: focusSec),
                totalSeconds: totalSec,
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildLegendRow(
                context: context,
                colors: colors,
                color: breakColor,
                label: 'Break Time',
                duration: Duration(seconds: breakSec),
                totalSeconds: totalSec,
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildLegendRow(
                context: context,
                colors: colors,
                color: otherColor,
                label: 'Other Usage',
                duration: Duration(seconds: otherSec),
                totalSeconds: totalSec,
              ),
              if (!hasData)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'No activity recorded today',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendRow({
    required BuildContext context,
    required AppThemeColors colors,
    required Color color,
    required String label,
    required Duration duration,
    required int totalSeconds,
  }) {
    final theme = Theme.of(context);
    final percentage = totalSeconds > 0
        ? ((duration.inSeconds / totalSeconds) * 100).round()
        : 0;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          _formatDuration(duration),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 36,
          child: Text(
            '$percentage%',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// Top Applications List with Proportional Progress Bars
  Widget _buildTopApplicationsSection(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);
    final apps = data.mostUsedApps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Top Applications',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () {
                AppNavigation.of(context).navigateTo(1);
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View All'),
                  SizedBox(width: 4),
                  Icon(LucideIcons.chevronRight, size: 14),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  size: 16,
                  color: colors.textSecondary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'No application usage recorded today.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          ...apps.take(3).map((app) => _buildAppRow(context, colors, app)),
      ],
    );
  }

  Widget _buildAppRow(
    BuildContext context,
    AppThemeColors colors,
    AppUsageData app,
  ) {
    final theme = Theme.of(context);
    final totalActiveSec = data.totalActiveTime.inSeconds;
    final proportion = totalActiveSec > 0
        ? (app.duration.inSeconds / totalActiveSec).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.primaryAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  app.appName.isNotEmpty ? app.appName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colors.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  app.appName,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                _formatDuration(app.duration),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: proportion,
              minHeight: 4,
              backgroundColor: colors.surfaceSecondary.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(
                colors.primaryAccent.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return '0m';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) {
      return '${h}h ${m}m';
    }
    return '${m}m';
  }
}
