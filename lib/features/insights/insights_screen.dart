import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/widgets/page_header.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              title: 'Insights',
              subtitle: 'Your weekly digital habits and trends.',
            ),
            const SizedBox(height: AppSpacing.xl),
            _buildWeeklyChartCard(context, colors),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(child: _buildStatCard(context, colors, 'Daily Average', '5h 12m', LucideIcons.clock)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _buildStatCard(context, colors, 'Most Used Category', 'Productivity', LucideIcons.briefcase)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _buildStatCard(context, colors, 'Focus Score', '84%', LucideIcons.target)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChartCard(BuildContext context, AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
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
      height: 350,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This Week', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 8,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        if (value >= 0 && value < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(days[value.toInt()], style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value % 2 == 0) {
                          return Text('${value.toInt()}h', style: TextStyle(color: colors.textSecondary, fontSize: 12));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 2,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colors.textSecondary.withValues(alpha: 0.1),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  _makeGroupData(0, 5, colors.primaryAccent),
                  _makeGroupData(1, 6.5, colors.primaryAccent),
                  _makeGroupData(2, 4, colors.primaryAccent),
                  _makeGroupData(3, 7, colors.primaryAccent),
                  _makeGroupData(4, 5.5, colors.primaryAccent),
                  _makeGroupData(5, 3, colors.lavenderAccent), // Weekend
                  _makeGroupData(6, 4.5, colors.lavenderAccent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _makeGroupData(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 22,
          borderRadius: BorderRadius.circular(6),
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, AppThemeColors colors, String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primaryAccent, size: 28),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
