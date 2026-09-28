import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import 'auth_components.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.onRegistered, this.onBackToLogin});

  final ValueChanged<UserSession> onRegistered;
  final VoidCallback? onBackToLogin;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _houseNoController = TextEditingController();
  final _purokController = TextEditingController();
  final _barangayController = TextEditingController();
  final _landmarkController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _houseNoController.dispose();
    _purokController.dispose();
    _barangayController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _phoneController.text.trim().length == 11 &&
      _passwordController.text.length >= 8 &&
      _houseNoController.text.trim().isNotEmpty &&
      _purokController.text.trim().isNotEmpty &&
      _barangayController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final session = await AuthService.register(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        houseNo: _houseNoController.text.trim(),
        purok: _purokController.text.trim(),
        barangay: _barangayController.text.trim(),
        landmark: _landmarkController.text.trim().isEmpty ? null : _landmarkController.text.trim(),
      );
      if (!mounted) return;
      widget.onRegistered(session);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    void refresh(String _) => setState(() {});

    // Same fields, order, labels and placeholders as the website's register
    // form (resources/views/reporter/register.blade.php).
    return AuthPage(
      tagline: 'Community-first hazard preparedness system',
      title: 'Create Account',
      subtitle: 'Set up your Rapid Alert access profile',
      children: [
        if (_error != null) AuthErrorBanner(message: _error!),
        AuthField(label: 'First Name', glyph: 'U', hint: 'Enter first name', controller: _firstNameController, onChanged: refresh),
        AuthField(label: 'Last Name', glyph: 'U', hint: 'Enter last name', controller: _lastNameController, onChanged: refresh),
        AuthField(
          label: 'Email',
          glyph: '@',
          hint: 'Enter email',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          onChanged: refresh,
        ),
        AuthField(
          label: 'Phone Number',
          glyph: '#',
          hint: '09XXXXXXXXX',
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          onChanged: refresh,
        ),
        AuthField(label: 'House No.', glyph: 'H', hint: 'House number', controller: _houseNoController, onChanged: refresh),
        AuthField(label: 'Purok', glyph: 'P', hint: 'Purok', controller: _purokController, onChanged: refresh),
        AuthField(
          label: 'Barangay',
          glyph: 'B',
          hint: 'Enter barangay',
          helper: 'Lipa City only.',
          controller: _barangayController,
          onChanged: refresh,
        ),
        AuthField(
          label: 'Landmark (Optional)',
          glyph: 'L',
          hint: 'Nearby landmark',
          controller: _landmarkController,
          onChanged: refresh,
        ),
        AuthField(
          label: 'Password',
          glyph: 'L',
          hint: 'Create password',
          helper: 'At least 8 characters.',
          controller: _passwordController,
          obscureText: _obscurePassword,
          onChanged: refresh,
          suffixIcon: PasswordVisibilityToggle(
            obscured: _obscurePassword,
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        AuthPrimaryButton(
          label: 'Create Account',
          busy: _submitting,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (widget.onBackToLogin != null)
          AuthFooter(
            children: [
              AuthFooterLink(lead: 'Already have an account?', label: 'Login Here', onTap: widget.onBackToLogin!),
            ],
          ),
      ],
    );
  }
}
