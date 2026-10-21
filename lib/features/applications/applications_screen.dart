import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/models/application_analytics_models.dart';
import '../../core/services/application_analytics_service.dart';
import '../../core/services/limits_service.dart';
import '../../core/services/windows_usage_tracker.dart';
import '../../core/widgets/app_limit_dialog.dart';
import '../../core/widgets/applications_date_selector.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/usage_bar_chart.dart';
import 'application_detail_screen.dart';

enum AppListFilter { all, limited, limitReached }
enum AppListSort { mostUsed, leastUsed, nameAsc }

/// Upgraded Applications screen: an application usage dashboard featuring
/// real-time date filtering, aggregate usage bar charts, search, filtering,
/// sorting, daily-limit progress, and individual application drill-downs.
class ApplicationsScreen extends StatefulWidget {
  final ApplicationAnalyticsService? analyticsService;
  final DateTime? referenceDate;
  final String? initialSelectedAppName;
  final DateTime Function()? clock;
  final Duration backgroundThrottleDuration;
  final Duration debounceDuration;
  final ValueListenable<bool>? windowVisibility;

  const ApplicationsScreen({
    super.key,
    this.analyticsService,
    this.referenceDate,
    this.initialSelectedAppName,
    this.clock,
    this.backgroundThrottleDuration = const Duration(seconds: 10),
    this.debounceDuration = const Duration(milliseconds: 250),
    this.windowVisibility,
  });

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  late DateRangeSelection _selection;
  ApplicationsAnalyticsResult? _analytics;
  bool _isLoading = true;
  String? _errorMessage;

  // Search & Filter state
  String _searchQuery = '';
  AppListFilter _activeFilter = AppListFilter.all;
  AppListSort _activeSort = AppListSort.mostUsed;
  final TextEditingController _searchController = TextEditingController();

  // Detail drill-down selection
  String? _selectedAppName;
  String? _selectedAppExePath;

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

  DateTime get _now => widget.clock != null ? widget.clock!() : DateTime.now();

  @override
  void initState() {
    super.initState();
    final now = widget.referenceDate ?? DateTime.now();
    _selection = DateRangeSelection.today(now);
    _selectedAppName = widget.initialSelectedAppName;
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
  void didUpdateWidget(ApplicationsScreen oldWidget) {
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
        _errorMessage = 'Could not access tracking service';
        _isLoading = false;
      });
      return;
    }

    _lastBackgroundLoadTime = _now;
    _loadAnalytics();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tracker?.removeListener(_onTrackerOrLimitsChanged);
    _limitsService?.removeListener(_onTrackerOrLimitsChanged);
    _visibilityListenable?.removeListener(_onVisibilityChanged);
    _searchController.dispose();
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
      final now = _now;
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
        _lastBackgroundLoadTime = _now;
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
      final result = await _resolvedService!.getApplicationsAnalytics(
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
          _errorMessage = 'Failed to load application usage: $e';
        }
      });
    }
  }

  void _onDateSelectionChanged(DateRangeSelection newSelection) {
    setState(() {
      _selection = newSelection;
    });
    _debounceTimer?.cancel();
    _lastBackgroundLoadTime = DateTime.now();
    _loadAnalytics();
  }

  List<AppItemAnalytics> get _filteredAndSortedApps {
    final list = _analytics?.applications ?? [];
    if (list.isEmpty) return const [];

    // 1. Filter
    final filtered = list.where((app) {
      // Search query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        if (!app.appName.toLowerCase().contains(q)) {
          return false;
        }
      }

      // Filter category
      switch (_activeFilter) {
        case AppListFilter.all:
          return true;
        case AppListFilter.limited:
          return app.isLimitEnabled;
        case AppListFilter.limitReached:
          if (!app.isLimitEnabled || _limitsService == null) return false;
          return _limitsService!.isLimitExceeded(app.limit!);
      }
    }).toList();

    // 2. Sort
    filtered.sort((a, b) {
      switch (_activeSort) {
        case AppListSort.mostUsed:
          final cmp = b.totalDuration.compareTo(a.totalDuration);
          if (cmp != 0) return cmp;
          return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        case AppListSort.leastUsed:
          final cmp = a.totalDuration.compareTo(b.totalDuration);
          if (cmp != 0) return cmp;
          return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        case AppListSort.nameAsc:
          return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    // If user has selected an application to inspect details, show ApplicationDetailScreen
    if (_selectedAppName != null) {
      return ApplicationDetailScreen(
        appName: _selectedAppName!,
        exePath: _selectedAppExePath,
        initialSelection: _selection,
        analyticsService: _resolvedService,
        referenceDate: widget.referenceDate,
        windowVisibility: _visibilityListenable,
        clock: widget.clock,
        onBack: () {
          setState(() {
            _selectedAppName = null;
            _selectedAppExePath = null;
          });
          _loadAnalytics(isBackground: true);
        },
      );
    }

    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Scaffold(
      backgroundColor: colors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header with Title, subtle description, and Date-range selector
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 800;
                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PageHeader(
                        title: 'Applications',
                        subtitle: 'Monitor application usage, analyze activity trends, and set daily limits.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: ApplicationsDateSelector(
                              selection: _selection,
                              onSelectionChanged: _onDateSelectionChanged,
                              referenceDate: widget.referenceDate,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton(
                            icon: const Icon(LucideIcons.refreshCw, size: 16),
                            tooltip: 'Refresh Analytics',
                            color: colors.textSecondary,
                            onPressed: () => _loadAnalytics(isBackground: false),
                          ),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: PageHeader(
                        title: 'Applications',
                        subtitle: 'Monitor application usage, analyze activity trends, and set daily limits.',
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ApplicationsDateSelector(
                          selection: _selection,
                          onSelectionChanged: _onDateSelectionChanged,
                          referenceDate: widget.referenceDate,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton(
                          icon: const Icon(LucideIcons.refreshCw, size: 16),
                          tooltip: 'Refresh Analytics',
                          color: colors.textSecondary,
                          onPressed: () => _loadAnalytics(isBackground: false),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),

            if (_isLoading && _analytics == null)
              _buildLoadingState(colors)
            else if (_errorMessage != null && _analytics == null)
              _buildErrorState(colors)
            else ...[
              // Compact Summary Section
              _buildSummarySection(theme, colors),
              const SizedBox(height: AppSpacing.xl),

              // Aggregate Usage Bar Graph
              UsageBarChart(
                bars: _analytics?.chartBars ?? const [],
                isHourly: _selection.isHourly,
                title: 'Aggregate Application Usage (${_selection.formattedDisplayLabel})',
                totalUsage: _analytics?.totalUsage ?? Duration.zero,
                barColor: colors.primaryAccent,
                height: 340,
              ),
              const SizedBox(height: AppSpacing.xl),

              // Application List Controls (Search, Filters, Sort)
              _buildListControls(theme, colors),
              const SizedBox(height: AppSpacing.md),

              // Application List
              _buildApplicationsList(theme, colors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection(ThemeData theme, AppThemeColors colors) {
    final analytics = _analytics;
    final totalDuration = analytics?.totalUsage ?? Duration.zero;
    final limitedApps = analytics?.totalLimitedApps ?? 0;
    final limitReachedApps = analytics?.totalLimitReachedApps ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 750;
        final cards = [
          _buildSummaryCard(
            colors: colors,
            icon: LucideIcons.clock,
            iconColor: colors.primaryAccent,
            title: 'Total Usage (${_selection.formattedDisplayLabel})',
            value: _formatDuration(totalDuration),
            subtitle: 'Aggregate across all applications',
          ),
          _buildSummaryCard(
            colors: colors,
            icon: LucideIcons.shieldAlert,
            iconColor: Colors.deepPurpleAccent,
            title: 'Active Daily Limits',
            value: '$limitedApps',
            subtitle: 'Applications with enabled daily limits',
          ),
          _buildSummaryCard(
            colors: colors,
            icon: LucideIcons.alertTriangle,
            iconColor: limitReachedApps > 0 ? Colors.redAccent : colors.greenAccent,
            title: 'Daily Limits Reached',
            value: '$limitReachedApps',
            subtitle: 'Reached for the current local day',
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
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: c,
                    ))
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildSummaryCard({
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
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListControls(ThemeData theme, AppThemeColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 750;

        final searchBar = TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search applications by name...',
            prefixIcon: const Icon(LucideIcons.search, size: 16),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(LucideIcons.x, size: 14),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: colors.surfaceSecondary,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        );

        final filterPills = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFilterPill('All', AppListFilter.all, colors),
            const SizedBox(width: 4),
            _buildFilterPill('Limited', AppListFilter.limited, colors),
            const SizedBox(width: 4),
            _buildFilterPill('Limit Reached', AppListFilter.limitReached, colors),
          ],
        );

        final sortDropdown = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AppListSort>(
              value: _activeSort,
              icon: const Icon(LucideIcons.chevronDown, size: 14),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
              dropdownColor: colors.surface,
              items: const [
                DropdownMenuItem(
                  value: AppListSort.mostUsed,
                  child: Text('Most Used'),
                ),
                DropdownMenuItem(
                  value: AppListSort.leastUsed,
                  child: Text('Least Used'),
                ),
                DropdownMenuItem(
                  value: AppListSort.nameAsc,
                  child: Text('Name (A–Z)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _activeSort = val);
                }
              },
            ),
          ),
        );

        if (isCompact) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.surfaceSecondary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchBar,
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    filterPills,
                    sortDropdown,
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.surfaceSecondary),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: searchBar,
              ),
              const SizedBox(width: AppSpacing.md),
              filterPills,
              const SizedBox(width: AppSpacing.md),
              sortDropdown,
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterPill(String label, AppListFilter filter, AppThemeColors colors) {
    final isSelected = _activeFilter == filter;
    return InkWell(
      key: ValueKey('filter_pill_${filter.name}'),
      onTap: () => setState(() => _activeFilter = filter),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildApplicationsList(ThemeData theme, AppThemeColors colors) {
    final apps = _filteredAndSortedApps;

    if (apps.isEmpty) {
      return _buildEmptyListState(theme, colors);
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: apps.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 0.5,
          color: colors.surfaceSecondary,
        ),
        itemBuilder: (context, index) {
          final app = apps[index];
          return _buildApplicationRow(app, theme, colors);
        },
      ),
    );
  }

  Widget _buildApplicationRow(
    AppItemAnalytics app,
    ThemeData theme,
    AppThemeColors colors,
  ) {
    final appColor = getAppColor(app.appName);
    final appIcon = getAppIcon(app.appName);
    final hasLimit = app.hasLimit && app.isLimitEnabled;
    final limit = app.limit;

    final isLimitReached = hasLimit && _limitsService != null && _limitsService!.isLimitExceeded(limit!);
    final limitProgress = hasLimit && _limitsService != null ? _limitsService!.getProgress(limit!) : 0.0;
    final remainingAllowance = hasLimit && _limitsService != null ? _limitsService!.getRemainingAllowance(limit!) : null;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedAppName = app.appName;
          _selectedAppExePath = app.exePath;
        });
      },
      borderRadius: BorderRadius.circular(16),
      hoverColor: colors.surfaceSecondary.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        child: Row(
          children: [
            // App Icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: appColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(appIcon, color: appColor, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),

            // App Name & Sessions count
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.appName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${app.sessionCount} session${app.sessionCount == 1 ? '' : 's'} recorded',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Usage Duration & Relative Progress Bar
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(app.totalDuration),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${(app.proportionalUsage * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: app.proportionalUsage,
                      minHeight: 5,
                      backgroundColor: colors.surfaceSecondary,
                      valueColor: AlwaysStoppedAnimation<Color>(appColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xl),

            // Daily Limit Status & Allowance Progress
            Expanded(
              flex: 3,
              child: hasLimit
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                isLimitReached
                                    ? 'Limit Reached'
                                    : '${_formatDuration(remainingAllowance ?? Duration.zero)} left',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isLimitReached ? Colors.redAccent : colors.primaryAccent,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Max: ${_formatDuration(limit!.limitDuration)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: limitProgress,
                            minHeight: 4,
                            backgroundColor: colors.surfaceSecondary,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isLimitReached ? Colors.redAccent : colors.primaryAccent,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'No limit',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Actions: Configure Limit Button & View Details Chevron
            IconButton(
              icon: Icon(
                hasLimit ? LucideIcons.pencil : LucideIcons.shield,
                size: 16,
              ),
              tooltip: hasLimit ? 'Edit Daily Limit' : 'Set Daily Limit',
              color: hasLimit ? colors.primaryAccent : colors.textSecondary,
              onPressed: () => _openLimitDialogForApp(app),
            ),
            IconButton(
              icon: const Icon(LucideIcons.chevronRight, size: 16),
              tooltip: 'View Application Details',
              color: colors.textSecondary,
              onPressed: () {
                setState(() {
                  _selectedAppName = app.appName;
                  _selectedAppExePath = app.exePath;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyListState(ThemeData theme, AppThemeColors colors) {
    String message = 'No tracked application usage recorded for this period.';
    if (_searchQuery.isNotEmpty) {
      message = 'No applications match "$_searchQuery".';
    } else if (_activeFilter == AppListFilter.limited) {
      message = 'No applications have active daily limits configured.';
    } else if (_activeFilter == AppListFilter.limitReached) {
      message = 'No application limits have been reached today.';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceSecondary),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _searchQuery.isNotEmpty ? LucideIcons.searchX : LucideIcons.appWindow,
              size: 40,
              color: colors.textSecondary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Text('Clear search filter'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(AppThemeColors colors) {
    return Container(
      height: 320,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2, color: colors.primaryAccent),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Aggregating application usage records...',
            style: TextStyle(color: colors.textSecondary),
          ),
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
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLimitDialogForApp(AppItemAnalytics app) async {
    if (_limitsService == null) return;
    await showAddOrEditLimitDialog(
      context,
      _limitsService!,
      existingLimit: app.limit,
      preselectedAppName: app.appName,
      preselectedExePath: app.exePath,
    );
    _debounceTimer?.cancel();
    _lastBackgroundLoadTime = DateTime.now();
    _loadAnalytics(isBackground: true);
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
