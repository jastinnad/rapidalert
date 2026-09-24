import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'announcements_screen.dart';
import 'evacuation_tracker_screen.dart';
import 'follow_up_board_screen.dart';
import 'resources_screen.dart';
import 'ui_components.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.service, required this.onNavigateToTab});

  final ResponderService service;
  final ValueChanged<int> onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<IncidentReport>>(
      stream: service.reportsStream,
      initialData: service.reports,
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <IncidentReport>[];
        final assigned = reports.length;
        final openCases = reports
            .where((r) => r.status != ReportStatus.completed)
            .length;
        final needHelp = reports.where((r) => r.needHelp).length;

        return StreamBuilder<List<EvacuationRecordEntry>>(
          stream: service.evacuationRecordsStream,
          initialData: service.evacuationRecords,
          builder: (context, evacSnapshot) {
            final activeCenters = (evacSnapshot.data ?? const <EvacuationRecordEntry>[])
                .where((e) => e.status != EvacStatus.completed)
                .map((e) => e.centerName)
                .toSet()
                .length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                const ScreenHeader(
                  title: 'Rapid Alert Console',
                  subtitle:
                      'Command view for validating reports, dispatching response, and coordinating evacuation support.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _summaryCard(
                      context,
                      title: 'Assigned Reports',
                      value: assigned.toString(),
                      color: RapidAlertColors.primaryRed,
                    ),
                    _summaryCard(
                      context,
                      title: 'Open Cases',
                      value: openCases.toString(),
                      color: RapidAlertColors.operationsBlue,
                    ),
                    _summaryCard(
                      context,
                      title: 'Need Help',
                      value: needHelp.toString(),
                      color: RapidAlertColors.warning,
                    ),
                    _summaryCard(
                      context,
                      title: 'Active Centers',
                      value: activeCenters.toString(),
                      color: RapidAlertColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Responder Modules',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                      _ModuleRow(
                        'Track Assigned Reports',
                        Icons.assignment_rounded,
                        onTap: () => onNavigateToTab(1),
                      ),
                      _ModuleRow(
                        'Map Responder to Reporter',
                        Icons.map_rounded,
                        onTap: () => onNavigateToTab(2),
                      ),
                      _ModuleRow(
                        'Responder Chat to Reporter',
                        Icons.chat_rounded,
                        onTap: () => onNavigateToTab(3),
                      ),
                      _ModuleRow(
                        'Real-Time Coordination',
                        Icons.podcasts_rounded,
                        onTap: () => onNavigateToTab(4),
                      ),
                      _ModuleRow(
                        'Follow-Up Board',
                        Icons.event_note_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => FollowUpBoardScreen(service: service)),
                        ),
                      ),
                      _ModuleRow(
                        'Evacuation Tracker',
                        Icons.home_work_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => EvacuationTrackerScreen(service: service)),
                        ),
                      ),
                      _ModuleRow(
                        'Announcements',
                        Icons.campaign_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => AnnouncementsScreen(service: service)),
                        ),
                      ),
                      _ModuleRow(
                        'Resources',
                        Icons.inventory_2_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ResourcesScreen(service: service)),
                        ),
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _summaryCard(
    BuildContext context, {
    required String title,
    required String value,
    required Color color,
  }) {
    final width = (MediaQuery.of(context).size.width - 44) / 2;
    return SizedBox(
      width: width,
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: RapidAlertColors.lightText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow(this.text, this.icon, {required this.onTap, this.isLast = false});

  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: RapidAlertColors.border)),
        ),
        child: Row(
          children: [
            Icon(icon, color: RapidAlertColors.operationsBlue, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            const Icon(Icons.chevron_right_rounded, color: RapidAlertColors.lightText, size: 20),
          ],
        ),
      ),
    );
  }
}
