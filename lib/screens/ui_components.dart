import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Plain background — no decorative blur or gradient orbs, kept flat and
/// consistent with the rest of the app.
class AtmosphericBackground extends StatelessWidget {
  const AtmosphericBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RapidAlertColors.background,
      child: child,
    );
  }
}

/// Flat card: solid white, a thin border, minimal shadow. No blur.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: RapidAlertColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RapidAlertColors.border),
      ),
      child: child,
    );
  }
}

/// Page header used at the top of every screen: a title and a subtitle,
/// no colored banner. Kept in one place so every screen looks the same.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: RapidAlertColors.darkText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 14, color: RapidAlertColors.lightText),
        ),
      ],
    );
  }
}
