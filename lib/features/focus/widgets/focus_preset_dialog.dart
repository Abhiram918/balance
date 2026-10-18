import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/models/focus_preset.dart';
import '../../../core/services/focus_service.dart';
import '../../../core/services/windows_app_discovery_service.dart';
import 'focus_app_picker_dialog.dart';

/// Modal dialog for creating or editing Focus presets with full Pomodoro cycle options
/// and per-preset application block lists.
class FocusPresetDialog extends StatefulWidget {
  final FocusService focusService;
  final WindowsAppDiscoveryService discoveryService;
  final FocusPreset? existingPreset;

  const FocusPresetDialog({
    super.key,
    required this.focusService,
    required this.discoveryService,
    this.existingPreset,
  });

  @override
  State<FocusPresetDialog> createState() => _FocusPresetDialogState();
}

class _FocusPresetDialogState extends State<FocusPresetDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late int _focusMinutes;
  late int _shortBreakMinutes;
  late int _longBreakMinutes;
  late int _cyclesBeforeLongBreak;
  late bool _autoStartBreaks;
  late bool _autoStartFocus;
  late bool _allowSkipBreak;
  late bool _soundEnabled;
  late bool _unblockDuringBreaks;
  late List<FocusPresetBlockedApp> _blockedApps;

  bool _isSaving = false;
  String? _generalError;

  bool get _isEditing => widget.existingPreset != null;
  bool get _isBuiltIn =>
      widget.existingPreset != null &&
      FocusService.builtInPresetNames.contains(widget.existingPreset!.name.trim().toLowerCase());

  @override
  void initState() {
    super.initState();
    final p = widget.existingPreset;
    _nameController = TextEditingController(text: p?.name ?? '');
    _focusMinutes = p != null ? p.focusDuration.inMinutes : 25;
    _shortBreakMinutes = p != null ? p.shortBreakDuration.inMinutes : 5;
    _longBreakMinutes = p != null ? p.longBreakDuration.inMinutes : 15;
    _cyclesBeforeLongBreak = p?.cyclesBeforeLongBreak ?? 4;
    _autoStartBreaks = p?.autoStartBreaks ?? false;
    _autoStartFocus = p?.autoStartFocus ?? false;
    _allowSkipBreak = p?.allowSkipBreak ?? true;
    _soundEnabled = p?.soundEnabled ?? true;
    _unblockDuringBreaks = p?.unblockDuringBreaks ?? true;
    _blockedApps = List.from(p?.blockedApps ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _openAppPicker() async {
    final updated = await showDialog<List<FocusPresetBlockedApp>>(
      context: context,
      builder: (ctx) => FocusAppPickerDialog(
        discoveryService: widget.discoveryService,
        initialBlockedApps: _blockedApps,
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _blockedApps = updated;
      });
    }
  }

  void _removeBlockedApp(int index) {
    setState(() {
      _blockedApps.removeAt(index);
    });
  }

  Future<void> _savePreset() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final trimmedName = _nameController.text.trim();
    final lowerName = trimmedName.toLowerCase();

    // Prevent duplicate names
    final duplicate = widget.focusService.presets.any((p) {
      if (_isEditing && p.id == widget.existingPreset!.id) return false;
      return p.name.trim().toLowerCase() == lowerName;
    });

    if (duplicate) {
      setState(() {
        _generalError = 'A preset named "$trimmedName" already exists. Please choose a different name.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _generalError = null;
    });

    try {
      if (_isEditing) {
        final updated = widget.existingPreset!.copyWith(
          name: trimmedName,
          focusDuration: Duration(minutes: _focusMinutes),
          shortBreakDuration: Duration(minutes: _shortBreakMinutes),
          longBreakDuration: Duration(minutes: _longBreakMinutes),
          cyclesBeforeLongBreak: _cyclesBeforeLongBreak,
          autoStartBreaks: _autoStartBreaks,
          autoStartFocus: _autoStartFocus,
          allowSkipBreak: _allowSkipBreak,
          soundEnabled: _soundEnabled,
          unblockDuringBreaks: _unblockDuringBreaks,
          blockedApps: _blockedApps,
          updatedAt: DateTime.now(),
        );
        await widget.focusService.updatePreset(updated);
      } else {
        final newPreset = FocusPreset(
          name: trimmedName,
          focusDuration: Duration(minutes: _focusMinutes),
          shortBreakDuration: Duration(minutes: _shortBreakMinutes),
          longBreakDuration: Duration(minutes: _longBreakMinutes),
          cyclesBeforeLongBreak: _cyclesBeforeLongBreak,
          autoStartBreaks: _autoStartBreaks,
          autoStartFocus: _autoStartFocus,
          allowSkipBreak: _allowSkipBreak,
          soundEnabled: _soundEnabled,
          unblockDuringBreaks: _unblockDuringBreaks,
          blockedApps: _blockedApps,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await widget.focusService.createPreset(newPreset);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _generalError = 'Failed to save preset: $e';
        });
      }
    }
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
        children: [
          Icon(
            _isEditing ? LucideIcons.sliders : LucideIcons.plusCircle,
            size: 22,
            color: colors.primaryAccent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _isEditing
                ? (_isBuiltIn ? 'Edit Built-in Preset' : 'Edit Focus Preset')
                : 'Create Custom Focus Preset',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Preset Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Preset Name *',
                    hintText: 'e.g. Morning Sprint, Code Session',
                    filled: true,
                    fillColor: colors.surfaceSecondary,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Preset name cannot be empty.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),

                // Durations Section
                Text(
                  'Durations & Intervals',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Focus Duration
                _buildDurationSlider(
                  title: 'Focus Duration',
                  minutes: _focusMinutes,
                  min: 1,
                  max: 120,
                  presets: const [15, 25, 45, 50, 60],
                  accentColor: colors.primaryAccent,
                  onChanged: (val) => setState(() => _focusMinutes = val),
                ),
                const SizedBox(height: AppSpacing.md),

                // Short Break Duration
                _buildDurationSlider(
                  title: 'Short Break Duration',
                  minutes: _shortBreakMinutes,
                  min: 1,
                  max: 30,
                  presets: const [3, 5, 10, 15],
                  accentColor: colors.greenAccent,
                  onChanged: (val) => setState(() => _shortBreakMinutes = val),
                ),
                const SizedBox(height: AppSpacing.md),

                // Long Break Duration
                _buildDurationSlider(
                  title: 'Long Break Duration',
                  minutes: _longBreakMinutes,
                  min: 1,
                  max: 60,
                  presets: const [10, 15, 20, 30],
                  accentColor: colors.greenAccent,
                  onChanged: (val) => setState(() => _longBreakMinutes = val),
                ),
                const SizedBox(height: AppSpacing.md),

                // Cycles before long break
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cycles Before Long Break',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Number of focus rounds before triggering a long break.',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                    Row(
                      children: [1, 2, 3, 4, 6].map((count) {
                        final isSel = _cyclesBeforeLongBreak == count;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text('$count'),
                            selected: isSel,
                            onSelected: (_) => setState(() => _cyclesBeforeLongBreak = count),
                            selectedColor: colors.primaryAccent.withValues(alpha: 0.18),
                            backgroundColor: colors.surfaceSecondary,
                            labelStyle: TextStyle(
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              color: isSel ? colors.primaryAccent : colors.textSecondary,
                            ),
                            side: BorderSide(
                              color: isSel ? colors.primaryAccent : Colors.transparent,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),

                // Automation & Break Behavior
                Text(
                  'Transitions & Behavior',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),

                _buildSwitchTile(
                  title: 'Automatic Break Start',
                  subtitle: 'Automatically start breaks when the focus timer completes.',
                  value: _autoStartBreaks,
                  onChanged: (v) => setState(() => _autoStartBreaks = v),
                  activeColor: colors.primaryAccent,
                ),
                _buildSwitchTile(
                  title: 'Automatic Focus Restart',
                  subtitle: 'Automatically start next focus cycle when break completes.',
                  value: _autoStartFocus,
                  onChanged: (v) => setState(() => _autoStartFocus = v),
                  activeColor: colors.primaryAccent,
                ),
                _buildSwitchTile(
                  title: 'Allow Skipping Breaks',
                  subtitle: 'Show action to jump directly to the next focus cycle during breaks.',
                  value: _allowSkipBreak,
                  onChanged: (v) => setState(() => _allowSkipBreak = v),
                  activeColor: colors.primaryAccent,
                ),
                _buildSwitchTile(
                  title: 'Completion Sound Chime',
                  subtitle: 'Play audio notification on interval transitions (respects global settings).',
                  value: _soundEnabled,
                  onChanged: (v) => setState(() => _soundEnabled = v),
                  activeColor: colors.primaryAccent,
                ),
                _buildSwitchTile(
                  title: 'Allow Blocked Apps During Breaks',
                  subtitle: _unblockDuringBreaks
                      ? 'Distraction apps become accessible during breaks to help you recharge.'
                      : 'Distraction apps remain blocked during breaks to maintain discipline.',
                  value: _unblockDuringBreaks,
                  onChanged: (v) => setState(() => _unblockDuringBreaks = v),
                  activeColor: colors.greenAccent,
                ),

                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),

                // Blocked Applications Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blocked Applications (${_blockedApps.length})',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Apps restricted from running during this preset.',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _openAppPicker,
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('Add Apps'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.surfaceSecondary,
                        foregroundColor: colors.primaryAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                if (_blockedApps.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: colors.surfaceSecondary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'No applications blocked for this preset.\nSessions will run without app enforcement.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _blockedApps.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final app = entry.value;
                      return Chip(
                        label: Text(app.appName),
                        avatar: Icon(LucideIcons.appWindow, size: 14, color: colors.primaryAccent),
                        deleteIcon: const Icon(LucideIcons.x, size: 14),
                        onDeleted: () => _removeBlockedApp(idx),
                        backgroundColor: colors.surfaceSecondary,
                        side: BorderSide(color: colors.primaryAccent.withValues(alpha: 0.3)),
                      );
                    }).toList(),
                  ),

                if (_generalError != null) ...[
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
                            _generalError!,
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
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.primaryAccent),
          onPressed: _isSaving ? null : _savePreset,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEditing ? 'Save Changes' : 'Create Preset'),
        ),
      ],
    );
  }

  Widget _buildDurationSlider({
    required String title,
    required int minutes,
    required int min,
    required int max,
    required List<int> presets,
    required Color accentColor,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(
                '$minutes min',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ],
          ),
          Slider(
            value: minutes.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min),
            activeColor: accentColor,
            onChanged: (v) => onChanged(v.toInt()),
          ),
          Wrap(
            spacing: 6,
            children: presets.map((p) {
              final isSel = minutes == p;
              return ChoiceChip(
                label: Text('$p min'),
                selected: isSel,
                onSelected: (_) => onChanged(p),
                selectedColor: accentColor.withValues(alpha: 0.18),
                backgroundColor: colors.surfaceSecondary,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  color: isSel ? accentColor : colors.textSecondary,
                ),
                side: BorderSide(color: isSel ? accentColor : Colors.transparent),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color activeColor,
  }) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Switch(
            value: value,
            activeThumbColor: activeColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
