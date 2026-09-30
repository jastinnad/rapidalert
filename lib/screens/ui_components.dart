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

/// A plain-language failure message with a Retry button, in place of a raw
/// exception.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 36, color: RapidAlertColors.lightText),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: RapidAlertColors.darkText)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: RapidAlertColors.primaryRed),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Marks data as a saved copy, never live: an OFFLINE badge, when it was
/// saved, and a Retry.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.savedAt, required this.onRetry, this.detail});

  final DateTime savedAt;
  final VoidCallback? onRetry;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final saved = TimeOfDay.fromDateTime(savedAt).format(context);
    final today = DateUtils.isSameDay(savedAt, DateTime.now());
    final when = today ? saved : '${savedAt.month}/${savedAt.day} $saved';
    final text = 'Showing the copy saved at $when.${detail != null ? ' $detail' : ''}';

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: const Color(0xFFFED7AA)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF9A3412), borderRadius: BorderRadius.circular(6)),
              child: const Text(
                'OFFLINE',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412), fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
