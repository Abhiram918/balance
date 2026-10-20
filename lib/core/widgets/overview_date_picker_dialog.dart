import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/theme/app_colors.dart';

/// Date selection dialog for Overview header and Daily Summary controls.
/// - Calendar picker with strict upper bound of today (no future dates).
/// - Quick shortcuts for "Today" and "Yesterday".
/// - "Reset to Today" convenience action.
/// - Cancel and Apply buttons.
class OverviewDatePickerDialog extends StatefulWidget {
  final DateTime selectedDate;
  final DateTime today;

  const OverviewDatePickerDialog({
    super.key,
    required this.selectedDate,
    required this.today,
  });

  @override
  State<OverviewDatePickerDialog> createState() => _OverviewDatePickerDialogState();
}

class _OverviewDatePickerDialogState extends State<OverviewDatePickerDialog> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );
    if (_selected.isAfter(widget.today)) {
      _selected = widget.today;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    final yesterday = widget.today.subtract(const Duration(days: 1));
    final isTodaySelected = _isSameDay(_selected, widget.today);
    final isYesterdaySelected = _isSameDay(_selected, yesterday);

    final formattedHeaderDate = isTodaySelected
        ? 'Today, ${DateFormat('MMM d, yyyy').format(_selected)}'
        : (isYesterdaySelected
            ? 'Yesterday, ${DateFormat('MMM d, yyyy').format(_selected)}'
            : DateFormat('EEEE, MMM d, yyyy').format(_selected));

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header with icon, title, current date subtitle, and close button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark
                                ? colors.primaryAccent.withValues(alpha: 0.15)
                                : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            LucideIcons.calendar,
                            color: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Date',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formattedHeaderDate,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    color: colors.textSecondary,
                    splashRadius: 20,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Quick shortcut chips: Today, Yesterday
              Row(
                children: [
                  _buildQuickChip(
                    label: 'Today',
                    isSelected: isTodaySelected,
                    colors: colors,
                    isDark: isDark,
                    onTap: () {
                      setState(() {
                        _selected = widget.today;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildQuickChip(
                    label: 'Yesterday',
                    isSelected: isYesterdaySelected,
                    colors: colors,
                    isDark: isDark,
                    onTap: () {
                      setState(() {
                        _selected = yesterday;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),

              // 3. Calendar Date Picker with lastDate = widget.today (No future dates)
              Theme(
                data: theme.copyWith(
                  colorScheme: theme.colorScheme.copyWith(
                    primary: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
                    onPrimary: isDark ? colors.background : Colors.white,
                    surface: colors.surface,
                    onSurface: colors.textPrimary,
                  ),
                ),
                child: SizedBox(
                  height: 290,
                  child: CalendarDatePicker(
                    initialDate: _selected,
                    firstDate: DateTime(2020, 1, 1),
                    lastDate: widget.today, // Strictly prevents future dates
                    onDateChanged: (newDate) {
                      setState(() {
                        _selected = DateTime(newDate.year, newDate.month, newDate.day);
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // 4. Action Buttons: Reset to Today, Cancel, Apply
              Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop(widget.today);
                        },
                        icon: const Icon(LucideIcons.rotateCcw, size: 14),
                        label: const Text('Reset to Today'),
                        style: TextButton.styleFrom(
                          foregroundColor: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.surfaceSecondary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(_selected);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? colors.primaryAccent : const Color(0xFF2563EB),
                      foregroundColor: isDark ? colors.background : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip({
    required String label,
    required bool isSelected,
    required AppThemeColors colors,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? colors.primaryAccent : const Color(0xFF2563EB))
              : (isDark ? colors.surfaceSecondary : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (isDark ? colors.primaryAccent : const Color(0xFF2563EB))
                : colors.surfaceSecondary,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? (isDark ? colors.background : Colors.white)
                : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
