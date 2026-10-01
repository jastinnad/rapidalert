import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/api_reporter_service.dart';
import '../data/app_config.dart';
import '../data/auth_service.dart';
import '../data/reporter_service.dart';
import '../models/reporter_models.dart';
import 'evacuation_centers_screen.dart';
import 'preparedness_assistant_sheet.dart';
import 'report_submit_screen.dart';
import 'report_tracking_screen.dart';
import 'settings_screen.dart';
import 'ui_components.dart';

class ReporterHomeShell extends StatefulWidget {
  const ReporterHomeShell({super.key, this.session, this.onLogout, this.isGuest = false});

  final UserSession? session;
  final VoidCallback? onLogout;

  /// True when reached via "Report a hazard without an account" — no
  /// session, no account-bound features (check-in, profile). Reports are
  /// tracked by a locally-generated device ID instead.
  final bool isGuest;

  @override
  State<ReporterHomeShell> createState() => _ReporterHomeShellState();
}

class _ReporterHomeShellState extends State<ReporterHomeShell> {
  late final ReporterService _service;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    _service = ApiReporterService(
      baseUrl: AppConfig.apiBaseUrl,
      bearerToken: session?.token ?? '',
      myUserId: session?.responderUserId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.isGuest
        ? [
            ReportSubmitScreen(
              service: _service,
              isGuest: true,
              onOpenTracking: () => setState(() => _index = 1),
              onOpenEvacuation: () => setState(() => _index = 2),
            ),
            ReportTrackingScreen(service: _service),
            EvacuationCentersScreen(service: _service, active: _index == 2),
          ]
        : [
            _ReporterDashboardTab(
              service: _service,
              session: widget.session,
              onNavigateToTab: (i) => setState(() => _index = i),
            ),
            ReportSubmitScreen(
              service: _service,
              onOpenTracking: () => setState(() => _index = 2),
              onOpenEvacuation: () => setState(() => _index = 3),
            ),
            ReportTrackingScreen(service: _service),
            EvacuationCentersScreen(service: _service, active: _index == 3),
          ];

    return Scaffold(
      // Same place as the website's preparedness widget toggle, which sits on
      // every reporter page (guest or signed in) — see chatbot/popup.blade.php.
      floatingActionButton: const _PreparednessButton(),
      body: AtmosphericBackground(
        child: SafeArea(
          child: Stack(
            children: [
              AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: pages[_index]),
              Positioned(
                top: 4,
                right: 16,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(side: BorderSide(color: RapidAlertColors.border)),
                  elevation: 0,
                  child: IconButton(
                    icon: Icon(
                      widget.isGuest ? Icons.person_add_alt_1_rounded : Icons.settings_outlined,
                      size: 20,
                      color: RapidAlertColors.darkText,
                    ),
                    tooltip: widget.isGuest ? 'Sign in or create an account' : 'Settings',
                    onPressed: widget.isGuest
                        ? widget.onLogout
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(session: widget.session, onLogout: widget.onLogout),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: RapidAlertColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (value) => setState(() => _index = value),
            backgroundColor: Colors.white,
            selectedItemColor: RapidAlertColors.primaryRed,
            unselectedItemColor: RapidAlertColors.lightText,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: widget.isGuest
                ? const [
                    BottomNavigationBarItem(icon: Icon(Icons.add_alert_rounded), label: 'Report'),
                    BottomNavigationBarItem(icon: Icon(Icons.track_changes_rounded), label: 'Track'),
                    BottomNavigationBarItem(icon: Icon(Icons.directions_run_rounded), label: 'Evacuate'),
                  ]
                : const [
                    BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
                    BottomNavigationBarItem(icon: Icon(Icons.add_alert_rounded), label: 'Report'),
                    BottomNavigationBarItem(icon: Icon(Icons.track_changes_rounded), label: 'Track'),
                    BottomNavigationBarItem(icon: Icon(Icons.directions_run_rounded), label: 'Evacuate'),
                  ],
          ),
        ),
      ),
    );
  }
}

/// The website's chatbot toggle: a 56px white circle showing the logo
/// (chatbot.css .ra-chatbot-toggle).
class _PreparednessButton extends StatelessWidget {
  const _PreparednessButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Preparedness assistant',
      child: Material(
        color: Colors.white,
        elevation: 0,
        shape: const CircleBorder(side: BorderSide(color: RapidAlertColors.border)),
        shadowColor: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showPreparednessAssistant(context),
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x1F0F172A), blurRadius: 20, offset: Offset(0, 8))],
            ),
            child: ClipOval(
              child: Image.asset('assets/images/rapid_alert_logo.png', width: 44, height: 44, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReporterDashboardTab extends StatefulWidget {
  const _ReporterDashboardTab({required this.service, required this.session, required this.onNavigateToTab});

  final ReporterService service;
  final UserSession? session;
  final ValueChanged<int> onNavigateToTab;

  @override
  State<_ReporterDashboardTab> createState() => _ReporterDashboardTabState();
}

class _ReporterDashboardTabState extends State<_ReporterDashboardTab> {
  CheckInStatus _status = CheckInStatus.safe;
  bool _updatingStatus = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  /// This tab's state is destroyed and rebuilt every time the shell
  /// switches away and back (AnimatedSwitcher, not IndexedStack), so
  /// without this the status would silently reset to "safe" on every
  /// return to Home regardless of what's actually persisted server-side.
  Future<void> _loadStatus() async {
    try {
      final status = await widget.service.loadCheckInStatus();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {
      // Keep the "safe" default on failure — best-effort, not worth
      // blocking the dashboard over.
    }
  }

  Future<void> _setStatus(CheckInStatus status) async {
    setState(() => _updatingStatus = true);
    try {
      final resolved = await widget.service.setCheckInStatus(status);
      if (!mounted) return;
      setState(() => _status = resolved);
      if (resolved == CheckInStatus.needHelp) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Need Help sent. CDRRMO dispatchers can now see that you need help.')),
        );
        widget.onNavigateToTab(2);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't update your status. Check your connection and try again."),
          action: SnackBarAction(label: 'Retry', onPressed: () => _setStatus(status)),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  /// Need Help alerts dispatchers (and may open a report), so it's confirmed
  /// first; switching back to "I'm Safe" isn't.
  Future<void> _confirmNeedHelp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send a Need Help alert?'),
        content: const Text(
          'This tells CDRRMO dispatchers that you need help now. It may also open an emergency '
          'report for your registered address so a responder can be assigned.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RapidAlertColors.primaryRed),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send Need Help'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _setStatus(CheckInStatus.needHelp);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Hi, ${session?.firstName.isNotEmpty == true ? session!.firstName : 'there'}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text('Report hazards and keep your safety status up to date.', style: TextStyle(color: RapidAlertColors.lightText)),
        const SizedBox(height: 20),
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your safety status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatusButton(
                      label: "I'm Safe",
                      icon: Icons.check_circle_outline_rounded,
                      color: RapidAlertColors.success,
                      selected: _status == CheckInStatus.safe,
                      onTap: _updatingStatus ? null : () => _setStatus(CheckInStatus.safe),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatusButton(
                      label: 'Need Help',
                      icon: Icons.warning_amber_rounded,
                      color: RapidAlertColors.primaryRed,
                      selected: _status == CheckInStatus.needHelp,
                      onTap: _updatingStatus || _status == CheckInStatus.needHelp ? null : _confirmNeedHelp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.add_alert_rounded, color: RapidAlertColors.primaryRed),
                title: const Text('Report a hazard'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => widget.onNavigateToTab(1),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.track_changes_rounded, color: RapidAlertColors.operationsBlue),
                title: const Text('Track my reports'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => widget.onNavigateToTab(2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : RapidAlertColors.border, width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
