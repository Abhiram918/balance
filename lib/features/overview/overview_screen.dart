import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/models/usage_data.dart';
import '../../core/widgets/activity_chart.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/daily_summary_card.dart';

/// Complete Overview redesign matching the reference image layout, typography,
/// colors, card placement, and data reconciliation.
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
        final data = tracker.todaySummary ??
            DailyUsageSummary(
              date: DateTime.now(),
              totalActiveTime: Duration.zero,
              goalTime: const Duration(hours: 8),
              focusTime: Duration.zero,
              breaksTaken: 0,
              hourlyActivity: List.filled(24, 0.0),
              mostUsedApps: [],
              allApps: [],
            );

        return Scaffold(
          backgroundColor: colors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, colors, data),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 920;
                    if (isDesktop) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Row: 3 metric cards (left) + Tracking Status card (right)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Row(
                                  children: [
                                    Expanded(child: _buildScreenTimeCard(context, colors, data)),
                                    const SizedBox(width: 14),
                                    Expanded(child: _buildFocusTimeCard(context, colors, data)),
                                    const SizedBox(width: 14),
                                    Expanded(child: _buildBreaksCard(context, colors, data)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 4,
                                child: _buildTrackingStatusCard(context, colors, tracker),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Main Body: Left Column (Daily Summary + Activity Timeline), Right Column (All Apps + Daily Activity)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  children: [
                                    DailySummaryCard(data: data),
                                    const SizedBox(height: 16),
                                    _buildActivityTimelineCard(context, colors, data),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    _buildApplicationsCard(context, colors, data),
                                    const SizedBox(height: 16),
                                    _buildDailyActivityCard(context, colors, data),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          _buildBottomStatusNote(context, colors),
                        ],
                      );
                    } else {
                      // Compact / Responsive Stack
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTrackingStatusCard(context, colors, tracker),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(child: _buildScreenTimeCard(context, colors, data)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildFocusTimeCard(context, colors, data)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildBreaksCard(context, colors, data)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DailySummaryCard(data: data),
                          const SizedBox(height: 16),
                          _buildActivityTimelineCard(context, colors, data),
                          const SizedBox(height: 16),
                          _buildApplicationsCard(context, colors, data),
                          const SizedBox(height: 16),
                          _buildDailyActivityCard(context, colors, data),
                          _buildBottomStatusNote(context, colors),
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

  // ---------------------------------------------------------------------------
  // Header Section
  // ---------------------------------------------------------------------------
  Widget _buildHeader(BuildContext context, AppThemeColors colors, DailyUsageSummary data) {
    final greeting = _getTimeGreeting();
    final userName = _getUserDisplayName();
    final formattedDate = DateFormat("'Today, 'MMM d, yyyy").format(data.date);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              userName,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Keep going. Small steps make a big difference.',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        // Date Selector Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.surfaceSecondary,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.calendar,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                formattedDate,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Top Metric Cards
  // ---------------------------------------------------------------------------

  /// 1. Screen Time Card (Pale Blue)
  Widget _buildScreenTimeCard(BuildContext context, AppThemeColors colors, DailyUsageSummary data) {
    final total = data.totalActiveTime;
    final hours = total.inHours;
    final minutes = total.inMinutes.remainder(60);

    final goalMinutes = data.goalTime.inMinutes > 0 ? data.goalTime.inMinutes : 480;
    final progressFraction = (total.inMinutes / goalMinutes).clamp(0.0, 1.0);
    final goalPercentage = (progressFraction * 100).toInt();
    final goalHours = data.goalTime.inHours;

    return Container(
      constraints: const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.monitor,
                  size: 16,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Screen Time',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${hours}h ${minutes}m',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'total today',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progressFraction,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFDBEAFE),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$goalPercentage% of ${goalHours}h goal',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 2. Focus Time Card (Pale Lavender)
  Widget _buildFocusTimeCard(BuildContext context, AppThemeColors colors, DailyUsageSummary data) {
    final focus = data.focusTime;
    final hours = focus.inHours;
    final minutes = focus.inMinutes.remainder(60);
    final goalHours = data.goalTime.inHours;

    return Container(
      constraints: const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDE9FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.target,
                  size: 16,
                  color: Color(0xFF7C3AED),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Focus Time',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${hours}h ${minutes}m',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'of ${goalHours}h goal',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Breaks Card (Pale Mint)
  Widget _buildBreaksCard(BuildContext context, AppThemeColors colors, DailyUsageSummary data) {
    final breaks = data.breaksTaken;

    return Container(
      constraints: const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCFCE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.coffee,
                  size: 16,
                  color: Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Breaks',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$breaks',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            breaks == 1 ? 'break today' : 'breaks today',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tracking Status Card
  // ---------------------------------------------------------------------------
  Widget _buildTrackingStatusCard(BuildContext context, AppThemeColors colors, tracker) {
    final isRunning = tracker.isRunning;
    final hasError = tracker.hasError;

    return Container(
      constraints: const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: hasError
                  ? const Color(0xFFFEE2E2)
                  : (isRunning ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasError
                  ? LucideIcons.alertTriangle
                  : (isRunning ? LucideIcons.sparkles : LucideIcons.pauseCircle),
              color: hasError
                  ? const Color(0xFFDC2626)
                  : (isRunning ? const Color(0xFF10B981) : colors.textSecondary),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      hasError ? 'Tracking Error' : (isRunning ? 'Tracking Active' : 'Tracking Paused'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: hasError
                            ? const Color(0xFFDC2626)
                            : (isRunning ? const Color(0xFF10B981) : Colors.amber.shade700),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasError ? tracker.errorMessage : 'Monitoring your computer usage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Working Pause/Resume button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (isRunning) {
                  tracker.stop();
                } else {
                  tracker.start();
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isRunning ? const Color(0xFFF1F5F9) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isRunning ? const Color(0xFFE2E8F0) : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRunning ? LucideIcons.pause : LucideIcons.play,
                      size: 13,
                      color: isRunning ? colors.textPrimary : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isRunning ? 'Pause' : 'Resume',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isRunning ? colors.textPrimary : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Activity Timeline Card
  // ---------------------------------------------------------------------------
  Widget _buildActivityTimelineCard(
    BuildContext context,
    AppThemeColors colors,
    DailyUsageSummary data,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary.withValues(alpha: 0.7)),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      LucideIcons.activity,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity Timeline',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Recorded computer usage by hour',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFCBD5E1),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'No Activity',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          ActivityChart(
            hourlyData: data.hourlyActivity,
            showLegend: false,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // All Applications Today Card
  // ---------------------------------------------------------------------------
  Widget _buildApplicationsCard(
    BuildContext context,
    AppThemeColors colors,
    DailyUsageSummary data,
  ) {
    // Exclude Balance itself from user applications
    final apps = data.allApps
        .where((a) => a.appName.trim().toLowerCase() != 'balance')
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary.withValues(alpha: 0.7)),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      LucideIcons.layoutGrid,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'All Applications Today',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  AppNavigation.of(context).navigateTo(1);
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.arrowRight,
                        size: 14,
                        color: Color(0xFF2563EB),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (apps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.mousePointer2,
                      size: 40,
                      color: colors.textSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No application usage recorded today.\nInteract with apps to see them here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...apps.take(5).map((app) => _buildAppRow(context, colors, app)),
        ],
      ),
    );
  }

  Widget _buildAppRow(BuildContext context, AppThemeColors colors, AppUsageData app) {
    final hours = app.duration.inHours;
    final minutes = app.duration.inMinutes.remainder(60);
    final timeString = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildAppIcon(app),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: app.proportionalUsage,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            timeString,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppIcon(AppUsageData app) {
    if (app.iconPath != null && app.iconPath!.isNotEmpty) {
      final file = File(app.iconPath!);
      if (file.existsSync()) {
        try {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: 32,
              height: 32,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildFallbackVectorIcon(app.appName),
            ),
          );
        } catch (_) {}
      }
    }
    return _buildFallbackVectorIcon(app.appName);
  }

  Widget _buildFallbackVectorIcon(String appName) {
    final lower = appName.toLowerCase();
    IconData icon = LucideIcons.appWindow;
    Color iconColor = const Color(0xFF475569);
    Color bgColor = const Color(0xFFF1F5F9);

    if (lower.contains('edge') || lower.contains('browser')) {
      icon = LucideIcons.globe;
      iconColor = const Color(0xFF0078D4);
      bgColor = const Color(0xFFE0F2FE);
    } else if (lower.contains('chrome')) {
      icon = LucideIcons.globe;
      iconColor = const Color(0xFFEA4335);
      bgColor = const Color(0xFFFEE2E2);
    } else if (lower.contains('whatsapp') || lower.contains('chat') || lower.contains('telegram')) {
      icon = LucideIcons.messageCircle;
      iconColor = const Color(0xFF10B981);
      bgColor = const Color(0xFFDCFCE7);
    } else if (lower.contains('code') ||
        lower.contains('studio') ||
        lower.contains('antigravity') ||
        lower.contains('ide')) {
      icon = LucideIcons.sparkles;
      iconColor = const Color(0xFF8B5CF6);
      bgColor = const Color(0xFFEDE9FE);
    } else if (lower.contains('vlc') || lower.contains('media') || lower.contains('player')) {
      icon = LucideIcons.playCircle;
      iconColor = const Color(0xFFEA580C);
      bgColor = const Color(0xFFFFEDD5);
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: iconColor),
    );
  }

  // ---------------------------------------------------------------------------
  // Daily Activity Card
  // ---------------------------------------------------------------------------
  Widget _buildDailyActivityCard(
    BuildContext context,
    AppThemeColors colors,
    DailyUsageSummary data,
  ) {
    final activity = data.dailyActivity;
    final mostActiveHour = activity?.mostActiveHourText ?? 'None recorded';
    final distinctApps = activity?.distinctAppsCount ??
        data.allApps.where((a) => a.appName.trim().toLowerCase() != 'balance').length;

    final longestDur = activity?.longestSessionDuration ?? Duration.zero;
    final longestAppName = activity?.longestSessionAppName ?? 'None recorded';

    final longestDurHours = longestDur.inHours;
    final longestDurMins = longestDur.inMinutes.remainder(60);
    final longestDurText = longestDur == Duration.zero
        ? 'None'
        : (longestDurHours > 0 ? '${longestDurHours}h ${longestDurMins}m' : '${longestDurMins}m');

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary.withValues(alpha: 0.7)),
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
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.trendingUp,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Daily Activity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Row 1: Two small tiles
          Row(
            children: [
              // Most active hour
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              LucideIcons.clock,
                              size: 13,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Most active hour',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mostActiveHour,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Applications used
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDCFCE7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              LucideIcons.layoutGrid,
                              size: 13,
                              color: Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Applications used',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$distinctApps',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'unique apps today',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: One wide tile for Longest active session
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDE9FE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        LucideIcons.timer,
                        size: 13,
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Longest active session',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  longestDurText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  longestAppName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom Status Note
  // ---------------------------------------------------------------------------
  Widget _buildBottomStatusNote(BuildContext context, AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Icon(
            LucideIcons.info,
            size: 14,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            'Your data is updated in real time while tracking is active.',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _getUserDisplayName() {
    final envUser = Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    if (envUser.trim().isNotEmpty) {
      final clean = envUser.trim();
      return clean[0].toUpperCase() + clean.substring(1);
    }
    return 'User';
  }
}
