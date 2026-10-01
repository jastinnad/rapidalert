import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'ui_components.dart';

/// The website's auth card (public/css/auth.css .auth-shell) over the Lipa
/// photo. Phones have no room for the web's side-by-side columns, so the red
/// brand panel (.auth-right) sits on top and the form (.auth-left) below.
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.tagline,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String tagline;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      // Keep the photo still when the keyboard opens; the scroll view pads
      // itself instead.
      resizeToAvoidBottomInset: false,
      body: AuthBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboard),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: RapidAlertColors.cardBorder),
                    boxShadow: const [
                      BoxShadow(color: Color(0x290F172A), blurRadius: 34, offset: Offset(0, 16)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BrandPanel(tagline: tagline),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: RapidAlertColors.darkText,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: const TextStyle(fontSize: 15, color: RapidAlertColors.lightText),
                              ),
                              const SizedBox(height: 20),
                              ...children,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.tagline});

  final String tagline;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: authGradient),
      child: DecoratedBox(
        // .auth-right's two soft white highlights.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.56, -0.52),
            radius: 0.9,
            colors: [Color(0x29FFFFFF), Color(0x00FFFFFF)],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.52, 0.4),
              radius: 0.9,
              colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
            child: Column(
              children: [
                // The web draws a 150px white circle holding a 190px logo
                // (the badge has transparent padding); same ratio here.
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x477F1D1D), blurRadius: 24, offset: Offset(0, 10)),
                    ],
                  ),
                  child: ClipOval(
                    child: OverflowBox(
                      maxWidth: 152,
                      maxHeight: 152,
                      child: Image.asset('assets/images/rapid_alert_logo.png', width: 152, height: 152),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Rapid Alert',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.92)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled input matching auth.css: bold slate label, and a single-letter
/// prefix glyph where the website uses one (it uses letters, not icons).
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.glyph,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.helper,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String glyph;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RapidAlertColors.labelText),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            autocorrect: !obscureText && keyboardType != TextInputType.emailAddress,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: const TextStyle(fontSize: 14, color: RapidAlertColors.darkText),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: SizedBox(
                width: 34,
                child: Center(
                  child: Text(
                    glyph,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RapidAlertColors.inputIcon),
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 34),
              suffixIcon: suffixIcon,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(helper!, style: const TextStyle(fontSize: 12, color: RapidAlertColors.lightText)),
          ],
        ],
      ),
    );
  }
}

/// A labelled pick-one field styled like [AuthField], for values that must come
/// from a fixed list (e.g. the PSGC address lists). While [items] is
/// unavailable it shows a loading line, or [error] with a Retry action.
class AuthDropdownField extends StatelessWidget {
  const AuthDropdownField({
    super.key,
    required this.label,
    required this.glyph,
    required this.hint,
    required this.items,
    required this.value,
    required this.onChanged,
    this.itemLabel,
    this.enabled = true,
    this.loading = false,
    this.loadingText = 'Loading…',
    this.error,
    this.onRetry,
    this.helper,
  });

  final String label;
  final String glyph;
  final String hint;
  final List<String> items;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Text shown for an item when the item itself is a code.
  final String Function(String item)? itemLabel;
  final bool enabled;
  final bool loading;
  final String loadingText;
  final String? error;
  final VoidCallback? onRetry;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final Widget field;
    if (loading) {
      field = Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: RapidAlertColors.background,
          border: Border.all(color: RapidAlertColors.cardBorder),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(loadingText, style: const TextStyle(fontSize: 14, color: RapidAlertColors.lightText)),
            ),
          ],
        ),
      );
    } else if (error != null) {
      field = Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          border: Border.all(color: const Color(0xFFFCA5A5)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(error!, style: const TextStyle(fontSize: 13, color: RapidAlertColors.linkRed)),
            ),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    } else {
      field = DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        menuMaxHeight: 360,
        hint: Text(hint, style: const TextStyle(fontSize: 14)),
        style: const TextStyle(fontSize: 14, color: RapidAlertColors.darkText),
        decoration: InputDecoration(
          prefixIcon: SizedBox(
            width: 34,
            child: Center(
              child: Text(
                glyph,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RapidAlertColors.inputIcon),
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
        ),
        items: items.map((item) => DropdownMenuItem(value: item, child: Text(itemLabel?.call(item) ?? item))).toList(),
        onChanged: enabled ? onChanged : null,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RapidAlertColors.labelText),
          ),
          const SizedBox(height: 6),
          field,
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(helper!, style: const TextStyle(fontSize: 12, color: RapidAlertColors.lightText)),
          ],
        ],
      ),
    );
  }
}

/// Show/hide toggle for password fields.
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({super.key, required this.obscured, required this.onPressed});

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        color: RapidAlertColors.inputIcon,
        size: 20,
      ),
      onPressed: onPressed,
    );
  }
}

/// auth.css .btn-primary: 135deg red gradient, radius 11, 46px tall.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: Ink(
            decoration: BoxDecoration(gradient: authButtonGradient, borderRadius: BorderRadius.circular(11)),
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: enabled ? onPressed : null,
              child: Opacity(
                opacity: enabled || busy ? 1 : 0.5,
                child: Center(
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(
                          label,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// auth.css .auth-banner, used for errors.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFEE2E2)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: RapidAlertColors.linkRed, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

/// auth.css footer: a hairline divider, then muted text with bold red links.
class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: RapidAlertColors.cardBorder)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// One footer line: optional muted lead-in text followed by a bold red link.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({super.key, this.lead, required this.label, required this.onTap});

  final String? lead;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text.rich(
          TextSpan(
            children: [
              if (lead != null)
                TextSpan(text: '$lead ', style: const TextStyle(color: RapidAlertColors.lightText)),
              TextSpan(
                text: label,
                style: const TextStyle(color: RapidAlertColors.linkRed, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
