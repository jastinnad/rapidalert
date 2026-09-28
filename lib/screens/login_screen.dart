import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../data/app_config.dart';
import '../data/auth_service.dart';
import 'auth_components.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn, this.onRegister, this.onGuestReport});

  final ValueChanged<UserSession> onSignedIn;
  final VoidCallback? onRegister;
  final VoidCallback? onGuestReport;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && _emailController.text.trim().isNotEmpty && _passwordController.text.isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final session = await AuthService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      widget.onSignedIn(session);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openForgotPassword() async {
    final opened = await launchUrl(
      Uri.parse('${AppConfig.apiBaseUrl}/reporter/password/forgot'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      tagline: 'Hazard Monitoring and Response Portal',
      title: 'Welcome Back',
      subtitle: 'Sign in to your account',
      children: [
        if (_error != null) AuthErrorBanner(message: _error!),
        AuthField(
          label: 'Email',
          glyph: '@',
          hint: 'Enter email',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
        ),
        AuthField(
          label: 'Password',
          glyph: 'L',
          hint: 'Enter password',
          controller: _passwordController,
          obscureText: _obscurePassword,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _canSubmit ? _submit() : null,
          suffixIcon: PasswordVisibilityToggle(
            obscured: _obscurePassword,
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        AuthPrimaryButton(
          label: 'Sign In',
          busy: _submitting,
          onPressed: _canSubmit ? _submit : null,
        ),
        AuthFooter(
          children: [
            // Password resets are web-only (the backend has no API for it),
            // same link the website's login shows.
            AuthFooterLink(label: 'Forgot Password? (Reporter accounts)', onTap: _openForgotPassword),
            if (widget.onRegister != null)
              AuthFooterLink(lead: "Don't have an account?", label: 'Register Here', onTap: widget.onRegister!),
            if (widget.onGuestReport != null)
              AuthFooterLink(label: 'Report a hazard without an account', onTap: widget.onGuestReport!),
            const SizedBox(height: 8),
            const Text(
              'Responder accounts are provisioned by an administrator. '
              'Contact your administrator for access or a password reset.',
              style: TextStyle(fontSize: 12.5, color: RapidAlertColors.lightText, height: 1.4),
            ),
          ],
        ),
      ],
    );
  }
}
