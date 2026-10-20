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
import '../../core/widgets/overview_date_picker_dialog.dart';

/// Complete Overview redesign matching the reference image layout, typography,
/// colors, card placement, working date pickers, and balanced column alignment.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late DateTime _selectedDate;
  DailyUsageSummary? _historicalSummary;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool get _isToday {
    final now = DateTime.now();
    return _isSameCalendarDay(_selectedDate, now);
  }

  bool get _isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return _isSameCalendarDay(_selectedDate, yesterday);
  }

  String get _headerDateLabel {
    if (_isToday) {
      return 'Today, ${DateFormat('MMM d, yyyy').format(_selectedDate)}';
    } else if (_isYesterday) {
      return 'Yesterday, ${DateFormat('MMM d, yyyy').format(_selectedDate)}';
    } else {
      return DateFormat('EEE, MMM d, yyyy').format(_selectedDate);
    }
  }

  String get _summaryDateLabel {
    if (_isToday) {
      return 'Today';
    } else if (_isYesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d').format(_selectedDate);
    }
  }

  Future<void> _selectDate(DateTime newDate) async {
    final norm = DateTime(newDate.year, newDate.month, newDate.day);
    if (_isSameCalendarDay(_selectedDate, norm)) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_isSameCalendarDay(norm, today)) {
      setState(() {
        _selectedDate = today;
        _historicalSummary = null;
      });
      return;
    }

    setState(() {
      _selectedDate = norm;
      _historicalSummary = null;
    });

    final tracker = TrackerProvider.of(context);
    final summary = await tracker.getSummaryForDay(norm);

    if (mounted && _isSameCalendarDay(_selectedDate, norm)) {
      setState(() {
        _historicalSummary = summary;
      });
    }
  }

  Future<void> _openDatePicker() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => OverviewDatePickerDialog(
        selectedDate: _selectedDate,
        today: today,
      ),
    );

    if (picked != null) {
      await _selectDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final tracker = TrackerProvider.of(context);
    final focusService = FocusProvider.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([tracker, focusService]),
      builder: (context, _) {
        final todayData = tracker.todaySummary ?? DailyUsageSummary.empty(DateTime.now());
        final data = _isToday
            ? todayData
            : (_historicalSummary ?? DailyUsageSummary.empty(_selectedDate));

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
                                    DailySummaryCard(
                                      data: data,
                                      dateLabel: _summaryDateLabel,
                                      onDateTap: _openDatePicker,
                                      minHeight: 300,
                                    ),
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
                          DailySummaryCard(
                            data: data,
                            dateLabel: _summaryDateLabel,
                            onDateTap: _openDatePicker,
                            minHeight: 300,
                          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final greeting = _getTimeGreeting();
    final userName = _getUserDisplayName();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Date Selector Pill (Interactive)
        InkWell(
          onTap: _openDatePicker,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF2E3445) : colors.surfaceSecondary,
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
                  color: isDark ? const Color(0xFF94A3B8) : colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  _headerDateLabel,
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
                  color: isDark ? const Color(0xFF94A3B8) : colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Top Metric Cards
  // ---------------------------------------------------------------------------

  /// 1. Screen Time Card (Pale Blue in light, subtle blue-tinted dark surface in dark)
  Widget _buildScreenTimeCard(BuildContext context, AppThemeColors colors, DailyUsageSummary data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isToday = _isSameCalendarDay(data.date, DateTime.now());
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
        color: isDark ? colors.cardBlue : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.3) : const Color(0xFFDBEAFE),
        ),
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
                  color: isDark
                      ? const Color(0xFF3B82F6).withValues(alpha: 0.22)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.monitor,
                  size: 16,
                  color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
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
                  isToday ? 'total today' : 'total for day',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progressFraction,
                      minHeight: 5,
                      backgroundColor: isDark
                          ? const Color(0xFF1B2538)
                          : const Color(0xFFDBEAFE),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
                      ),
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
          ),
        ],
      ),
    );
  }

  /// 2. Focus Time Card (Pale Lavender in light, subtle violet-tinted dark surface in dark)
  Widget _buildFocusTimeCard(BuildContext context, AppThemeColors colors, DailyUsageSummary data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final focus = data.focusTime;
    final hours = focus.inHours;
    final minutes = focus.inMinutes.remainder(60);
    final goalHours = data.goalTime.inHours;

    return Container(
      constraints: const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? colors.cardLavender : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFFA855F7).withValues(alpha: 0.3) : const Color(0xFFEDE9FE),
        ),
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
                  color: isDark
                      ? const Color(0xFFA855F7).withValues(alpha: 0.22)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.target,
                  size: 16,
                  color: isDark ? const Color(0xFFC084FC) : const Color(0xFF7C3AED),
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

  /// 3. Breaks Card (Pale Mint in light, subtle green-tinted dark surface in dark)
  Widget _buildBreaksCard(BuildContext context, AppThemeColors colors, DailyUsageSummary data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final breaks = data.breaksTaken;

    return Container(
      constraints: const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? colors.cardMint : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFDCFCE7),
        ),
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
                  color: isDark
                      ? const Color(0xFF10B981).withValues(alpha: 0.22)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.coffee,
                  size: 16,
                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
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
            _isSameCalendarDay(data.date, DateTime.now())
                ? (breaks == 1 ? 'break today' : 'breaks today')
                : (breaks == 1 ? 'break for day' : 'breaks for day'),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
                  ? (isDark ? const Color(0xFFDC2626).withValues(alpha: 0.18) : const Color(0xFFFEE2E2))
                  : (isRunning
                      ? (isDark ? const Color(0xFF10B981).withValues(alpha: 0.18) : const Color(0xFFECFDF5))
                      : (isDark ? colors.surfaceSecondary : const Color(0xFFF1F5F9))),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasError
                  ? LucideIcons.alertTriangle
                  : (isRunning ? LucideIcons.sparkles : LucideIcons.pauseCircle),
              color: hasError
                  ? (isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626))
                  : (isRunning
                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF10B981))
                      : colors.textSecondary),
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
                            : (isRunning
                                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF10B981))
                                : Colors.amber.shade700),
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
                  color: isRunning
                      ? (isDark ? colors.surfaceSecondary : const Color(0xFFF1F5F9))
                      : (isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.18) : const Color(0xFFEFF6FF)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isRunning
                        ? (isDark ? colors.surfaceSecondary : const Color(0xFFE2E8F0))
                        : (isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.35) : const Color(0xFFBFDBFE)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRunning ? LucideIcons.pause : LucideIcons.play,
                      size: 13,
                      color: isRunning
                          ? colors.textPrimary
                          : (isDark ? colors.primaryAccent : const Color(0xFF2563EB)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isRunning ? 'Pause' : 'Resume',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isRunning
                            ? colors.textPrimary
                            : (isDark ? colors.primaryAccent : const Color(0xFF2563EB)),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      key: const Key('activity_timeline_card'),
      constraints: const BoxConstraints(minHeight: 290),
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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? colors.primaryAccent.withValues(alpha: 0.15)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        LucideIcons.activity,
                        color: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
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
                    decoration: BoxDecoration(
                      color: isDark ? colors.surfaceSecondary : const Color(0xFFCBD5E1),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isToday = _isSameCalendarDay(data.date, DateTime.now());
    // Exclude Balance itself from user applications
    final apps = data.allApps
        .where((a) => a.appName.trim().toLowerCase() != 'balance')
        .toList();

    return Container(
      constraints: const BoxConstraints(minHeight: 346),
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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? colors.primaryAccent.withValues(alpha: 0.15)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        LucideIcons.layoutGrid,
                        color: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        isToday
                            ? 'All Applications Today'
                            : 'Applications (${DateFormat('MMM d').format(data.date)})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.arrowRight,
                        size: 14,
                        color: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
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
                      isToday
                          ? 'No application usage recorded today.\nInteract with apps to see them here.'
                          : 'No application usage recorded for ${DateFormat('MMMM d, yyyy').format(data.date)}.',
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
            ...apps.take(5).map((app) => _buildAppRow(context, colors, app, isDark: isDark)),
        ],
      ),
    );
  }

  Widget _buildAppRow(
    BuildContext context,
    AppThemeColors colors,
    AppUsageData app, {
    required bool isDark,
  }) {
    final hours = app.duration.inHours;
    final minutes = app.duration.inMinutes.remainder(60);
    final timeString = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _buildAppIcon(app, isDark, colors),
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
                    backgroundColor: isDark
                        ? colors.surfaceSecondary
                        : const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? colors.primaryAccent : const Color(0xFF3B82F6),
                    ),
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

  Widget _buildAppIcon(AppUsageData app, bool isDark, AppThemeColors colors) {
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
              errorBuilder: (context, error, stackTrace) =>
                  _buildFallbackVectorIcon(app.appName, isDark, colors),
            ),
          );
        } catch (_) {}
      }
    }
    return _buildFallbackVectorIcon(app.appName, isDark, colors);
  }

  Widget _buildFallbackVectorIcon(String appName, bool isDark, AppThemeColors colors) {
    final lower = appName.toLowerCase();
    IconData icon = LucideIcons.appWindow;
    Color iconColor = const Color(0xFF475569);
    Color bgColor = const Color(0xFFF1F5F9);

    if (lower.contains('edge') || lower.contains('browser')) {
      icon = LucideIcons.globe;
      iconColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0078D4);
      bgColor = isDark ? const Color(0xFF0078D4).withValues(alpha: 0.18) : const Color(0xFFE0F2FE);
    } else if (lower.contains('chrome')) {
      icon = LucideIcons.globe;
      iconColor = isDark ? const Color(0xFFF87171) : const Color(0xFFEA4335);
      bgColor = isDark ? const Color(0xFFEA4335).withValues(alpha: 0.18) : const Color(0xFFFEE2E2);
    } else if (lower.contains('whatsapp') || lower.contains('chat') || lower.contains('telegram')) {
      icon = LucideIcons.messageCircle;
      iconColor = isDark ? const Color(0xFF34D399) : const Color(0xFF10B981);
      bgColor = isDark ? const Color(0xFF10B981).withValues(alpha: 0.18) : const Color(0xFFDCFCE7);
    } else if (lower.contains('code') ||
        lower.contains('studio') ||
        lower.contains('antigravity') ||
        lower.contains('ide')) {
      icon = LucideIcons.sparkles;
      iconColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFF8B5CF6);
      bgColor = isDark ? const Color(0xFF8B5CF6).withValues(alpha: 0.18) : const Color(0xFFEDE9FE);
    } else if (lower.contains('vlc') || lower.contains('media') || lower.contains('player')) {
      icon = LucideIcons.playCircle;
      iconColor = isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C);
      bgColor = isDark ? const Color(0xFFEA580C).withValues(alpha: 0.18) : const Color(0xFFFFEDD5);
    } else {
      iconColor = isDark ? colors.textSecondary : const Color(0xFF475569);
      bgColor = isDark ? colors.surfaceSecondary : const Color(0xFFF1F5F9);
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
      key: const Key('daily_activity_card'),
      constraints: const BoxConstraints(minHeight: 290),
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
                  color: isDark
                      ? colors.primaryAccent.withValues(alpha: 0.15)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.trendingUp,
                  color: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
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
                    color: isDark
                        ? colors.surfaceSecondary.withValues(alpha: 0.5)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? colors.surfaceSecondary : const Color(0xFFDBEAFE),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? colors.primaryAccent.withValues(alpha: 0.15)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                LucideIcons.clock,
                                size: 13,
                                color: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
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
                    color: isDark
                        ? colors.surfaceSecondary.withValues(alpha: 0.5)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? colors.surfaceSecondary : const Color(0xFFDCFCE7),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? colors.greenAccent.withValues(alpha: 0.15)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                LucideIcons.layoutGrid,
                                size: 13,
                                color: isDark ? colors.greenAccent : const Color(0xFF059669),
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
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
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
              color: isDark
                  ? colors.surfaceSecondary.withValues(alpha: 0.5)
                  : const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? colors.surfaceSecondary : const Color(0xFFEDE9FE),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isDark
                              ? colors.lavenderAccent.withValues(alpha: 0.15)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          LucideIcons.timer,
                          size: 13,
                          color: isDark ? colors.lavenderAccent : const Color(0xFF7C3AED),
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
