import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Activity timeline displaying recorded screen time across 24 hourly buckets.
///
/// Features:
/// - Clear y-axis markings (0m, 30m, 60m) so users immediately understand bar heights.
/// - Distinct visual representation for active hours vs. unrecorded past hours vs. future hours.
/// - Detailed hover tooltip with exact minutes and time range.
/// - Concise legend explaining the chart data.
class ActivityChart extends StatelessWidget {
  final List<double> hourlyData;
  final int? currentHour;
  final bool showLegend;

  const ActivityChart({
    super.key,
    required this.hourlyData,
    this.currentHour,
    this.showLegend = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    final nowHour = currentHour ?? DateTime.now().hour;

    // Convert data to BarChartGroupData
    final barGroups = List.generate(24, (index) {
      final value = index < hourlyData.length ? hourlyData[index].clamp(0.0, 1.0) : 0.0;
      final isPastOrCurrent = index <= nowHour;
      final isActive = value > 0.0;

      // Color selection matching reference image and responding to dark theme
      final Color barColor = isActive
          ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB))
          : (isPastOrCurrent
              ? (isDark ? const Color(0xFF2E384D) : const Color(0xFF93C5FD))
              : Colors.transparent);

      // Bar height: if active, actual value (at least 0.04 so very short sessions are visible);
      // if inactive past hour, a tiny baseline dot (0.018); if future hour, 0.0
      final double rodHeight = isActive
          ? (value < 0.04 ? 0.04 : value)
          : (isPastOrCurrent ? 0.018 : 0.0);

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: rodHeight,
            color: barColor,
            width: 7,
            borderRadius: BorderRadius.circular(3),
            backDrawRodData: BackgroundBarChartRodData(
              show: false,
            ),
          ),
        ],
      );
    });

    final chartWidget = SizedBox(
      height: 180,
      child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 1.0,
              minY: 0.0,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) =>
                      isDark ? const Color(0xFF1E222D) : colors.surfaceSecondary,
                  tooltipBorder: BorderSide(
                    color: isDark
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
                        : colors.surfaceSecondary,
                    width: 1,
                  ),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final hour = group.x;
                    final nextHour = (hour + 1) % 24;
                    final rawValue = hour < hourlyData.length ? hourlyData[hour] : 0.0;
                    final minutes = (rawValue * 60).round();
                    final isFuture = hour > nowHour;

                    final timeStr =
                        '${hour.toString().padLeft(2, '0')}:00 – ${nextHour.toString().padLeft(2, '0')}:00';

                    String statusText;
                    if (isFuture) {
                      statusText = 'Future hour';
                    } else if (minutes == 0) {
                      statusText = 'No recorded activity';
                    } else {
                      statusText = '$minutes min active';
                    }

                    return BarTooltipItem(
                      '$timeStr\n',
                      theme.textTheme.labelMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                      children: [
                        TextSpan(
                          text: statusText,
                          style: TextStyle(
                            color: minutes > 0
                                ? (isDark ? const Color(0xFF60A5FA) : colors.primaryAccent)
                                : colors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final intHour = value.toInt();
                      if (intHour % 2 != 0) return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${intHour.toString().padLeft(2, '0')}:00',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                    reservedSize: 24,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: 0.5,
                    getTitlesWidget: (value, meta) {
                      String label = '';
                      if ((value - 0.0).abs() < 0.05) {
                        label = '0m';
                      } else if ((value - 0.5).abs() < 0.05) {
                        label = '30m';
                      } else if ((value - 1.0).abs() < 0.05) {
                        label = '60m';
                      } else {
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          label,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 0.5,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: isDark
                      ? const Color(0xFF2A3142)
                      : colors.textSecondary.withValues(alpha: 0.08),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: barGroups,
            ),
          ),
        );

    if (!showLegend) {
      return chartWidget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLegend(context, colors),
        const SizedBox(height: AppSpacing.md),
        chartWidget,
      ],
    );
  }

  Widget _buildLegend(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Recorded computer usage by hour (up to 60 min per bar)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3B82F6) : colors.primaryAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Active',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2E384D) : colors.surfaceSecondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'No Activity',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
