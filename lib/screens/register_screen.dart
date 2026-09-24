import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/auth_service.dart';

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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: RapidAlertColors.darkText),
        title: const Text(
          'Create Reporter Account',
          style: TextStyle(color: RapidAlertColors.darkText, fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Register to report hazards and track their status. '
                'Responder accounts are provisioned by an administrator.',
                style: TextStyle(fontSize: 13, color: RapidAlertColors.lightText, height: 1.4),
              ),
              const SizedBox(height: 20),
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
                    style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(child: _field('First name', _firstNameController)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Last name', _lastNameController)),
                ],
              ),
              const SizedBox(height: 14),
              _field('Email', _emailController, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 14),
              _field(
                'Phone (11 digits)',
                _phoneController,
                keyboardType: TextInputType.phone,
                hint: '09XXXXXXXXX',
              ),
              const SizedBox(height: 14),
              _field(
                'Password (min. 8 characters)',
                _passwordController,
                obscure: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Address (Lipa City pilot area)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RapidAlertColors.darkText),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field('House / block no.', _houseNoController)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Purok', _purokController)),
                ],
              ),
              const SizedBox(height: 14),
              _field('Barangay', _barangayController),
              const SizedBox(height: 14),
              _field('Landmark (optional)', _landmarkController),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  child: Ink(
                    decoration: BoxDecoration(gradient: authGradient, borderRadius: BorderRadius.circular(11)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: _canSubmit ? _submit : null,
                      child: Opacity(
                        opacity: _canSubmit ? 1 : 0.5,
                        child: Center(
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                )
                              : const Text(
                                  'Create Account',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.onBackToLogin != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: widget.onBackToLogin,
                    child: const Text('Already have an account? Sign in'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffixIcon,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
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
          ),
        ),
      ],
    );
  }
}
