import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/auth_service.dart';
import 'ui_components.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.session, this.onLogout});

  final UserSession? session;
  final VoidCallback? onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _handleSignOut() async {
    if (widget.onLogout == null) return;
    setState(() => _signingOut = true);
    // Triggers AuthGate to swap to the login screen underneath. Since this
    // screen was reached via Navigator.push, it sits on top of that swap and
    // must pop itself to actually reveal it.
    widget.onLogout!();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final initials = _initialsFor(session?.firstName, session?.lastName);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: RapidAlertColors.primaryRed.withValues(alpha: 0.12),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: RapidAlertColors.primaryRed,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  session?.fullName.trim().isNotEmpty == true ? session!.fullName : 'Account',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (session?.email.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(session!.email, style: const TextStyle(color: RapidAlertColors.lightText)),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: RapidAlertColors.operationsBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    session?.isReporter == true ? 'Reporter' : 'Responder',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: RapidAlertColors.operationsBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: RapidAlertColors.primaryRed),
              title: const Text('Sign Out'),
              trailing: _signingOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: widget.onLogout == null || _signingOut ? null : _handleSignOut,
            ),
          ),
        ],
      ),
    );
  }

  String _initialsFor(String? first, String? last) {
    final a = (first ?? '').trim();
    final b = (last ?? '').trim();
    if (a.isEmpty && b.isEmpty) return 'R';
    return '${a.isNotEmpty ? a[0] : ''}${b.isNotEmpty ? b[0] : ''}'.toUpperCase();
  }
}
