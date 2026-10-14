import 'package:flutter/material.dart';
import '../../app/theme/app_spacing.dart';

class RoundedMetricCard extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final CrossAxisAlignment crossAxisAlignment;

  const RoundedMetricCard({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.width,
    this.height,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        boxShadow:
            backgroundColor == null ||
                backgroundColor == theme.colorScheme.surface
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
