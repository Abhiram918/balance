import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/models/app_limit.dart';
import '../../core/models/application_analytics_models.dart';
import '../../core/services/application_analytics_service.dart';
import '../../core/services/limits_service.dart';
import '../../core/services/windows_usage_tracker.dart';
import '../../core/widgets/app_limit_dialog.dart';
import '../../core/widgets/applications_date_selector.dart';
import '../../core/widgets/usage_bar_chart.dart';

/// Dedicated analytics dashboard for an individual tracked Windows application.
class ApplicationDetailScreen extends StatefulWidget {
  final String appName;
  final String? exePath;
  final DateRangeSelection initialSelection;
  final VoidCallback? onBack;
  final ApplicationAnalyticsService? analyticsService;
  final DateTime? referenceDate;
  final Duration backgroundThrottleDuration;
  final Duration debounceDuration;
  final ValueListenable<bool>? windowVisibility;
  final DateTime Function()? clock;

  const ApplicationDetailScreen({
    super.key,
    required this.appName,
    this.exePath,
    required this.initialSelection,
    this.onBack,
    this.analyticsService,
    this.referenceDate,
    this.backgroundThrottleDuration = const Duration(seconds: 10),
    this.debounceDuration = const Duration(milliseconds: 250),
    this.windowVisibility,
    this.clock,
  });

  @override
  State<ApplicationDetailScreen> createState() => _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState extends State<ApplicationDetailScreen> {
  late DateRangeSelection _selection;
  SingleAppAnalyticsResult? _analytics;
  bool _isLoading = true;
  String? _errorMessage;

  ApplicationAnalyticsService? _resolvedService;
  WindowsUsageTracker? _tracker;
  LimitsService? _limitsService;
  bool _isInitialized = false;
  int _requestId = 0;

  Timer? _debounceTimer;
  DateTime _lastBackgroundLoadTime = DateTime.fromMillisecondsSinceEpoch(0);
  ValueListenable<bool>? _visibilityListenable;
  bool _isWindowVisible = true;
  bool _needsRefreshOnRestore = false;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      _visibilityListenable = widget.windowVisibility ?? WindowVisibilityProvider.of(context);
      _visibilityListenable?.addListener(_onVisibilityChanged);
      _isWindowVisible = _visibilityListenable?.value ?? true;
      _initAndLoad();
    }
  }

  @override
  void didUpdateWidget(ApplicationDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowVisibility != widget.windowVisibility) {
      _visibilityListenable?.removeListener(_onVisibilityChanged);
      _visibilityListenable = widget.windowVisibility ?? WindowVisibilityProvider.of(context);
      _visibilityListenable?.addListener(_onVisibilityChanged);
      _isWindowVisible = _visibilityListenable?.value ?? true;
    }
  }

  void _initAndLoad() {
    final tracker = TrackerProvider.read(context);
    _tracker = tracker;
    _tracker?.addListener(_onTrackerOrLimitsChanged);

    try {
      _limitsService = LimitsProvider.of(context);
      _limitsService?.addListener(_onTrackerOrLimitsChanged);
    } catch (_) {}

    if (widget.analyticsService != null) {
      _resolvedService = widget.analyticsService;
    } else if (tracker != null) {
      _resolvedService = ApplicationAnalyticsService(
        repository: tracker.repository,
        tracker: tracker,
        limitsService: _limitsService,
      );
    } else {
      setState(() {
        _errorMessage = 'Could not access local tracking service';
        _isLoading = false;
      });
      return;
    }

    _lastBackgroundLoadTime = widget.clock != null ? widget.clock!() : DateTime.now();
    _loadAnalytics();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tracker?.removeListener(_onTrackerOrLimitsChanged);
    _limitsService?.removeListener(_onTrackerOrLimitsChanged);
    _visibilityListenable?.removeListener(_onVisibilityChanged);
    super.dispose();
  }

  void _onTrackerOrLimitsChanged() {
    if (!mounted) return;
    if (!_isWindowVisible) {
      _needsRefreshOnRestore = true;
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      if (!mounted) return;
      if (!_isWindowVisible) {
        _needsRefreshOnRestore = true;
        return;
      }
      final now = widget.clock != null ? widget.clock!() : DateTime.now();
      if (now.difference(_lastBackgroundLoadTime) >= widget.backgroundThrottleDuration) {
        _lastBackgroundLoadTime = now;
        _loadAnalytics(isBackground: true);
      }
    });
  }

  void _onVisibilityChanged() {
    if (!mounted) return;
    final isVisible = _visibilityListenable?.value ?? true;
    if (_isWindowVisible != isVisible) {
      _isWindowVisible = isVisible;
      if (_isWindowVisible && _needsRefreshOnRestore) {
        _needsRefreshOnRestore = false;
        _debounceTimer?.cancel();
        _lastBackgroundLoadTime = widget.clock != null ? widget.clock!() : DateTime.now();
        _loadAnalytics(isBackground: true);
      }
    }
  }

  Future<void> _loadAnalytics({bool isBackground = false}) async {
    if (_resolvedService == null) return;
    final currentReq = ++_requestId;

    if (!isBackground && _analytics == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final result = await _resolvedService!.getSingleAppAnalytics(
        appName: widget.appName,
        exePath: widget.exePath,
        selection: _selection,
        referenceDate: widget.referenceDate,
      );

      if (!mounted || currentReq != _requestId) return;

      setState(() {
        _analytics = result;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted || currentReq != _requestId) return;
      setState(() {
        _isLoading = false;
        if (_analytics == null) {
          _errorMessage = 'Failed to load analytics: $e';
        }
      });
    }
  }

  void _onDateSelectionChanged(DateRangeSelection newSelection) {
    setState(() {
      _selection = newSelection;
    });
    _loadAnalytics();
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final appColor = getAppColor(widget.appName);
    final appIcon = getAppIcon(widget.appName);

    return Scaffold(
      backgroundColor: colors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation Bar (Back button + Date Selector)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: _handleBack,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.surfaceSecondary),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.arrowLeft, size: 16, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Back to Applications',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ApplicationsDateSelector(
                  selection: _selection,
                  onSelectionChanged: _onDateSelectionChanged,
                  referenceDate: widget.referenceDate,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Application Hero Banner
            _buildAppHeader(theme, colors, appColor, appIcon),
            const SizedBox(height: AppSpacing.xl),

            if (_isLoading && _analytics == null)
              _buildLoadingState(colors)
            else if (_errorMessage != null && _analytics == null)
              _buildErrorState(colors)
            else ...[
              // Summary Metric Cards
              _buildMetricCards(theme, colors, appColor),
              const SizedBox(height: AppSpacing.xl),

              // Application Specific Usage Bar Chart
              UsageBarChart(
                bars: _analytics?.chartBars ?? const [],
                isHourly: _selection.isHourly,
                title: '${widget.appName} Usage (${_selection.formattedDisplayLabel})',
                totalUsage: _analytics?.totalUsage ?? Duration.zero,
                barColor: appColor,
                height: 340,
              ),
              const SizedBox(height: AppSpacing.xl),

              // Limit Management Card
              _buildLimitManagementSection(theme, colors),
              const SizedBox(height: AppSpacing.xl),

              // Activity & Sessions History Table
              _buildSessionHistorySection(theme, colors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAppHeader(
    ThemeData theme,
    AppThemeColors colors,
    Color appColor,
    IconData appIcon,
  ) {
    final limit = _analytics?.limit;
    final hasLimit = limit != null;
    final isExceeded = _analytics?.isLimitReached ?? false;
    final remaining = _analytics?.remainingAllowance;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: appColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(appIcon, color: appColor, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.appName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _buildLimitBadge(hasLimit, limit, isExceeded, remaining, colors),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.exePath != null && widget.exePath!.isNotEmpty
                      ? widget.exePath!
                      : 'Windows desktop application',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colors.primaryAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(hasLimit ? LucideIcons.pencil : LucideIcons.plus, size: 16),
            label: Text(hasLimit ? 'Edit Limit' : 'Set Daily Limit'),
            onPressed: _openLimitDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildLimitBadge(
    bool hasLimit,
    AppLimit? limit,
    bool isExceeded,
    Duration? remaining,
    AppThemeColors colors,
  ) {
    if (!hasLimit) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'No limit set',
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
      );
    }

    if (!limit!.isEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Limit disabled',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );
    }

    if (isExceeded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Limit reached today',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primaryAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Daily limit: ${_formatDuration(limit.limitDuration)}${remaining != null ? ' (${_formatDuration(remaining)} left)' : ''}',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.primaryAccent),
      ),
    );
  }

  Widget _buildMetricCards(
    ThemeData theme,
    AppThemeColors colors,
    Color appColor,
  ) {
    final analytics = _analytics;
    final total = analytics?.totalUsage ?? Duration.zero;
    final sessions = analytics?.sessionCount ?? 0;
    final dailyAvg = analytics?.dailyAverage ?? Duration.zero;
    final limit = analytics?.limit;

    final limitStatusStr = limit != null
        ? (limit.isEnabled
            ? (analytics?.isLimitReached == true
                ? 'Limit Reached'
                : '${_formatDuration(analytics?.remainingAllowance ?? Duration.zero)} left')
            : 'Disabled')
        : 'Not configured';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final cards = [
          _buildStatCard(
            colors: colors,
            icon: LucideIcons.clock,
            iconColor: appColor,
            title: 'Total Usage (${_selection.formattedDisplayLabel})',
            value: _formatDuration(total),
            subtitle: '${_selection.daysCount} calendar day${_selection.daysCount > 1 ? 's' : ''}',
          ),
          _buildStatCard(
            colors: colors,
            icon: LucideIcons.playCircle,
            iconColor: Colors.deepPurpleAccent,
            title: 'Recorded Sessions',
            value: '$sessions',
            subtitle: 'Sessions in selected period',
          ),
          _buildStatCard(
            colors: colors,
            icon: LucideIcons.calendar,
            iconColor: colors.greenAccent,
            title: 'Daily Average',
            value: _formatDuration(dailyAvg),
            subtitle: 'Average per calendar day',
          ),
          _buildStatCard(
            colors: colors,
            icon: LucideIcons.shieldAlert,
            iconColor: limit != null && (analytics?.isLimitReached ?? false)
                ? Colors.redAccent
                : colors.primaryAccent,
            title: 'Current Daily Limit',
            value: limit != null ? _formatDuration(limit.limitDuration) : 'None',
            subtitle: limitStatusStr,
          ),
        ];

        if (isWide) {
          return Row(
            children: cards
                .map((c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: c,
                      ),
                    ))
                .toList(),
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildStatCard({
    required AppThemeColors colors,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLimitManagementSection(ThemeData theme, AppThemeColors colors) {
    final limit = _analytics?.limit;
    final hasLimit = limit != null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.shieldCheck, size: 20, color: colors.primaryAccent),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Daily Limit Configuration',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (hasLimit)
                IconButton(
                  icon: const Icon(LucideIcons.trash2, size: 18),
                  tooltip: 'Delete Limit',
                  color: Colors.redAccent.withValues(alpha: 0.8),
                  onPressed: _deleteLimit,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasLimit) ...[
            Text(
              'No daily limit is currently configured for ${widget.appName}. Setting a limit helps you stay mindful of your digital wellbeing.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.primaryAccent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Add Daily Limit'),
              onPressed: _openLimitDialog,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Allowance: ${_formatDuration(limit.limitDuration)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Warning alert at ${limit.warningThresholdPercentage}% (${_formatDuration(limit.warningDuration)}) • ${limit.isEnforced ? 'Auto-closes at limit' : 'Notifications only'}',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(
                      limit.isEnabled ? 'Enabled' : 'Disabled',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: limit.isEnabled ? colors.primaryAccent : colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: limit.isEnabled,
                      activeThumbColor: colors.primaryAccent,
                      onChanged: (val) async {
                        if (_limitsService != null && limit.id != null) {
                          await _limitsService!.toggleLimit(limit.id!, val);
                          _loadAnalytics(isBackground: true);
                        }
                      },
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(LucideIcons.pencil, size: 16),
                      tooltip: 'Edit Limit Settings',
                      onPressed: _openLimitDialog,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionHistorySection(ThemeData theme, AppThemeColors colors) {
    final sessions = _analytics?.sessions ?? const [];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Activity & Session History',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '${sessions.length} session${sessions.length == 1 ? '' : 's'}',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.calendarX,
                      size: 32,
                      color: colors.textSecondary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No recorded sessions for this application in the selected period.',
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
              itemCount: sessions.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 0.5,
                color: colors.surfaceSecondary,
              ),
              itemBuilder: (context, index) {
                final s = sessions[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: colors.surfaceSecondary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          LucideIcons.clock,
                          size: 15,
                          color: colors.primaryAccent,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE, MMM d, yyyy').format(s.startTime),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${DateFormat('h:mm:ss a').format(s.startTime)} – ${DateFormat('h:mm:ss a').format(s.endTime)}',
                              style: TextStyle(color: colors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDuration(s.duration),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(AppThemeColors colors) {
    return Container(
      height: 300,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2, color: colors.primaryAccent),
          const SizedBox(height: AppSpacing.md),
          Text('Loading application analytics...', style: TextStyle(color: colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildErrorState(AppThemeColors colors) {
    return Container(
      height: 240,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertCircle, size: 36, color: Colors.redAccent),
          const SizedBox(height: AppSpacing.sm),
          Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: () => _loadAnalytics(),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLimitDialog() async {
    if (_limitsService == null) return;
    await showAddOrEditLimitDialog(
      context,
      _limitsService!,
      existingLimit: _analytics?.limit,
      preselectedAppName: widget.appName,
      preselectedExePath: widget.exePath,
    );
    _loadAnalytics(isBackground: true);
  }

  Future<void> _deleteLimit() async {
    if (_limitsService == null || _analytics?.limit == null) return;
    final deleted = await confirmDeleteLimitDialog(
      context,
      _limitsService!,
      _analytics!.limit!,
    );
    if (deleted) {
      _loadAnalytics(isBackground: true);
    }
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
