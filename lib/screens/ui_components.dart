import 'package:flutter/material.dart';

import '../app/theme.dart';

const _backgroundPhoto = AssetImage('assets/images/lipa_background.webp');

/// The website's in-app page background (public/css/home.css .reporter-v5):
/// the Lipa photo under a 62% white wash, with faint red and blue glows.
class AtmosphericBackground extends StatelessWidget {
  const AtmosphericBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _PhotoBackdrop(
      wash: const Color(0x9EFFFFFF),
      glows: const [
        (Alignment(-0.76, -0.64), Color(0x14EF4444)),
        (Alignment(0.72, 0.64), Color(0x141E40AF)),
      ],
      child: child,
    );
  }
}

/// The website's login/register background (public/css/auth.css): the same
/// photo under a lighter 56% white wash, with red and amber glows.
class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _PhotoBackdrop(
      wash: const Color(0x8FFFFFFF),
      glows: const [
        (Alignment(-0.72, -0.68), Color(0x2BEF4444)),
        (Alignment(0.72, -0.72), Color(0x21F59E0B)),
      ],
      child: child,
    );
  }
}

class _PhotoBackdrop extends StatelessWidget {
  const _PhotoBackdrop({required this.wash, required this.glows, required this.child});

  final Color wash;
  final List<(Alignment, Color)> glows;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: RapidAlertColors.background),
        const Image(image: _backgroundPhoto, fit: BoxFit.cover, gaplessPlayback: true),
        ColoredBox(color: wash),
        // CSS radial glows fade out at ~34% of the farthest-corner distance,
        // which on a phone is roughly two-thirds of the screen width.
        for (final (center, color) in glows)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: center,
                radius: 0.67,
                colors: [color, color.withValues(alpha: 0)],
              ),
            ),
          ),
        child,
      ],
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
