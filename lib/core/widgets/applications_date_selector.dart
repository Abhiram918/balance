import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../models/application_analytics_models.dart';

/// Interactive date selector widget for the Applications dashboard and Application Details view.
/// Supports Today, Past 7 Days, Past 30 Days, Custom Date, and Custom Date Range.
class ApplicationsDateSelector extends StatelessWidget {
  final DateRangeSelection selection;
  final ValueChanged<DateRangeSelection> onSelectionChanged;
  final DateTime? referenceDate;

  const ApplicationsDateSelector({
    super.key,
    required this.selection,
    required this.onSelectionChanged,
    this.referenceDate,
  });

  DateTime get _effectiveToday {
    final now = referenceDate ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 680;

        if (isCompact) {
          // Dropdown / Button popup
          return _buildPickerButton(context, theme, colors);
        }

        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.surfaceSecondary),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPresetButton(
                  label: 'Today',
                  preset: DateFilterPreset.today,
                  isSelected: selection.preset == DateFilterPreset.today,
                  colors: colors,
                  onTap: () => onSelectionChanged(DateRangeSelection.today(_effectiveToday)),
                ),
                const SizedBox(width: 2),
                _buildPresetButton(
                  label: 'Past 7 Days',
                  preset: DateFilterPreset.past7Days,
                  isSelected: selection.preset == DateFilterPreset.past7Days,
                  colors: colors,
                  onTap: () => onSelectionChanged(DateRangeSelection.past7Days(_effectiveToday)),
                ),
                const SizedBox(width: 2),
                _buildPresetButton(
                  label: 'Past 30 Days',
                  preset: DateFilterPreset.past30Days,
                  isSelected: selection.preset == DateFilterPreset.past30Days,
                  colors: colors,
                  onTap: () => onSelectionChanged(DateRangeSelection.past30Days(_effectiveToday)),
                ),
                const SizedBox(width: 6),
                Container(width: 1, height: 20, color: colors.surfaceSecondary),
                const SizedBox(width: 6),
                _buildCustomPickerTrigger(context, theme, colors),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresetButton({
    required String label,
    required DateFilterPreset preset,
    required bool isSelected,
    required AppThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomPickerTrigger(
    BuildContext context,
    ThemeData theme,
    AppThemeColors colors,
  ) {
    final isCustom = selection.preset == DateFilterPreset.customDate ||
        selection.preset == DateFilterPreset.customRange;

    String customText;
    if (isCustom) {
      if (selection.isSingleDay) {
        customText = DateFormat('MMM d, yyyy').format(selection.startDate);
      } else {
        customText =
            '${DateFormat('MMM d').format(selection.startDate)} – ${DateFormat('MMM d').format(selection.endDate)}';
      }
    } else {
      customText = 'Custom...';
    }

    return InkWell(
      onTap: () => _openCustomDateDialog(context),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCustom
              ? colors.primaryAccent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.calendar,
              size: 15,
              color: isCustom ? colors.primaryAccent : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              customText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isCustom ? FontWeight.w600 : FontWeight.w500,
                color: isCustom ? colors.primaryAccent : colors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: isCustom ? colors.primaryAccent : colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerButton(
    BuildContext context,
    ThemeData theme,
    AppThemeColors colors,
  ) {
    return InkWell(
      onTap: () => _openCustomDateDialog(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.surfaceSecondary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.calendar, size: 16, color: colors.primaryAccent),
            const SizedBox(width: 8),
            Text(
              selection.formattedDisplayLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronDown, size: 14, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _openCustomDateDialog(BuildContext context) async {
    final result = await showDialog<DateRangeSelection>(
      context: context,
      builder: (ctx) => _ApplicationsDatePickerDialog(
        currentSelection: selection,
        today: _effectiveToday,
      ),
    );

    if (result != null) {
      onSelectionChanged(result);
    }
  }
}

/// Native-feeling Windows calendar dialog for selecting single dates or custom ranges.
class _ApplicationsDatePickerDialog extends StatefulWidget {
  final DateRangeSelection currentSelection;
  final DateTime today;

  const _ApplicationsDatePickerDialog({
    required this.currentSelection,
    required this.today,
  });

  @override
  State<_ApplicationsDatePickerDialog> createState() =>
      _ApplicationsDatePickerDialogState();
}

class _ApplicationsDatePickerDialogState
    extends State<_ApplicationsDatePickerDialog> {
  late bool _isRangeMode;
  late DateTime _startDate;
  late DateTime _endDate;
  DateTime? _rangeAnchor;

  @override
  void initState() {
    super.initState();
    _startDate = widget.currentSelection.startDate;
    _endDate = widget.currentSelection.endDate;
    _isRangeMode = widget.currentSelection.preset == DateFilterPreset.customRange &&
        !widget.currentSelection.isSingleDay;
    if (_startDate.isAfter(widget.today)) _startDate = widget.today;
    if (_endDate.isAfter(widget.today)) _endDate = widget.today;
  }

  void _onDaySelected(DateTime day) {
    final norm = DateTime(day.year, day.month, day.day);
    if (norm.isAfter(widget.today)) return; // Guard against future dates

    setState(() {
      if (!_isRangeMode) {
        _startDate = norm;
        _endDate = norm;
      } else {
        if (_rangeAnchor == null) {
          _rangeAnchor = norm;
          _startDate = norm;
          _endDate = norm;
        } else {
          if (norm.isBefore(_rangeAnchor!)) {
            _startDate = norm;
            _endDate = _rangeAnchor!;
          } else {
            _startDate = _rangeAnchor!;
            _endDate = norm;
          }
          _rangeAnchor = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.primaryAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          LucideIcons.calendar,
                          color: colors.primaryAccent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Date or Range',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isRangeMode
                                ? '${DateFormat('MMM d').format(_startDate)} – ${DateFormat('MMM d, yyyy').format(_endDate)}'
                                : DateFormat('EEEE, MMM d, yyyy').format(_startDate),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.primaryAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Single Date vs Date Range toggle
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _isRangeMode = false;
                            _endDate = _startDate;
                            _rangeAnchor = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: !_isRangeMode ? colors.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: !_isRangeMode
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Single Date',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: !_isRangeMode ? FontWeight.bold : FontWeight.normal,
                              color: !_isRangeMode ? colors.textPrimary : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _isRangeMode = true;
                            _rangeAnchor = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _isRangeMode ? colors.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _isRangeMode
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Date Range',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _isRangeMode ? FontWeight.bold : FontWeight.normal,
                              color: _isRangeMode ? colors.textPrimary : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Calendar Picker
              Theme(
                data: theme.copyWith(
                  colorScheme: theme.colorScheme.copyWith(
                    primary: colors.primaryAccent,
                    onPrimary: Colors.white,
                    surface: colors.surface,
                    onSurface: colors.textPrimary,
                  ),
                ),
                child: CalendarDatePicker(
                  initialDate: _startDate,
                  firstDate: DateTime(2020, 1, 1),
                  lastDate: widget.today,
                  onDateChanged: _onDaySelected,
                ),
              ),

              if (_isRangeMode && _rangeAnchor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Click end date to complete the range (starts ${DateFormat('MMM d').format(_rangeAnchor!)})',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: colors.primaryAccent,
                    ),
                  ),
                ),

              const SizedBox(height: AppSpacing.md),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _startDate = widget.today;
                        _endDate = widget.today;
                        _isRangeMode = false;
                        _rangeAnchor = null;
                      });
                    },
                    child: const Text('Reset to Today'),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.primaryAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          final selection = _isRangeMode
                              ? DateRangeSelection.customRange(_startDate, _endDate)
                              : DateRangeSelection.customDate(_startDate);
                          Navigator.of(context).pop(selection);
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
