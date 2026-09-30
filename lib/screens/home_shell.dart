import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/api_responder_service.dart';
import '../data/app_config.dart';
import '../data/auth_service.dart';
import '../data/mock_responder_service.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart' show AssignmentAlert;
import 'assigned_reports_screen.dart';
import 'chat_screen.dart';
import 'coordination_screen.dart';
import 'dashboard_screen.dart';
import 'map_tracking_screen.dart';
import 'settings_screen.dart';
import 'ui_components.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.session, this.onLogout});

  final UserSession? session;
  final VoidCallback? onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final ResponderService _service;
  StreamSubscription<AssignmentAlert>? _alertSub;
  int _index = 0;

  /// The report the Map tab should show, set by an assignment alert's View.
  String? _mapReportId;

  static const _mapTab = 2;

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    _service = (AppConfig.useApi && session != null)
        ? ApiResponderService(
            baseUrl: AppConfig.apiBaseUrl,
            bearerToken: session.token,
            responderUserId: session.responderUserId,
          )
        : MockResponderService();
    _alertSub = _service.assignmentAlerts.listen(_showAssignmentAlert);
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _service.dispose();
    super.dispose();
  }

  /// In-app only (no push): shows while the app is open. Banners queue, so
  /// two quick assignments are shown one after the other.
  void _showAssignmentAlert(AssignmentAlert alert) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: const Color(0xFFFEF2F2),
        leading: const Icon(Icons.assignment_ind_rounded, color: RapidAlertColors.primaryRed),
        content: Semantics(
          liveRegion: true,
          child: Text(alert.message, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        actions: [
          TextButton(onPressed: messenger.hideCurrentMaterialBanner, child: const Text('Dismiss')),
          FilledButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              setState(() {
                _mapReportId = alert.reportId;
                _index = _mapTab;
              });
            },
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        service: _service,
        onNavigateToTab: (index) => setState(() => _index = index),
      ),
      AssignedReportsScreen(service: _service),
      MapTrackingScreen(service: _service, initialReportId: _mapReportId),
      ChatScreen(service: _service),
      CoordinationScreen(service: _service),
    ];

    return Scaffold(
      body: AtmosphericBackground(
        child: SafeArea(
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: pages[_index],
              ),
              Positioned(
                top: 4,
                right: 16,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(side: BorderSide(color: RapidAlertColors.border)),
                  elevation: 0,
                  child: IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20, color: RapidAlertColors.darkText),
                    tooltip: 'Settings',
                    onPressed: () => Navigator.of(context).push(
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
            // A normal tab switch opens the map on its default report again.
            onTap: (value) => setState(() {
              _index = value;
              _mapReportId = null;
            }),
            backgroundColor: Colors.white,
            selectedItemColor: RapidAlertColors.primaryRed,
            unselectedItemColor: RapidAlertColors.lightText,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.assignment_rounded),
                label: 'Reports',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_rounded),
                label: 'Map',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_rounded),
                label: 'Chat',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.podcasts_rounded),
                label: 'Live',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
