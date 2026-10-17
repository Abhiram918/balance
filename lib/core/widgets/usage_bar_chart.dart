import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../models/application_analytics_models.dart';

/// Reusable bar chart widget for displaying aggregate or single-application usage
/// across hourly or daily time periods with exact hover tooltips, empty zero bars,
/// and smooth desktop styling.
class UsageBarChart extends StatelessWidget {
  final List<UsageBarData> bars;
  final bool isHourly;
  final String title;
  final Duration totalUsage;
  final Color? barColor;
  final double height;

  const UsageBarChart({
    super.key,
    required this.bars,
    required this.isHourly,
    required this.title,
    required this.totalUsage,
    this.barColor,
    this.height = 320,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final effectiveBarColor = barColor ?? colors.primaryAccent;

    // Determine max value for Y axis (in hours)
    double maxHours = 0.0;
    for (final bar in bars) {
      if (bar.inHours > maxHours) {
        maxHours = bar.inHours;
      }
    }

    // Minimum maxY of 1.0 hour if hourly, or 2.0 hours if daily
    final minMaxY = isHourly ? 1.0 : 2.0;
    final maxY = max(minMaxY, (maxHours * 1.25).ceilToDouble());

    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Chart Title + Total Screen Time badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: effectiveBarColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.clock, size: 13, color: effectiveBarColor),
                    const SizedBox(width: 5),
                    Text(
                      'Total: ${_formatDuration(totalUsage)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: effectiveBarColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Chart area
          Expanded(
            child: bars.isEmpty
                ? _buildEmptyState(colors)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxY,
                          minY: 0,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipColor: (_) => colors.surfaceSecondary,
                              tooltipPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                if (groupIndex >= 0 && groupIndex < bars.length) {
                                  final point = bars[groupIndex];
                                  final durStr = _formatDuration(point.duration);
                                  return BarTooltipItem(
                                    '${point.fullLabel}\n$durStr',
                                    TextStyle(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  );
                                }
                                return null;
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 42,
                                getTitlesWidget: (value, meta) {
                                  if (value == 0) return const SizedBox.shrink();
                                  if (value == meta.max || value == meta.min) {
                                    return const SizedBox.shrink();
                                  }
                                  // Show integer hour marks
                                  if (value == value.roundToDouble()) {
                                    return Text(
                                      '${value.toInt()}h',
                                      style: TextStyle(
                                        color: colors.textSecondary.withValues(alpha: 0.6),
                                        fontSize: 11,
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= bars.length) {
                                    return const SizedBox.shrink();
                                  }

                                  if (isHourly) {
                                    // 24 hours: show labels every 3 or 4 hours
                                    if (idx % 3 != 0 && idx != bars.length - 1) {
                                      return const SizedBox.shrink();
                                    }
                                  } else {
                                    // Multi-day
                                    if (bars.length > 14 && idx % 4 != 0 && idx != bars.length - 1) {
                                      return const SizedBox.shrink();
                                    } else if (bars.length > 7 && idx % 2 != 0 && idx != bars.length - 1) {
                                      return const SizedBox.shrink();
                                    }
                                  }

                                  final bar = bars[idx];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      bar.label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: bar.isCurrent
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: bar.isCurrent
                                            ? effectiveBarColor
                                            : colors.textSecondary,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: maxY <= 2 ? 0.5 : 1.0,
                            getDrawingHorizontalLine: (value) {
                              return FlLine(
                                color: colors.surfaceSecondary.withValues(alpha: 0.7),
                                strokeWidth: 1,
                              );
                            },
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: bars.map((b) {
                            final valHours = b.inHours;
                            // Width of bars scales with number of items
                            final barWidth = isHourly
                                ? (constraints.maxWidth > 800 ? 16.0 : 9.0)
                                : (bars.length <= 7
                                    ? 28.0
                                    : (bars.length <= 14 ? 18.0 : 8.0));

                            final isZero = valHours <= 0;
                            final rodColor = b.isCurrent
                                ? effectiveBarColor
                                : effectiveBarColor.withValues(alpha: 0.85);

                            return BarChartGroupData(
                              x: b.index,
                              barRods: [
                                BarChartRodData(
                                  toY: isZero ? 0.0 : valHours,
                                  color: rodColor,
                                  width: barWidth,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(5),
                                    topRight: Radius.circular(5),
                                  ),
                                  backDrawRodData: BackgroundBarChartRodData(
                                    show: true,
                                    toY: maxY,
                                    color: colors.surfaceSecondary.withValues(alpha: 0.35),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppThemeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.barChart2,
            size: 32,
            color: colors.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No usage activity in this period',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    final secs = d.inSeconds % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else if (mins > 0) {
      return '${mins}m';
    } else if (secs > 0) {
      return '${secs}s';
    } else {
      return '0m';
    }
  }
}
