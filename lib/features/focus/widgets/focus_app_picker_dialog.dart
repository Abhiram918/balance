import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/models/discovered_app.dart';
import '../../../core/models/focus_preset.dart';
import '../../../core/services/windows_app_discovery_service.dart';

enum _PickerFilterTab { all, installed, tracked }

/// Interactive, searchable modal dialog allowing users to pick applications
/// to block for a Focus preset.
class FocusAppPickerDialog extends StatefulWidget {
  final WindowsAppDiscoveryService discoveryService;
  final List<FocusPresetBlockedApp> initialBlockedApps;

  const FocusAppPickerDialog({
    super.key,
    required this.discoveryService,
    required this.initialBlockedApps,
  });

  /// Protected process and shell components that must NEVER be selected.
  static const Set<String> protectedExeNames = {
    'explorer.exe',
    'shellexperiencehost.exe',
    'sihost.exe',
    'shellhost.exe',
    'searchhost.exe',
    'searchapp.exe',
    'searchui.exe',
    'searchindexer.exe',
    'startmenuexperiencehost.exe',
    'dwm.exe',
    'csrss.exe',
    'smss.exe',
    'lsass.exe',
    'services.exe',
    'wininit.exe',
    'winlogon.exe',
    'svchost.exe',
    'system',
    'taskmgr.exe',
    'taskhostw.exe',
    'taskhost.exe',
    'cmd.exe',
    'powershell.exe',
    'pwsh.exe',
    'conhost.exe',
    'ctfmon.exe',
    'fontdrvhost.exe',
    'rundll32.exe',
    'dllhost.exe',
    'appverif.exe',
    'msiexec.exe',
    'balance.exe',
    'digital_wellbeing.exe',
    'flutter_tester.exe',
  };

  static const Set<String> protectedAppNames = {
    'balance',
    'digital wellbeing',
    'windows explorer',
    'task manager',
    'system',
  };

  static bool isProtectedApp(String name, String? exe) {
    final lowerName = name.trim().toLowerCase();
    if (protectedAppNames.contains(lowerName)) return true;
    if (exe != null && exe.trim().isNotEmpty) {
      final fileName = exe.split(RegExp(r'[\\/]')).last.trim().toLowerCase();
      if (protectedExeNames.contains(fileName)) return true;
    }
    return false;
  }

  @override
  State<FocusAppPickerDialog> createState() => _FocusAppPickerDialogState();
}

class _FocusAppPickerDialogState extends State<FocusAppPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _manualNameController = TextEditingController();
  final TextEditingController _manualExeController = TextEditingController();

  List<DiscoveredApp> _allApps = [];
  final Map<String, FocusPresetBlockedApp> _selectedApps = {};
  _PickerFilterTab _filterTab = _PickerFilterTab.all;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _errorMessage;
  bool _isManualEntry = false;
  String? _manualInputError;

  @override
  void initState() {
    super.initState();
    for (final app in widget.initialBlockedApps) {
      _selectedApps[app.appName.trim().toLowerCase()] = app;
    }
    _loadApplications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualNameController.dispose();
    _manualExeController.dispose();
    super.dispose();
  }

  Future<void> _loadApplications({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apps = await widget.discoveryService.discoverApplications(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _allApps = apps;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to discover applications: $e';
      });
    }
  }

  List<DiscoveredApp> get _filteredApps {
    var list = _allApps;

    if (_filterTab == _PickerFilterTab.installed) {
      list = list.where((a) => a.source != AppDiscoverySource.historicalTracked || a.hasExecutablePath).toList();
    } else if (_filterTab == _PickerFilterTab.tracked) {
      list = list.where((a) => a.isPreviouslyTracked).toList();
    }

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

  void _toggleApp(DiscoveredApp app) {
    if (FocusAppPickerDialog.isProtectedApp(app.displayName, app.executablePath ?? app.executableName)) {
      return;
    }

    final key = app.displayName.trim().toLowerCase();
    setState(() {
      if (_selectedApps.containsKey(key)) {
        _selectedApps.remove(key);
      } else {
        _selectedApps[key] = FocusPresetBlockedApp(
          appName: app.displayName.trim(),
          exePath: app.executablePath?.trim() ?? (app.executableName?.trim().isNotEmpty == true ? app.executableName!.trim() : null),
        );
      }
    });
  }

  void _addManualApp() {
    final name = _manualNameController.text.trim();
    final exe = _manualExeController.text.trim();

    if (name.isEmpty) {
      setState(() => _manualInputError = 'Application name cannot be empty.');
      return;
    }

    if (FocusAppPickerDialog.isProtectedApp(name, exe.isNotEmpty ? exe : null)) {
      setState(() => _manualInputError = 'Protected Windows apps and Balance cannot be blocked.');
      return;
    }

    final key = name.toLowerCase();
    setState(() {
      _selectedApps[key] = FocusPresetBlockedApp(
        appName: name,
        exePath: exe.isNotEmpty ? exe : null,
      );
      _manualNameController.clear();
      _manualExeController.clear();
      _manualInputError = null;
      _isManualEntry = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(LucideIcons.shieldAlert, size: 22, color: colors.primaryAccent),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Select Applications to Block',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          IconButton(
            icon: _isLoading
                ? const Icon(LucideIcons.loader2, size: 16)
                : const Icon(LucideIcons.refreshCw, size: 16),
            tooltip: 'Rescan Installed Applications',
            onPressed: _isLoading ? null : () => _loadApplications(forceRefresh: true),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose applications that will be restricted while this focus preset is running.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),

            // Search bar & Manual entry toggle
            Row(
              children: [
                Expanded(
                  child: TextField(
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () => setState(() => _isManualEntry = !_isManualEntry),
                  icon: Icon(_isManualEntry ? LucideIcons.list : LucideIcons.plus, size: 16),
                  label: Text(_isManualEntry ? 'Browse' : 'Manual'),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primaryAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            if (_isManualEntry) ...[
              // Manual app entry fields
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Custom Application',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextField(
                      controller: _manualNameController,
                      decoration: InputDecoration(
                        labelText: 'Application Name *',
                        hintText: 'e.g. Steam, Discord, Spotify',
                        filled: true,
                        fillColor: colors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _manualExeController,
                      decoration: InputDecoration(
                        labelText: 'Executable Name or Path (Optional)',
                        hintText: 'e.g. steam.exe or C:\\...\\steam.exe',
                        filled: true,
                        fillColor: colors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    if (_manualInputError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _manualInputError!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _addManualApp,
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text('Add to Block List'),
                        style: FilledButton.styleFrom(backgroundColor: colors.primaryAccent),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Filter tabs
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
              const SizedBox(height: AppSpacing.sm),

              // Application list container
              Container(
                height: 260,
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.surfaceSecondary),
                ),
                child: _buildAppList(context, colors),
              ),
            ],

            const SizedBox(height: AppSpacing.sm),
            // Selected count footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedApps.length} application(s) selected to block',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _selectedApps.isNotEmpty ? colors.primaryAccent : colors.textSecondary,
                  ),
                ),
                if (_selectedApps.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selectedApps.clear()),
                    child: const Text('Clear All', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.primaryAccent),
          onPressed: () {
            Navigator.of(context).pop(_selectedApps.values.toList());
          },
          child: Text('Done (${_selectedApps.length})'),
        ),
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
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? colors.primaryAccent : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildAppList(BuildContext context, AppThemeColors colors) {
    if (_isLoading) {
      return const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.loader2, size: 16),
            SizedBox(width: 8),
            Text('Scanning applications...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle, color: Colors.orangeAccent, size: 32),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: () => _loadApplications(forceRefresh: true),
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: const Text('Retry Scan'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredApps;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.searchX, size: 36, color: colors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _searchQuery.isNotEmpty ? 'No applications match "$_searchQuery"' : 'No applications found',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'You can add applications manually via the "Manual" button above.',
              style: TextStyle(color: colors.textSecondary.withValues(alpha: 0.7), fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: colors.surfaceSecondary),
      itemBuilder: (context, index) {
        final app = filtered[index];
        final isProtected = FocusAppPickerDialog.isProtectedApp(app.displayName, app.executablePath ?? app.executableName);
        final isSelected = _selectedApps.containsKey(app.displayName.trim().toLowerCase());

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          enabled: !isProtected,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primaryAccent.withValues(alpha: 0.15)
                  : colors.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isProtected
                  ? LucideIcons.shieldCheck
                  : (isSelected ? LucideIcons.check : LucideIcons.appWindow),
              size: 16,
              color: isProtected
                  ? colors.textSecondary
                  : (isSelected ? colors.primaryAccent : colors.textSecondary),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  app.displayName,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isProtected ? colors.textSecondary : colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isProtected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Protected',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            app.executableName ?? app.executablePath ?? app.publisher ?? 'Installed App',
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Checkbox(
            value: isSelected,
            activeColor: colors.primaryAccent,
            onChanged: isProtected ? null : (_) => _toggleApp(app),
          ),
          onTap: isProtected ? null : () => _toggleApp(app),
        );
      },
    );
  }
}
