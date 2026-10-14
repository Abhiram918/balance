import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

class AppSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Container(
      width: 240,
      color: colors.surface,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.primaryAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.activity,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Balance',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _SidebarItem(
            icon: LucideIcons.layoutDashboard,
            label: 'Overview',
            isSelected: selectedIndex == 0,
            onTap: () => onItemSelected(0),
          ),
          _SidebarItem(
            icon: LucideIcons.layoutGrid,
            label: 'Applications',
            isSelected: selectedIndex == 1,
            onTap: () => onItemSelected(1),
          ),
          _SidebarItem(
            icon: LucideIcons.focus,
            label: 'Focus',
            isSelected: selectedIndex == 2,
            onTap: () => onItemSelected(2),
          ),
          _SidebarItem(
            icon: LucideIcons.barChart2,
            label: 'Insights',
            isSelected: selectedIndex == 3,
            onTap: () => onItemSelected(3),
          ),
          _SidebarItem(
            icon: LucideIcons.shieldAlert,
            label: 'Limits',
            isSelected: selectedIndex == 4,
            onTap: () => onItemSelected(4),
          ),
          const Spacer(),
          _SidebarItem(
            icon: LucideIcons.settings,
            label: 'Settings',
            isSelected: selectedIndex == 5,
            onTap: () => onItemSelected(5),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.innerRadius),
          hoverColor: colors.surfaceSecondary.withValues(alpha: 0.5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primaryAccent.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.innerRadius),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? colors.primaryAccent
                      : colors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? colors.primaryAccent
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
