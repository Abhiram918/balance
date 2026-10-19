import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/models/app_limit.dart';
import '../../core/models/discovered_app.dart';
import '../../core/services/limits_service.dart';
import '../../core/widgets/page_header.dart';

class LimitsScreen extends StatelessWidget {
  const LimitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final limitsService = LimitsProvider.of(context);

    final allLimits = limitsService.limits;
    final enabledCount = limitsService.enabledLimits.length;
    final exceededCount = allLimits.where((l) => l.isEnabled && limitsService.isLimitExceeded(l)).length;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: PageHeader(
                    title: 'App Limits',
                    subtitle: 'Set daily allowances for your applications and stay balanced.',
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddOrEditLimitDialog(context, limitsService),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Add Limit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primaryAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Summary Stats Cards
            if (allLimits.isNotEmpty) ...[
              _buildSummaryHeader(context, colors, allLimits.length, enabledCount, exceededCount),
              const SizedBox(height: AppSpacing.xl),
            ],

            // Main Content: List or Empty State
            if (allLimits.isEmpty)
              _buildEmptyState(context, colors, limitsService)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configured Limits',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...allLimits.map((limit) => _buildLimitCard(context, colors, limitsService, limit)),
                ],
              ),

            const SizedBox(height: AppSpacing.xxl),
            _buildWindowsLimitationNote(context, colors),
          ],
        ),
      ),
    );
  }

  /// Summary banner showing count of active and exceeded limits.
  Widget _buildSummaryHeader(
    BuildContext context,
    AppThemeColors colors,
    int total,
    int enabled,
    int exceeded,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceSecondary),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryMetric(
              context,
              colors,
              icon: LucideIcons.layers,
              title: 'Total Limits',
              value: '$total',
              color: colors.primaryAccent,
            ),
          ),
          Container(width: 1, height: 48, color: colors.surfaceSecondary),
          Expanded(
            child: _buildSummaryMetric(
              context,
              colors,
              icon: LucideIcons.checkCircle2,
              title: 'Active Today',
              value: '$enabled',
              color: colors.greenAccent,
            ),
          ),
          Container(width: 1, height: 48, color: colors.surfaceSecondary),
          Expanded(
            child: _buildSummaryMetric(
              context,
              colors,
              icon: LucideIcons.alertTriangle,
              title: 'Limits Reached',
              value: '$exceeded',
              color: exceeded > 0 ? Colors.redAccent : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(
    BuildContext context,
    AppThemeColors colors, {
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Individual card for a configured limit.
  Widget _buildLimitCard(
    BuildContext context,
    AppThemeColors colors,
    LimitsService service,
    AppLimit limit,
  ) {
    final theme = Theme.of(context);
    final used = service.getUsageForApp(limit.appName);
    final isExceeded = service.isLimitExceeded(limit);
    final isNear = service.isNearLimit(limit);
    final progress = service.getProgress(limit);
    final remaining = service.getRemainingAllowance(limit);

    // Color coordination based on threshold
    final Color statusColor;
    if (!limit.isEnabled) {
      statusColor = colors.textSecondary.withValues(alpha: 0.5);
    } else if (isExceeded) {
      statusColor = Colors.redAccent;
    } else if (isNear) {
      statusColor = Colors.amber.shade700;
    } else {
      statusColor = colors.primaryAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExceeded && limit.isEnabled
              ? Colors.redAccent.withValues(alpha: 0.4)
              : colors.surfaceSecondary,
          width: isExceeded && limit.isEnabled ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Application Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getAppIcon(limit.appName),
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            limit.appName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _buildStatusBadge(limit, isExceeded, isNear, remaining, colors),
                        if (limit.isEnforced) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.deepPurpleAccent.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.shieldAlert, size: 11, color: Colors.deepPurpleAccent),
                                SizedBox(width: 4),
                                Text(
                                  'Enforced',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepPurpleAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (limit.limitDuration > Duration.zero)
                          Text(
                            'Warning at ${limit.warningThresholdPercentage}% (${_formatDuration(limit.warningDuration)})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          )
                        else
                          Text(
                            'Blocked all day (0m allowance)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: limit.isEnabled ? Colors.redAccent : colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '•',
                          style: TextStyle(color: colors.textSecondary, fontSize: 10),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            limit.isEnforced ? 'Closes app at limit' : 'Notifications only',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: limit.isEnforced ? Colors.deepPurpleAccent : colors.textSecondary,
                              fontSize: 11,
                              fontWeight: limit.isEnforced ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Controls: Enable Switch, Edit, Delete
              Switch(
                value: limit.isEnabled,
                activeThumbColor: colors.primaryAccent,
                onChanged: (val) => service.toggleLimit(limit.id!, val),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                icon: const Icon(LucideIcons.pencil, size: 18),
                tooltip: 'Edit Limit',
                color: colors.textSecondary,
                onPressed: () => _showAddOrEditLimitDialog(context, service, existingLimit: limit),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 18),
                tooltip: 'Delete Limit',
                color: Colors.redAccent.withValues(alpha: 0.8),
                onPressed: () => _confirmDeleteLimit(context, service, limit),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: limit.isEnabled ? progress : 0.0,
              minHeight: 8,
              backgroundColor: colors.surfaceSecondary,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Usage & Allowance footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Used: ${_formatDuration(used)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: limit.isEnabled ? colors.textPrimary : colors.textSecondary,
                ),
              ),
              Text(
                'Daily Allowance: ${_formatDuration(limit.limitDuration)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
    AppLimit limit,
    bool isExceeded,
    bool isNear,
    Duration remaining,
    AppThemeColors colors,
  ) {
    if (!limit.isEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('Disabled', style: TextStyle(fontSize: 11, color: Colors.grey)),
      );
    }
    if (isExceeded) {
      final isZeroAllowance = limit.limitDuration <= Duration.zero;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isZeroAllowance ? 'Blocked All Day' : 'Limit Reached',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
      );
    }
    if (isNear) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '${_formatDuration(remaining)} left',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${_formatDuration(remaining)} left',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.primaryAccent),
      ),
    );
  }

  /// Empty state when no limits are configured.
  Widget _buildEmptyState(
    BuildContext context,
    AppThemeColors colors,
    LimitsService limitsService,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.primaryAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.shieldCheck, size: 48, color: colors.primaryAccent),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No app limits configured',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'Set daily usage allowances on applications Balance tracks to receive timely reminders and keep your screen time balanced.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: () => _showAddOrEditLimitDialog(context, limitsService),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Set Your First Limit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Explicit Windows platform limitation disclosure card.
  Widget _buildWindowsLimitationNote(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceSecondary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 18, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Operating System Notice: Balance monitors foreground app usage and sends native Windows warnings and limit-reached notifications to help you stay mindful. In accordance with system safety, Balance does not forcibly terminate, suspend, or block external applications.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Delete confirmation dialog.
  Future<void> _confirmDeleteLimit(
    BuildContext context,
    LimitsService service,
    AppLimit limit,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Delete limit for ${limit.appName}?'),
          content: Text(
            'Are you sure you want to delete this limit? Your recorded application usage history will not be affected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete Limit'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && limit.id != null) {
      await service.deleteLimit(limit.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Limit for "${limit.appName}" deleted.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Add or Edit Limit Dialog.
  Future<void> _showAddOrEditLimitDialog(
    BuildContext context,
    LimitsService service, {
    AppLimit? existingLimit,
  }) async {
    List<DiscoveredApp> discoveredApps = [];
    try {
      discoveredApps = await service.getDiscoveredApplications();
    } catch (e) {
      debugPrint('Failed to load discovered applications: $e');
    }

    if (!context.mounted) return;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => _LimitDialog(
          service: service,
          discoveredApps: discoveredApps,
          existingLimit: existingLimit,
        ),
      );
    } catch (e) {
      debugPrint('Failed to open limit dialog: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open limit dialog: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${mins}m';
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
        lower.contains('pycharm') ||
        lower.contains('idea') ||
        lower.contains('git') ||
        lower.contains('notepad++') ||
        lower.contains('terminal')) {
      return LucideIcons.code;
    }
    if (lower.contains('discord') ||
        lower.contains('slack') ||
        lower.contains('teams') ||
        lower.contains('telegram') ||
        lower.contains('whatsapp') ||
        lower.contains('chat') ||
        lower.contains('message')) {
      return LucideIcons.messageSquare;
    }
    if (lower.contains('spotify') || lower.contains('music') || lower.contains('audio')) {
      return LucideIcons.music;
    }
    if (lower.contains('vlc') ||
        lower.contains('video') ||
        lower.contains('media') ||
        lower.contains('player') ||
        lower.contains('youtube') ||
        lower.contains('netflix')) {
      return LucideIcons.playCircle;
    }
    if (lower.contains('game') || lower.contains('steam') || lower.contains('epic')) {
      return LucideIcons.gamepad2;
    }
    if (lower.contains('word') ||
        lower.contains('excel') ||
        lower.contains('powerpoint') ||
        lower.contains('office') ||
        lower.contains('note') ||
        lower.contains('onenote') ||
        lower.contains('outlook') ||
        lower.contains('access') ||
        lower.contains('document')) {
      return LucideIcons.fileText;
    }
    if (lower.contains('figma') ||
        lower.contains('design') ||
        lower.contains('paint') ||
        lower.contains('draw') ||
        lower.contains('capcut') ||
        lower.contains('photo')) {
      return LucideIcons.palette;
    }
    if (lower.contains('docker') ||
        lower.contains('postman') ||
        lower.contains('compass') ||
        lower.contains('mysql') ||
        lower.contains('tool') ||
        lower.contains('powertoys') ||
        lower.contains('winrar') ||
        lower.contains('snipping')) {
      return LucideIcons.wrench;
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
    if (lower.contains('powerpoint')) return Colors.orange.shade800;
    if (lower.contains('code') || lower.contains('studio')) return Colors.indigoAccent;
    if (lower.contains('spotify')) return Colors.greenAccent.shade700;
    if (lower.contains('steam')) return Colors.blueGrey;
    if (lower.contains('figma')) return Colors.pinkAccent;
    return const Color(0xFF6366F1);
  }
}

enum _PickerFilterTab { all, installed, tracked }

/// Dialog for creating or editing an app limit with an interactive, searchable Windows application picker.
class _LimitDialog extends StatefulWidget {
  final LimitsService service;
  final List<DiscoveredApp>? discoveredApps;
  final AppLimit? existingLimit;

  const _LimitDialog({
    required this.service,
    this.discoveredApps,
    this.existingLimit,
  });

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late TextEditingController _customAppController;
  late TextEditingController _customExeController;
  late TextEditingController _searchController;

  List<DiscoveredApp> _allApps = [];
  DiscoveredApp? _selectedApp;
  _PickerFilterTab _filterTab = _PickerFilterTab.all;
  String _searchQuery = '';
  bool _isManualEntry = false;
  bool _isScanning = false;
  String? _scanError;

  late int _hours;
  late int _minutes;
  late int _warningPercentage;
  late bool _isEnforced;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _customAppController = TextEditingController();
    _customExeController = TextEditingController();
    _searchController = TextEditingController();

    // Initialize applications list
    if (widget.discoveredApps != null && widget.discoveredApps!.isNotEmpty) {
      _allApps = List.from(widget.discoveredApps!);
    }

    final existing = widget.existingLimit;
    if (existing != null) {
      _hours = existing.limitDuration.inHours;
      _minutes = existing.limitDuration.inMinutes % 60;
      _warningPercentage = existing.warningThresholdPercentage;
      _isEnforced = existing.isEnforced;
      _customAppController.text = existing.appName;
      if (existing.exePath != null) {
        _customExeController.text = existing.exePath!;
      }

      // Find matching discovered app if available
      final match = _allApps.where((a) =>
          a.displayName.toLowerCase() == existing.appName.toLowerCase() ||
          (existing.exePath != null && a.executablePath?.toLowerCase() == existing.exePath!.toLowerCase()));
      if (match.isNotEmpty) {
        _selectedApp = match.first;
      } else {
        _selectedApp = DiscoveredApp(
          id: existing.appName.toLowerCase(),
          displayName: existing.appName,
          executablePath: existing.exePath,
          source: AppDiscoverySource.custom,
        );
      }
    } else {
      _hours = 1;
      _minutes = 0;
      _warningPercentage = 80;
      _isEnforced = false;

      if (_allApps.isNotEmpty) {
        _selectedApp = _allApps.first;
      } else {
        _isManualEntry = true;
      }
    }

    // If initial apps was empty and we're not in test mode, trigger scan
    if (_allApps.isEmpty && widget.existingLimit == null) {
      _scanApplications();
    }
  }

  @override
  void dispose() {
    _customAppController.dispose();
    _customExeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanApplications() async {
    setState(() {
      _isScanning = true;
      _scanError = null;
    });

    try {
      final apps = await widget.service.getDiscoveredApplications(forceRefresh: true);
      if (mounted) {
        setState(() {
          _allApps = apps;
          _isScanning = false;
          if (_selectedApp == null && apps.isNotEmpty) {
            _selectedApp = apps.first;
            if (_customAppController.text.isEmpty) {
              _isManualEntry = false;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanError = 'Failed to scan applications: $e';
        });
      }
    }
  }

  List<DiscoveredApp> get _filteredApps {
    var list = _allApps;

    // Apply tab filter
    if (_filterTab == _PickerFilterTab.installed) {
      list = list.where((a) => a.source != AppDiscoverySource.historicalTracked || a.hasExecutablePath).toList();
    } else if (_filterTab == _PickerFilterTab.tracked) {
      list = list.where((a) => a.isPreviouslyTracked).toList();
    }

    // Apply text search filter
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((app) {
        final nameMatch = app.displayName.toLowerCase().contains(query);
        final exeMatch = app.executableName?.toLowerCase().contains(query) ?? false;
        final pathMatch = app.executablePath?.toLowerCase().contains(query) ?? false;
        return nameMatch || exeMatch || pathMatch;
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    final isEditing = widget.existingLimit != null;

    final presets = const [
      Duration.zero,
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 45),
      Duration(hours: 1),
      Duration(hours: 1, minutes: 30),
      Duration(hours: 2),
      Duration(hours: 3),
    ];

    return AlertDialog(
      title: Text(isEditing ? 'Edit App Limit' : 'Set App Limit'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Target application selection
              _buildTargetAppSection(context, colors, isEditing),
              const SizedBox(height: AppSpacing.lg),

              // Daily allowance section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Allowance',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      _hours == 0 && _minutes == 0 ? '0m (Blocked all day)' : '${_hours}h ${_minutes}m',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _hours == 0 && _minutes == 0 ? Colors.redAccent : colors.primaryAccent,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Presets chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((preset) {
                  final pHours = preset.inHours;
                  final pMins = preset.inMinutes % 60;
                  final isSelected = _hours == pHours && _minutes == pMins;
                  final label = preset == Duration.zero
                      ? '0m (Blocked)'
                      : (pHours > 0 && pMins > 0
                          ? '${pHours}h ${pMins}m'
                          : (pHours > 0 ? '${pHours}h' : '${pMins}m'));

                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    selectedColor: colors.primaryAccent.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: isSelected ? colors.primaryAccent : Colors.transparent,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _hours = pHours;
                        _minutes = pMins;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.md),

              // Custom hours/minutes sliders
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hours: $_hours', style: theme.textTheme.bodySmall),
                        Slider(
                          value: _hours.toDouble(),
                          min: 0,
                          max: 12,
                          divisions: 12,
                          activeColor: colors.primaryAccent,
                          onChanged: (v) => setState(() => _hours = v.toInt()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Minutes: $_minutes', style: theme.textTheme.bodySmall),
                        Slider(
                          value: _minutes.toDouble(),
                          min: 0,
                          max: 55,
                          divisions: 11,
                          activeColor: colors.primaryAccent,
                          onChanged: (v) => setState(() => _minutes = v.toInt()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_hours == 0 && _minutes == 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '0 minutes allowance: The application is restricted all day and blocked immediately when launched.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              if (_hours > 0 || _minutes > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Warning Notification Threshold',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '$_warningPercentage%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.primaryAccent,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _warningPercentage.toDouble(),
                  min: 50,
                  max: 95,
                  divisions: 9,
                  label: '$_warningPercentage%',
                  activeColor: colors.primaryAccent,
                  onChanged: (v) => setState(() => _warningPercentage = v.toInt()),
                ),
                Text(
                  'Receive an early alert when you hit $_warningPercentage% of your allowance.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ] else ...[
                Text(
                  'Early warning is not applicable for a 0-minute allowance (the app is blocked immediately).',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              // Enforcement Setting Section
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isEnforced
                        ? Colors.deepPurpleAccent.withValues(alpha: 0.5)
                        : colors.surfaceSecondary,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isEnforced ? LucideIcons.shieldAlert : LucideIcons.shield,
                              size: 18,
                              color: _isEnforced ? Colors.deepPurpleAccent : colors.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'Enforce Limit',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _isEnforced,
                          activeThumbColor: Colors.deepPurpleAccent,
                          onChanged: (val) => setState(() => _isEnforced = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Automatically close this application when the daily allowance is reached and prevent it from staying open today.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (_isEnforced) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2B2218) : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFFD97706).withValues(alpha: 0.5)
                                : const Color(0xFFFCD34D),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.alertTriangle,
                                  size: 16,
                                  color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Possible Unsaved Work Loss',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'At the daily limit, Balance will request this application to close gracefully, and terminate it if it remains open. Please save your work regularly.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: colors.textPrimary.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (_errorText != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.alertCircle, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.primaryAccent),
          onPressed: _saveLimit,
          child: Text(isEditing ? 'Save Changes' : 'Create Limit'),
        ),
      ],
    );
  }

  Widget _buildTargetAppSection(BuildContext context, AppThemeColors colors, bool isEditing) {
    final theme = Theme.of(context);

    if (isEditing) {
      final appName = widget.existingLimit!.appName;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Target Application', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceSecondary),
            ),
            child: Row(
              children: [
                _buildAppIconWidget(appName, null),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (widget.existingLimit!.exePath != null)
                        Text(
                          widget.existingLimit!.exePath!,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Creating limit
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Target Application', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Row(
              children: [
                IconButton(
                  icon: _isScanning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 15),
                  tooltip: 'Rescan Windows Applications',
                  onPressed: _isScanning ? null : _scanApplications,
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isManualEntry = !_isManualEntry;
                      if (_isManualEntry && _selectedApp != null) {
                        _customAppController.text = _selectedApp!.displayName;
                        _customExeController.text = _selectedApp!.executablePath ?? '';
                      }
                    });
                  },
                  child: Text(
                    _isManualEntry ? 'Pick from apps' : 'Enter manually',
                    style: TextStyle(fontSize: 12, color: colors.primaryAccent),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        if (_isManualEntry) ...[
          // Manual input fields
          TextField(
            controller: _customAppController,
            decoration: InputDecoration(
              labelText: 'Application Name',
              hintText: 'e.g. Google Chrome, Telegram, Spotify',
              filled: true,
              fillColor: colors.surfaceSecondary,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _customExeController,
            decoration: InputDecoration(
              labelText: 'Executable Path or Name (Optional)',
              hintText: 'e.g. C:\\Program Files\\...\\app.exe or app.exe',
              filled: true,
              fillColor: colors.surfaceSecondary,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ] else ...[
          // Interactive Searchable Picker
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search applications by name or .exe...',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colors.surfaceSecondary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // Filter pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All (${_allApps.length})', _PickerFilterTab.all, colors),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'Installed (${_allApps.where((a) => a.source != AppDiscoverySource.historicalTracked || a.hasExecutablePath).length})',
                  _PickerFilterTab.installed,
                  colors,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'Previously Tracked (${_allApps.where((a) => a.isPreviouslyTracked).length})',
                  _PickerFilterTab.tracked,
                  colors,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // Scrollable Application List
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceSecondary),
            ),
            child: _buildAppListContent(context, colors),
          ),
        ],
      ],
    );
  }

  Widget _buildFilterChip(String label, _PickerFilterTab tab, AppThemeColors colors) {
    final isSelected = _filterTab == tab;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _filterTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryAccent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colors.primaryAccent : colors.surfaceSecondary,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? colors.primaryAccent : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildAppListContent(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);

    if (_isScanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Scanning Windows applications...',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_scanError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle, size: 28, color: Colors.amber),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _scanError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              TextButton(
                onPressed: _scanApplications,
                child: const Text('Retry Scan'),
              ),
            ],
          ),
        ),
      );
    }

    final apps = _filteredApps;
    if (apps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.searchX, size: 28, color: colors.textSecondary.withValues(alpha: 0.6)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _searchQuery.isNotEmpty ? 'No applications match "$_searchQuery"' : 'No applications available',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isManualEntry = true;
                      _customAppController.text = _searchQuery.trim();
                    });
                  },
                  icon: const Icon(LucideIcons.plus, size: 14),
                  label: Text('Use "$_searchQuery" manually', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: apps.length,
      separatorBuilder: (context, index) => Divider(height: 1, thickness: 0.5, color: colors.surfaceSecondary),
      itemBuilder: (context, index) {
        final app = apps[index];
        final isSelected = _selectedApp?.id == app.id;

        return InkWell(
          onTap: () {
            setState(() {
              _selectedApp = app;
              _errorText = null;
            });
          },
          child: Container(
            color: isSelected ? colors.primaryAccent.withValues(alpha: 0.12) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _buildAppIconWidget(app.displayName, app.iconPath),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              app.displayName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? colors.primaryAccent : colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (app.isPreviouslyTracked) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.greenAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Tracked',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: colors.greenAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (app.executableName != null || app.executablePath != null)
                        Text(
                          app.executableName ?? app.executablePath!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: colors.textSecondary.withValues(alpha: 0.8),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(LucideIcons.check, size: 18, color: colors.primaryAccent),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppIconWidget(String appName, String? iconPath) {
    if (iconPath != null && iconPath.isNotEmpty && File(iconPath).existsSync()) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(iconPath),
            width: 28,
            height: 28,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildFallbackVectorIcon(appName),
          ),
        );
      } catch (_) {}
    }
    return _buildFallbackVectorIcon(appName);
  }

  Widget _buildFallbackVectorIcon(String appName) {
    final color = LimitsScreen._getAppColor(appName);
    final icon = LimitsScreen._getAppIcon(appName);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 15, color: color),
    );
  }

  Future<void> _saveLimit() async {
    final String appName;
    final String? exePath;

    if (_isManualEntry) {
      appName = _customAppController.text.trim();
      exePath = _customExeController.text.trim().isNotEmpty ? _customExeController.text.trim() : null;
    } else {
      if (_selectedApp == null) {
        setState(() => _errorText = 'Please select an application.');
        return;
      }
      appName = _selectedApp!.displayName.trim();
      exePath = _selectedApp!.executablePath;
    }

    if (appName.isEmpty) {
      setState(() => _errorText = 'Please specify an application name.');
      return;
    }

    // Explicit Balance self-exclusion guard
    if (widget.service.discoveryService?.isExcluded(appName, exePath) == true ||
        appName.toLowerCase() == 'balance' ||
        appName.toLowerCase() == 'balance desktop' ||
        appName.toLowerCase() == 'digital wellbeing') {
      setState(() => _errorText = 'Balance itself cannot be set as a limit target.');
      return;
    }

    final totalMinutes = _hours * 60 + _minutes;
    if (totalMinutes < 0) {
      setState(() => _errorText = 'Daily allowance cannot be negative.');
      return;
    }

    final duration = Duration(minutes: totalMinutes);

    try {
      if (widget.existingLimit != null) {
        await widget.service.updateLimit(
          id: widget.existingLimit!.id!,
          duration: duration,
          warningPercentage: _warningPercentage,
          isEnforced: _isEnforced,
        );
      } else {
        await widget.service.createLimit(
          appName: appName,
          exePath: exePath,
          duration: duration,
          warningPercentage: _warningPercentage,
          isEnforced: _isEnforced,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        if (e is ArgumentError) {
          _errorText = e.message;
        } else {
          _errorText = e.toString();
        }
      });
    }
  }
}

