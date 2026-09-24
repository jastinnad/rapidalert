import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/auth_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_submitting &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: RapidAlertColors.emergencyRed,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _BrandHeader(),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 420),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(28, 34, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome Back',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: RapidAlertColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sign in to your Rapid Alert account',
                      style: TextStyle(fontSize: 14, color: RapidAlertColors.lightText),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5F5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFEE2E2)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Text(
                      'Email',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldDecoration(
                        hint: 'Enter email',
                        icon: Icons.alternate_email_rounded,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Password',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => canSubmit ? _submit() : null,
                      decoration: _fieldDecoration(
                        hint: 'Enter password',
                        icon: Icons.lock_outline_rounded,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: authGradient,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: canSubmit ? _submit : null,
                            child: Opacity(
                              opacity: canSubmit ? 1 : 0.5,
                              child: Center(
                                child: _submitting
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Sign In',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Divider(color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 14),
                    if (widget.onRegister != null) ...[
                      Center(
                        child: TextButton(
                          onPressed: widget.onRegister,
                          child: const Text(
                            "Don't have an account? Register as a reporter",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: RapidAlertColors.primaryRed,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (widget.onGuestReport != null) ...[
                      Center(
                        child: TextButton(
                          onPressed: widget.onGuestReport,
                          child: const Text(
                            'Report a hazard without an account',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: RapidAlertColors.operationsBlue,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    const Text(
                      'Responder accounts are provisioned by an administrator. '
                      'Contact your administrator for access or a password reset.',
                      style: TextStyle(fontSize: 12.5, color: RapidAlertColors.lightText, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      prefixIcon: Icon(icon, size: 19, color: const Color(0xFF94A3B8)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: RapidAlertColors.border, width: 2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: RapidAlertColors.border, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFFF87171), width: 2),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      decoration: BoxDecoration(gradient: authGradient),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7F1D1D).withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Image.asset('assets/images/rapid_alert_logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(height: 16),
          const Text(
            'Rapid Alert',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Hazard Monitoring and Response Portal',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.92)),
          ),
        ],
      ),
    );
  }
}
