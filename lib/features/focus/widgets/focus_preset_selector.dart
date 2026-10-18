import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/models/focus_preset.dart';
import '../../../core/services/focus_service.dart';
import '../../../core/services/windows_app_discovery_service.dart';
import 'focus_preset_dialog.dart';

/// Preset selector displaying built-in and custom presets with metrics,
/// selection state, and preset management actions.
class FocusPresetSelector extends StatelessWidget {
  final FocusService focusService;
  final WindowsAppDiscoveryService discoveryService;

  const FocusPresetSelector({
    super.key,
    required this.focusService,
    required this.discoveryService,
  });

  bool get _isSessionActive => focusService.isRunning || focusService.isPaused;

  Future<void> _openCreateDialog(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (ctx) => FocusPresetDialog(
        focusService: focusService,
        discoveryService: discoveryService,
      ),
    );
  }

  Future<void> _openEditDialog(BuildContext context, FocusPreset preset) async {
    await showDialog<bool>(
      context: context,
      builder: (ctx) => FocusPresetDialog(
        focusService: focusService,
        discoveryService: discoveryService,
        existingPreset: preset,
      ),
    );
  }

  Future<void> _duplicatePreset(BuildContext context, FocusPreset preset) async {
    try {
      final copy = await focusService.duplicatePreset(preset);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preset duplicated as "${copy.name}"'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to duplicate preset: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _confirmDeletePreset(BuildContext context, FocusPreset preset) async {
    if (preset.id == null) return;
    final isBuiltIn = FocusService.builtInPresetNames.contains(preset.name.trim().toLowerCase());
    if (isBuiltIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Built-in presets cannot be deleted.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Preset?'),
        content: Text(
          'Are you sure you want to delete "${preset.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await focusService.deletePreset(preset.id!);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preset "${preset.name}" deleted.'),
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete preset: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final presets = focusService.presets;
    final selected = focusService.selectedPreset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(LucideIcons.layoutGrid, size: 16, color: colors.textPrimary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Focus Presets',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${presets.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            FilledButton.tonalIcon(
              onPressed: () => _openCreateDialog(context),
              icon: const Icon(LucideIcons.plus, size: 13),
              label: const Text('New Preset', style: TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(
                backgroundColor: colors.surfaceSecondary,
                foregroundColor: colors.primaryAccent,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Horizontal scrollable preset cards row
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: presets.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final preset = presets[index];
              final isSelected = selected?.id != null && preset.id != null
                  ? selected!.id == preset.id
                  : selected?.name.toLowerCase() == preset.name.toLowerCase();

              return SizedBox(
                width: 250,
                child: _buildPresetCard(context, preset, isSelected, colors, theme),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPresetCard(
    BuildContext context,
    FocusPreset preset,
    bool isSelected,
    AppThemeColors colors,
    ThemeData theme,
  ) {
    final isBuiltIn = FocusService.builtInPresetNames.contains(preset.name.trim().toLowerCase());
    final accentColor = colors.primaryAccent;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_isSessionActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot switch preset during an active session.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        focusService.selectPreset(preset);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.surface
              : colors.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? accentColor
                : colors.surfaceSecondary,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: accentColor.withValues(alpha: 0.12),
                blurRadius: 8,
                spreadRadius: 1,
                offset: const Offset(0, 1),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Top Row: Name, Badge, Menu
            Row(
              children: [
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(LucideIcons.checkCircle2, size: 14, color: accentColor),
                  ),
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          preset.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (preset.isDefault) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(LucideIcons.moreVertical, size: 14, color: colors.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _openEditDialog(context, preset);
                    } else if (val == 'duplicate') {
                      _duplicatePreset(context, preset);
                    } else if (val == 'delete') {
                      _confirmDeletePreset(context, preset);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(LucideIcons.pencil, size: 13),
                          SizedBox(width: 8),
                          Text('Edit Preset', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Row(
                        children: [
                          Icon(LucideIcons.copy, size: 13),
                          SizedBox(width: 8),
                          Text('Duplicate', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    if (!isBuiltIn)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(LucideIcons.trash2, size: 13, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Durations breakdown
            Row(
              children: [
                Icon(LucideIcons.flame, size: 11, color: accentColor),
                const SizedBox(width: 3),
                Text(
                  '${preset.focusDuration.inMinutes}m Focus',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(LucideIcons.coffee, size: 11, color: colors.greenAccent),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    '${preset.shortBreakDuration.inMinutes}m/${preset.longBreakDuration.inMinutes}m Break',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Cycles and apps
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.repeat, size: 10, color: colors.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      '${preset.cyclesBeforeLongBreak} cycles',
                      style: TextStyle(fontSize: 10, color: colors.textSecondary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: preset.blockedApps.isNotEmpty
                        ? Colors.deepPurpleAccent.withValues(alpha: 0.12)
                        : colors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        preset.blockedApps.isNotEmpty ? LucideIcons.shieldAlert : LucideIcons.shieldCheck,
                        size: 10,
                        color: preset.blockedApps.isNotEmpty ? Colors.deepPurpleAccent : colors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        preset.blockedApps.isNotEmpty
                            ? '${preset.blockedApps.length} blocked'
                            : 'No apps blocked',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: preset.blockedApps.isNotEmpty ? Colors.deepPurpleAccent : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
