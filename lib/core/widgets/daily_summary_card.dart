import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../models/usage_data.dart';

/// Daily Summary card reproducing the reference image design:
/// - Donut chart with total screen time in the center.
/// - Legend with Other Usage, Break Time, and Focus Sessions (durations and percentages).
/// - Vertical divider.
/// - Daily goal section with target icon, progress bar, percentage, and remaining time.
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.surfaceSecondary.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, colors),
          const SizedBox(height: AppSpacing.xl),
          _buildBody(context, colors),
        ],
      ),
    );
  }

  /// Card Header with Chart Icon, Title, Subtitle, and Date Selector Pill
  Widget _buildHeader(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.barChart2,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Summary',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your computer usage and activity for today',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Dropdown pill: Today ∨
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.surfaceSecondary,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Today',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Body containing: Donut Chart, Legend, Vertical Divider, and Goal Progress Box
  Widget _buildBody(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);
    final breakdown = data.timeBreakdown;

    final focusSec = breakdown?.focusDuration.inSeconds ?? data.focusTime.inSeconds;
    final breakSec = breakdown?.breakDuration.inSeconds ?? data.breakDuration.inSeconds;
    final otherSec = breakdown?.otherUsageDuration.inSeconds ??
        max(0, data.totalActiveTime.inSeconds - focusSec - breakSec);
    final totalSec = focusSec + breakSec + otherSec;

    final total = data.totalActiveTime;
    final totalHours = total.inHours;
    final totalMins = total.inMinutes.remainder(60);

    // Goal calculation
    final goalMinutes = data.goalTime.inMinutes > 0 ? data.goalTime.inMinutes : 480;
    final progressFraction = (total.inMinutes / goalMinutes).clamp(0.0, 1.0);
    final goalPercentage = (progressFraction * 100).toInt();

    final remainingDuration = data.goalTime > total ? (data.goalTime - total) : Duration.zero;
    final remHours = remainingDuration.inHours;
    final remMins = remainingDuration.inMinutes.remainder(60);
    final remainingText = '${remHours}h ${remMins}m remaining';

    // Color definitions from reference image
    const otherUsageColor = Color(0xFF00A3FF); // Vibrant Sky Blue
    const breakColor = Color(0xFFA855F7);      // Magenta/Purple
    const focusColor = Color(0xFF10B981);      // Emerald/Mint Green

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Donut Chart with total inside
          SizedBox(
            width: 148,
            height: 148,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (totalSec > 0)
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2.5,
                      centerSpaceRadius: 46,
                      startDegreeOffset: -90,
                      sections: [
                        if (otherSec > 0)
                          PieChartSectionData(
                            color: otherUsageColor,
                            value: otherSec.toDouble(),
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
                        if (focusSec > 0)
                          PieChartSectionData(
                            color: focusColor,
                            value: focusSec.toDouble(),
                            title: '',
                            radius: 18,
                          ),
                      ],
                    ),
                  )
                else
                  CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 16,
                    color: colors.surfaceSecondary,
                  ),
                // Center text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${totalHours}h ${totalMins}m',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: colors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'total',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xl),

          // 2. Legend
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegendItem(
                  context: context,
                  colors: colors,
                  color: otherUsageColor,
                  label: 'Other Usage',
                  duration: Duration(seconds: otherSec),
                  totalSeconds: totalSec,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildLegendItem(
                  context: context,
                  colors: colors,
                  color: breakColor,
                  label: 'Break Time',
                  duration: Duration(seconds: breakSec),
                  totalSeconds: totalSec,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildLegendItem(
                  context: context,
                  colors: colors,
                  color: focusColor,
                  label: 'Focus Sessions',
                  duration: Duration(seconds: focusSec),
                  totalSeconds: totalSec,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),

          // 3. Vertical Divider
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colors.surfaceSecondary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: AppSpacing.lg),

          // 4. Daily Goal Box
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.surfaceSecondary.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.target,
                          size: 15,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${data.goalTime.inHours}h goal',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progressFraction,
                            minHeight: 7,
                            backgroundColor: const Color(0xFFE2E8F0),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$goalPercentage%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    remainingText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
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
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          _formatDuration(duration),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(
            '$percentage%',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
