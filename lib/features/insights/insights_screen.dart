import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/models/analytics_data.dart';
import '../../core/services/usage_analytics_service.dart';
import '../../core/widgets/page_header.dart';

/// Insights screen displaying real, data-driven analytics and trends
/// derived directly from the SQLite database and live tracking.
class InsightsScreen extends StatefulWidget {
  final UsageAnalyticsService? analyticsService;

  const InsightsScreen({super.key, this.analyticsService});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.last7Days;
  PeriodAnalytics? _analytics;
  bool _isLoading = true;
  String? _errorMessage;

  UsageAnalyticsService? _resolvedService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initServiceAndLoad();
  }

  void _initServiceAndLoad() {
    if (widget.analyticsService != null) {
      _resolvedService = widget.analyticsService;
    } else {
      try {
        final tracker = TrackerProvider.of(context);
        _resolvedService = UsageAnalyticsService(
          repository: tracker.repository,
          tracker: tracker,
        );
      } catch (e) {
        _errorMessage = 'Could not access tracking service: $e';
        _isLoading = false;
        return;
      }
    }

    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    if (_resolvedService == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _resolvedService!.getAnalytics(period: _selectedPeriod);
      if (mounted) {
        setState(() {
          _analytics = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load usage analytics: $e';
          _isLoading = false;
        });
      }
    }
  }

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: PageHeader(
                    title: 'Insights',
                    subtitle: _getSubtitleForPeriod(_selectedPeriod),
                  ),
                ),
                _buildPeriodSelector(colors),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_isLoading)
              _buildLoadingState(colors)
            else if (_errorMessage != null)
              _buildErrorState(colors, theme)
            else if (_analytics != null)
              _buildAnalyticsContent(context, colors, theme, _analytics!)
            else
              _buildEmptyState(colors, theme),
          ],
        ),
      ),
    );
  }

  String _getSubtitleForPeriod(AnalyticsPeriod period) {
    switch (period) {
      case AnalyticsPeriod.today:
        return 'Your digital usage and active breakdown for today.';
      case AnalyticsPeriod.last7Days:
        return 'Your weekly digital habits and trends over the last 7 calendar days.';
      case AnalyticsPeriod.last30Days:
        return 'Your 30-day digital trends and long-term usage patterns.';
    }
  }

  Widget _buildPeriodSelector(AppThemeColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AnalyticsPeriod.values.map((period) {
          final isSelected = _selectedPeriod == period;
          return InkWell(
            onTap: () {
              if (_selectedPeriod != period) {
                setState(() {
                  _selectedPeriod = period;
                });
                _loadAnalytics();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                period.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? colors.primaryAccent : colors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoadingState(AppThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colors.primaryAccent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Analyzing recorded usage...',
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(AppThemeColors colors, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.alertTriangle, size: 40, color: Colors.amber),
          const SizedBox(height: AppSpacing.md),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: colors.primaryAccent),
            onPressed: _loadAnalytics,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Retry Analysis'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppThemeColors colors, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(LucideIcons.barChart2, size: 56, color: colors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No usage records found',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Use your applications normally and your digital insights will automatically appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsContent(
    BuildContext context,
    AppThemeColors colors,
    ThemeData theme,
    PeriodAnalytics analytics,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary Cards Row
        _buildSummaryMetricCards(context, colors, theme, analytics),
        const SizedBox(height: AppSpacing.xl),

        // Weekly / Period Bar Chart
        _buildChartCard(context, colors, theme, analytics),
        const SizedBox(height: AppSpacing.xl),

        // Most Used Applications Breakdown
        _buildTopApplicationsSection(context, colors, theme, analytics),
      ],
    );
  }

  Widget _buildSummaryMetricCards(
    BuildContext context,
    AppThemeColors colors,
    ThemeData theme,
    PeriodAnalytics analytics,
  ) {
    final dailyAvgStr = _formatDuration(analytics.dailyAverage);
    final topAppName = analytics.mostUsedApp?.appName ?? 'None';
    final topAppDuration = analytics.mostUsedApp != null
        ? _formatDuration(analytics.mostUsedApp!.duration)
        : '0m';

    final activeDayLabel = analytics.mostActiveDay != null
        ? '${analytics.mostActiveDay!.label} (${_formatDuration(analytics.mostActiveDay!.duration)})'
        : 'None';

    final focusTimeStr = _formatDuration(analytics.totalFocusTime);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final cardList = [
          _buildStatCard(
            context: context,
            colors: colors,
            title: _selectedPeriod == AnalyticsPeriod.last7Days
                ? '7-Day Daily Average'
                : (_selectedPeriod == AnalyticsPeriod.today ? "Today's Usage" : 'Daily Average'),
            value: _selectedPeriod == AnalyticsPeriod.today
                ? _formatDuration(analytics.totalScreenTime)
                : dailyAvgStr,
            subtitle: _selectedPeriod == AnalyticsPeriod.today
                ? _formatComparisonSubtitle(analytics)
                : 'Across all ${analytics.totalDaysCount} calendar days',
            icon: LucideIcons.clock,
            accentColor: colors.primaryAccent,
          ),
          _buildStatCard(
            context: context,
            colors: colors,
            title: 'Most Used Application',
            value: topAppName,
            subtitle: '$topAppDuration in this period',
            icon: LucideIcons.appWindow,
            accentColor: Colors.deepPurpleAccent,
          ),
          _buildStatCard(
            context: context,
            colors: colors,
            title: 'Most Active Day',
            value: activeDayLabel,
            subtitle: '${analytics.activeDaysCount} of ${analytics.totalDaysCount} days active',
            icon: LucideIcons.flame,
            accentColor: Colors.amber.shade800,
          ),
          _buildStatCard(
            context: context,
            colors: colors,
            title: 'Focus Sessions',
            value: focusTimeStr,
            subtitle: 'Dedicated focus time',
            icon: LucideIcons.target,
            accentColor: colors.greenAccent,
          ),
        ];

        if (isWide) {
          return Row(
            children: cardList
                .map((card) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                        child: card,
                      ),
                    ))
                .toList(),
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cardList[0]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cardList[1]),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: cardList[2]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cardList[3]),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  String _formatComparisonSubtitle(PeriodAnalytics analytics) {
    if (analytics.percentageChangeVsPrevious != null) {
      final pct = analytics.percentageChangeVsPrevious!;
      final prefix = pct >= 0 ? '+' : '';
      return '$prefix${pct.toStringAsFixed(0)}% vs yesterday';
    } else if (analytics.previousPeriodScreenTime == Duration.zero &&
        analytics.totalScreenTime > Duration.zero) {
      return '+${_formatDuration(analytics.totalScreenTime)} vs yesterday';
    }
    return 'Same as yesterday';
  }

  Widget _buildStatCard({
    required BuildContext context,
    required AppThemeColors colors,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(
    BuildContext context,
    AppThemeColors colors,
    ThemeData theme,
    PeriodAnalytics analytics,
  ) {
    final series = analytics.dailySeries;
    double maxHours = 0.0;
    for (final point in series) {
      if (point.inHours > maxHours) {
        maxHours = point.inHours;
      }
    }

    // Sensible dynamic maxY (at least 4 hours so small usage doesn't dwarf the scale)
    final maxY = max(4.0, (maxHours * 1.25).ceilToDouble());

    String chartTitle;
    switch (analytics.period) {
      case AnalyticsPeriod.last7Days:
        chartTitle = 'Daily Screen Time (Last 7 Days)';
        break;
      case AnalyticsPeriod.last30Days:
        chartTitle = 'Daily Screen Time (Last 30 Days)';
        break;
      case AnalyticsPeriod.today:
        chartTitle = "Today's Recorded Usage";
        break;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      height: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(chartTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                'Total: ${_formatDuration(analytics.totalScreenTime)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colors.primaryAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: series.isEmpty || !analytics.hasUsage
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.barChart, size: 36, color: colors.textSecondary.withValues(alpha: 0.3)),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'No active usage recorded for this period',
                          style: TextStyle(color: colors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (groupIndex >= 0 && groupIndex < series.length) {
                              final point = series[groupIndex];
                              final dateFormatted = DateFormat('EEE, MMM d').format(point.date);
                              final durStr = _formatDuration(point.duration);
                              return BarTooltipItem(
                                '$dateFormatted\n$durStr',
                                const TextStyle(
                                  color: Colors.white,
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
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < series.length) {
                                // For 30-day view, skip labels to avoid crowding
                                if (analytics.period == AnalyticsPeriod.last30Days && idx % 4 != 0 && idx != series.length - 1) {
                                  return const SizedBox.shrink();
                                }
                                final point = series[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    point.isToday && analytics.period == AnalyticsPeriod.last7Days ? 'Today' : point.label,
                                    style: TextStyle(
                                      color: point.isToday ? colors.primaryAccent : colors.textSecondary,
                                      fontWeight: point.isToday ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 11,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 38,
                            interval: maxY > 6 ? 2 : 1,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink();
                              return Text(
                                '${value.toInt()}h',
                                style: TextStyle(color: colors.textSecondary, fontSize: 11),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY > 6 ? 2 : 1,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: colors.textSecondary.withValues(alpha: 0.08),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(series.length, (index) {
                        final point = series[index];
                        final rodColor = point.isToday
                            ? colors.primaryAccent
                            : (point.isWeekend ? colors.lavenderAccent : colors.primaryAccent.withValues(alpha: 0.82));

                        final rodWidth = analytics.period == AnalyticsPeriod.last30Days
                            ? 6.0
                            : (analytics.period == AnalyticsPeriod.today ? 32.0 : 20.0);

                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: point.inHours,
                              color: rodColor,
                              width: rodWidth,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: maxY,
                                color: colors.surfaceSecondary.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopApplicationsSection(
    BuildContext context,
    AppThemeColors colors,
    ThemeData theme,
    PeriodAnalytics analytics,
  ) {
    final apps = analytics.topApplications;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Application Breakdown',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (apps.isNotEmpty)
                Text(
                  '${apps.length} tracked',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (apps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Column(
                  children: [
                    Icon(LucideIcons.appWindow, size: 40, color: colors.textSecondary.withValues(alpha: 0.3)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No application usage recorded for this period.',
                      style: TextStyle(color: colors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: apps.length,
              separatorBuilder: (context, index) => Divider(
                height: 16,
                thickness: 0.5,
                color: colors.surfaceSecondary,
              ),
              itemBuilder: (context, index) {
                final app = apps[index];
                final rank = index + 1;
                final pct = (app.proportionalUsage * 100).toStringAsFixed(1);
                final appColor = _getAppColor(app.appName);
                final appIcon = _getAppIcon(app.appName);

                return Row(
                  children: [
                    // Rank badge
                    Container(
                      width: 24,
                      alignment: Alignment.center,
                      child: Text(
                        '#$rank',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // Icon
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: appColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(appIcon, color: appColor, size: 18),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // App Name & Progress Bar
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  app.appName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _formatDuration(app.duration),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: app.proportionalUsage.clamp(0.0, 1.0),
                                    minHeight: 5,
                                    backgroundColor: colors.surfaceSecondary,
                                    valueColor: AlwaysStoppedAnimation<Color>(appColor),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  '$pct%',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}m';
    }
  }

  static IconData _getAppIcon(String appName) {
    final lower = appName.toLowerCase();
    if (lower.contains('chrome') ||
        lower.contains('edge') ||
        lower.contains('firefox') ||
        lower.contains('opera') ||
        lower.contains('brave') ||
        lower.contains('browser')) {
      return LucideIcons.globe;
    }
    if (lower.contains('code') ||
        lower.contains('studio') ||
        lower.contains('dev') ||
        lower.contains('terminal') ||
        lower.contains('git')) {
      return LucideIcons.code;
    }
    if (lower.contains('discord') ||
        lower.contains('slack') ||
        lower.contains('teams') ||
        lower.contains('telegram') ||
        lower.contains('whatsapp') ||
        lower.contains('chat')) {
      return LucideIcons.messageSquare;
    }
    if (lower.contains('spotify') || lower.contains('music') || lower.contains('audio')) {
      return LucideIcons.music;
    }
    if (lower.contains('vlc') || lower.contains('video') || lower.contains('player') || lower.contains('netflix')) {
      return LucideIcons.playCircle;
    }
    if (lower.contains('word') || lower.contains('excel') || lower.contains('office') || lower.contains('note') || lower.contains('document')) {
      return LucideIcons.fileText;
    }
    if (lower.contains('game') || lower.contains('steam') || lower.contains('epic')) {
      return LucideIcons.gamepad2;
    }
    if (lower.contains('figma') || lower.contains('design') || lower.contains('paint')) {
      return LucideIcons.palette;
    }
    return LucideIcons.appWindow;
  }

  static Color _getAppColor(String appName) {
    final lower = appName.toLowerCase();
    if (lower.contains('chrome')) return Colors.amber.shade700;
    if (lower.contains('edge') || lower.contains('telegram')) return Colors.blueAccent;
    if (lower.contains('firefox')) return Colors.deepOrangeAccent;
    if (lower.contains('whatsapp') || lower.contains('excel')) return Colors.green;
    if (lower.contains('word')) return Colors.blue.shade800;
    if (lower.contains('code') || lower.contains('studio')) return Colors.indigoAccent;
    if (lower.contains('spotify')) return Colors.greenAccent.shade700;
    if (lower.contains('figma')) return Colors.pinkAccent;
    return const Color(0xFF6366F1);
  }
}
