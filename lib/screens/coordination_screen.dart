import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/backend_features.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class CoordinationScreen extends StatelessWidget {
  const CoordinationScreen({super.key, required this.service});

  final ResponderService service;

  @override
  Widget build(BuildContext context) {
    if (!BackendFeatures.coordinationFeed) {
      return _unavailable();
    }

    return StreamBuilder<List<CoordinationEvent>>(
      stream: service.eventsStream,
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <CoordinationEvent>[];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const ScreenHeader(
              title: 'Real-Time Coordination',
              subtitle: 'Live operations stream for responder and admin coordination.',
            ),
            const SizedBox(height: 12),
            const GlassCard(
              child: Row(
                children: [
                  Icon(
                    Icons.podcasts_rounded,
                    color: RapidAlertColors.primaryRed,
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Text('Connected to live coordination feed.')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (events.isEmpty)
              const GlassCard(child: Text('Waiting for coordination events...'))
            else
              ...events.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 5),
                          decoration: BoxDecoration(
                            color: _priorityColor(event.priority),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(event.message),
                              const SizedBox(height: 6),
                              Text(
                                DateFormat(
                                  'MMM d, h:mm:ss a',
                                ).format(event.time),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: RapidAlertColors.lightText,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Shown while production has no coordination-events endpoint, instead of
  /// a "connected" banner over a feed that can never receive anything.
  Widget _unavailable() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: const [
        ScreenHeader(
          title: 'Real-Time Coordination',
          subtitle: 'Live operations stream for responder and admin coordination.',
        ),
        SizedBox(height: 12),
        GlassCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: RapidAlertColors.operationsBlue),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live coordination is not available yet',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Your assigned reports and their status changes are in the Reports tab, '
                      'and messages from reporters are in the Chat tab.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _priorityColor(CoordinationPriority priority) {
    return switch (priority) {
      CoordinationPriority.normal => RapidAlertColors.operationsBlue,
      CoordinationPriority.important => RapidAlertColors.success,
      CoordinationPriority.urgent => RapidAlertColors.warning,
      CoordinationPriority.critical => RapidAlertColors.primaryRed,
    };
  }
}
