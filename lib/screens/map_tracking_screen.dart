import 'dart:math';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/responder_service.dart';
import '../models/responder_models.dart';
import 'ui_components.dart';

class MapTrackingScreen extends StatefulWidget {
  const MapTrackingScreen({super.key, required this.service});

  final ResponderService service;

  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen> {
  String? _selectedReportId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<IncidentReport>>(
      stream: widget.service.reportsStream,
      initialData: widget.service.reports,
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <IncidentReport>[];
        final selected = reports.firstWhere(
          (r) => r.id == _selectedReportId,
          orElse: () => reports.isNotEmpty ? reports.first : _emptyReport,
        );

        return StreamBuilder<GeoPoint>(
          stream: widget.service.responderTrackingStream,
          initialData: widget.service.currentResponderPoint,
          builder: (context, trackingSnapshot) {
            final responder =
                trackingSnapshot.data ??
                const GeoPoint(lat: 13.9412, lng: 121.1631);
            final distanceKm = _distanceKm(
              responder.lat,
              responder.lng,
              selected.reporterLat,
              selected.reporterLng,
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                const ScreenHeader(
                  title: 'Map Responder to Reporter',
                  subtitle: 'Live responder tracking and route estimation to reporter location.',
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assigned Incident',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        isExpanded: true,
                        value:
                            _selectedReportId ??
                            (reports.isNotEmpty ? reports.first.id : null),
                        items: reports
                            .map(
                              (r) => DropdownMenuItem(
                                value: r.id,
                                child: Text('${r.id} - ${r.location}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedReportId = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(0),
                  child: SizedBox(
                    height: 260,
                    child: CustomPaint(
                      painter: _RoutePainter(
                        responder: responder,
                        reporter: GeoPoint(
                          lat: selected.reporterLat,
                          lng: selected.reporterLng,
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Simulated Tactical Map',
                          style: TextStyle(
                            color: RapidAlertColors.lightText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.id,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Reporter: ${selected.reporterName}'),
                      Text('Location: ${selected.location}'),
                      const SizedBox(height: 8),
                      Text(
                        'Responder -> Reporter Distance: ${distanceKm.toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

  static final _emptyReport = IncidentReport(
    id: 'N/A',
    hazard: 'N/A',
    location: 'No report',
    reporterName: 'N/A',
    status: ReportStatus.assigned,
    needHelp: false,
    updated: DateTime.fromMillisecondsSinceEpoch(0),
    reporterLat: 13.9412,
    reporterLng: 121.1631,
  );

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({required this.responder, required this.reporter});

  final GeoPoint responder;
  final GeoPoint reporter;

  @override
  void paint(Canvas canvas, Size size) {
    final mapPaint = Paint()..color = const Color(0xFFF2F5FC);
    canvas.drawRect(Offset.zero & size, mapPaint);

    final gridPaint = Paint()
      ..color = const Color(0x15000000)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final responderOffset = Offset(size.width * 0.25, size.height * 0.70);
    final reporterOffset = Offset(size.width * 0.73, size.height * 0.35);

    final routePaint = Paint()
      ..color = RapidAlertColors.operationsBlue
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(responderOffset, reporterOffset, routePaint);

    final responderPaint = Paint()..color = RapidAlertColors.success;
    final reporterPaint = Paint()..color = RapidAlertColors.primaryRed;

    canvas.drawCircle(responderOffset, 10, responderPaint);
    canvas.drawCircle(reporterOffset, 10, reporterPaint);

    final ripplePaint = Paint()
      ..color = RapidAlertColors.primaryRed.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(reporterOffset, 20, ripplePaint);
    canvas.drawCircle(reporterOffset, 30, ripplePaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) {
    return oldDelegate.responder != responder ||
        oldDelegate.reporter != reporter;
  }
}
