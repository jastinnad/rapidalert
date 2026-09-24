import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key, required this.service});

  final ResponderService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: StreamBuilder<List<Announcement>>(
        stream: service.announcementsStream,
        initialData: service.announcements,
        builder: (context, snapshot) {
          final announcements = snapshot.data ?? const <Announcement>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const ScreenHeader(
                title: 'Announcements',
                subtitle: 'Broadcasts and advisories from admin, most recent first.',
              ),
              const SizedBox(height: 16),
              if (announcements.isEmpty)
                const GlassCard(child: Text('No announcements yet.'))
              else
                ...announcements.map(
                  (announcement) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AnnouncementCard(announcement: announcement),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final color = switch (announcement.priority) {
      AnnouncementPriority.high => RapidAlertColors.primaryRed,
      AnnouncementPriority.normal => RapidAlertColors.operationsBlue,
      AnnouncementPriority.low => RapidAlertColors.lightText,
    };

    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 44,
            margin: const EdgeInsets.only(top: 2, right: 12),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        announcement.title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (announcement.hazardType.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          announcement.hazardType,
                          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(announcement.message, style: const TextStyle(fontSize: 13.5)),
                const SizedBox(height: 8),
                Text(
                  announcement.publishedAgo,
                  style: const TextStyle(fontSize: 11.5, color: RapidAlertColors.lightText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
