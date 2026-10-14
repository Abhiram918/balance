import 'package:flutter/material.dart';
import '../../app/app.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/widgets/page_header.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeColors>()!;
    final settingsService = SettingsProvider.of(context);
    final tracker = TrackerProvider.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              title: 'Settings',
              subtitle: 'Customize your Balance experience.',
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('General', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            _buildSettingSwitch(
              context: context,
              colors: colors,
              title: 'Launch on Startup',
              subtitle: 'Start Balance automatically when you log in.',
              icon: LucideIcons.power,
              value: settingsService.launchOnStartup,
              onChanged: (val) async {
                final success = await settingsService.setLaunchOnStartup(val);
                if (!success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to update Windows startup registration.'),
                    ),
                  );
                }
              },
            ),
            _buildSettingSwitch(
              context: context,
              colors: colors,
              title: 'Notifications',
              subtitle: 'Receive alerts for limits and focus sessions.',
              icon: LucideIcons.bell,
              value: settingsService.notifications,
              onChanged: (val) => settingsService.setNotifications(val),
            ),
            _buildSettingSwitch(
              context: context,
              colors: colors,
              title: 'Dark Mode',
              subtitle: 'Toggle dark theme.',
              icon: LucideIcons.moon,
              value: settingsService.darkMode,
              onChanged: (val) => settingsService.setDarkMode(val),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Tracking', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
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
                      Icon(LucideIcons.coffee, color: colors.primaryAccent),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Idle Timeout', style: theme.textTheme.titleMedium),
                            Text(
                              'Stop tracking after ${settingsService.idleTimeoutMinutes.toInt()} minutes of inactivity.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Slider(
                    value: settingsService.idleTimeoutMinutes,
                    min: 1,
                    max: 15,
                    divisions: 14,
                    label: '${settingsService.idleTimeoutMinutes.toInt()} min',
                    activeColor: colors.primaryAccent,
                    onChanged: (val) {
                      settingsService.setIdleTimeoutMinutes(val);
                      tracker.setIdleThreshold(Duration(minutes: val.toInt()));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingSwitch({
    required BuildContext context,
    required AppThemeColors colors,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primaryAccent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.primaryAccent,
          ),
        ],
      ),
    );
  }
}

