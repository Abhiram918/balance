import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

class ActivityChart extends StatelessWidget {
  final List<double> hourlyData;

  const ActivityChart({super.key, required this.hourlyData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    // Convert data to BarChartGroupData
    final barGroups = List.generate(24, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: hourlyData[index],
            color: colors.primaryAccent,
            width: 8,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 1.0, // Max possible value
              color: colors.primaryAccent.withValues(alpha: 0.1),
            ),
          ),
        ],
      );
    });

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 1.0,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => colors.surfaceSecondary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${group.x.toString().padLeft(2, '0')}:00\n',
                  theme.textTheme.labelLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: '${(rod.toY * 60).toInt()} min',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.textSecondary,
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
                  if (intHour % 4 != 0) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      '${intHour.toString().padLeft(2, '0')}:00',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  );
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
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
              color: colors.textSecondary.withValues(alpha: 0.1),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
}
