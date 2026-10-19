import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../models/app_limit.dart';
import '../models/discovered_app.dart';
import '../services/limits_service.dart';

/// Shows the Add or Edit Limit dialog with application picker and configuration controls.
Future<void> showAddOrEditLimitDialog(
  BuildContext context,
  LimitsService service, {
  AppLimit? existingLimit,
  String? preselectedAppName,
  String? preselectedExePath,
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
      builder: (ctx) => AppLimitDialog(
        service: service,
        discoveredApps: discoveredApps,
        existingLimit: existingLimit,
        preselectedAppName: preselectedAppName,
        preselectedExePath: preselectedExePath,
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

/// Delete confirmation dialog for an app limit.
Future<bool> confirmDeleteLimitDialog(
  BuildContext context,
  LimitsService service,
  AppLimit limit,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text('Delete limit for ${limit.appName}?'),
        content: const Text(
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
    return true;
  }
  return false;
}

enum PickerFilterTab { all, installed, tracked }

/// Dialog for creating or editing an app limit with an interactive, searchable Windows application picker.
class AppLimitDialog extends StatefulWidget {
  final LimitsService service;
  final List<DiscoveredApp>? discoveredApps;
  final AppLimit? existingLimit;
  final String? preselectedAppName;
  final String? preselectedExePath;

  const AppLimitDialog({
    super.key,
    required this.service,
    this.discoveredApps,
    this.existingLimit,
    this.preselectedAppName,
    this.preselectedExePath,
  });

  @override
  State<AppLimitDialog> createState() => _AppLimitDialogState();
}

class _AppLimitDialogState extends State<AppLimitDialog> {
  late TextEditingController _customAppController;
  late TextEditingController _customExeController;
  late TextEditingController _searchController;

  List<DiscoveredApp> _allApps = [];
  DiscoveredApp? _selectedApp;
  PickerFilterTab _filterTab = PickerFilterTab.all;
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

      final match = _allApps.where((a) =>
          a.displayName.toLowerCase() == existing.appName.toLowerCase() ||
          (existing.exePath != null &&
              a.executablePath?.toLowerCase() == existing.exePath!.toLowerCase()));
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

      final preselected = widget.preselectedAppName;
      if (preselected != null && preselected.trim().isNotEmpty) {
        _customAppController.text = preselected.trim();
        if (widget.preselectedExePath != null) {
          _customExeController.text = widget.preselectedExePath!;
        }
        final match = _allApps.where((a) =>
            a.displayName.toLowerCase() == preselected.trim().toLowerCase() ||
            (widget.preselectedExePath != null &&
                a.executablePath?.toLowerCase() ==
                    widget.preselectedExePath!.toLowerCase()));
        if (match.isNotEmpty) {
          _selectedApp = match.first;
        } else {
          _selectedApp = DiscoveredApp(
            id: preselected.toLowerCase(),
            displayName: preselected,
            executablePath: widget.preselectedExePath,
            source: AppDiscoverySource.custom,
          );
        }
      } else if (_allApps.isNotEmpty) {
        _selectedApp = _allApps.first;
      } else {
        _isManualEntry = true;
      }
    }

    if (_allApps.isEmpty && widget.existingLimit == null && widget.preselectedAppName == null) {
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

    switch (_filterTab) {
      case PickerFilterTab.installed:
        list = list.where((a) => a.source != AppDiscoverySource.historicalTracked).toList();
        break;
      case PickerFilterTab.tracked:
        list = list.where((a) => a.isPreviouslyTracked).toList();
        break;
      case PickerFilterTab.all:
        break;
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list.where((a) {
        final nameMatch = a.displayName.toLowerCase().contains(q);
        final exeMatch = a.executableName?.toLowerCase().contains(q) ?? false;
        final pubMatch = a.publisher?.toLowerCase().contains(q) ?? false;
        return nameMatch || exeMatch || pubMatch;
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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colors.surface,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isEditing ? 'Edit App Limit' : 'Set App Limit',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTargetAppSection(context, colors, isEditing),
              const SizedBox(height: AppSpacing.lg),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Allowance',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _hours == 0 && _minutes == 0 ? '0m (Blocked all day)' : '${_hours}h ${_minutes}m',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _hours == 0 && _minutes == 0 ? Colors.redAccent : colors.primaryAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

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
                    Text(
                      'Warning Notification Threshold',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Target Application', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isManualEntry = !_isManualEntry;
                  _errorText = null;
                });
              },
              icon: Icon(_isManualEntry ? LucideIcons.list : LucideIcons.edit3, size: 14),
              label: Text(_isManualEntry ? 'Select from list' : 'Enter manually', style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        if (_isManualEntry) ...[
          TextField(
            controller: _customAppController,
            decoration: InputDecoration(
              labelText: 'Application Name',
              hintText: 'e.g. Chrome, Visual Studio Code',
              filled: true,
              fillColor: colors.surfaceSecondary,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _customExeController,
            decoration: InputDecoration(
              labelText: 'Executable Path (optional)',
              hintText: r'e.g. C:\Program Files\App\app.exe',
              filled: true,
              fillColor: colors.surfaceSecondary,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ] else ...[
          _buildAppPickerControls(context, colors),
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: colors.surfaceSecondary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceSecondary),
            ),
            child: _buildAppPickerList(context, colors),
          ),
        ],
      ],
    );
  }

  Widget _buildAppPickerControls(BuildContext context, AppThemeColors colors) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search applications...',
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _buildFilterChip('All', PickerFilterTab.all, colors),
                const SizedBox(width: 4),
                _buildFilterChip('Installed', PickerFilterTab.installed, colors),
                const SizedBox(width: 4),
                _buildFilterChip('Tracked', PickerFilterTab.tracked, colors),
              ],
            ),
            if (_isScanning)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                tooltip: 'Refresh installed applications',
                onPressed: _scanApplications,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, PickerFilterTab tab, AppThemeColors colors) {
    final isSelected = _filterTab == tab;
    return InkWell(
      onTap: () => setState(() => _filterTab = tab),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
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

  Widget _buildAppPickerList(BuildContext context, AppThemeColors colors) {
    final theme = Theme.of(context);
    final apps = _filteredApps;

    if (_isScanning && apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: AppSpacing.sm),
            Text('Scanning installed applications...', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    if (apps.isEmpty) {
      if (_scanError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _scanError!,
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.searchX, size: 28, color: colors.textSecondary.withValues(alpha: 0.4)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _searchQuery.isNotEmpty ? 'No applications match "$_searchQuery"' : 'No applications found',
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
                          app.executableName ?? app.executablePath ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(LucideIcons.check, size: 16, color: colors.primaryAccent),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppIconWidget(String appName, String? iconPath) {
    if (iconPath != null && iconPath.isNotEmpty && File(iconPath).existsSync()) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(iconPath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildFallbackAppIcon(appName),
          ),
        ),
      );
    }
    return _buildFallbackAppIcon(appName);
  }

  Widget _buildFallbackAppIcon(String appName) {
    final icon = getAppIcon(appName);
    final color = getAppColor(appName);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
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

/// Helper returning standard Lucide icon based on application name.
IconData getAppIcon(String appName) {
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

/// Helper returning thematic brand color based on application name.
Color getAppColor(String appName) {
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
