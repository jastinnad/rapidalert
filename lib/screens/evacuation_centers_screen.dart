import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../data/osrm_route.dart';
import '../data/reporter_service.dart';
import '../models/reporter_models.dart';
import 'ui_components.dart';

/// Lipa City centroid — same fallback the website uses when browser/device
/// geolocation is unavailable or denied.
const _lipaFallback = LatLng(13.9411, 121.1634);

const _geofenceArrivalMeters = 100;

class EvacuationCentersScreen extends StatefulWidget {
  const EvacuationCentersScreen({super.key, required this.service, this.active = true});

  final ReporterService service;

  /// Whether this tab is currently the selected one. Location permission is
  /// only requested the first time this becomes true — the tab shell builds
  /// every page eagerly, so without this guard a reporter would see a
  /// location prompt the moment the app opens, before ever tapping Evacuate.
  final bool active;

  @override
  State<EvacuationCentersScreen> createState() => _EvacuationCentersScreenState();
}

class _EvacuationCentersScreenState extends State<EvacuationCentersScreen> {
  bool _started = false;

  bool _loadingPosition = true;
  String? _positionBanner;
  LatLng _position = _lipaFallback;

  EvacuationRankedResult? _result;
  bool _loadingCenters = false;
  String? _loadError;

  int? _selectedAreaId;
  bool _arrived = false;
  String? _geofenceError;
  StreamSubscription<Position>? _geofenceSub;
  Timer? _reroutePollTimer;
  String? _rerouteBanner;

  final _mapController = MapController();
  bool _mapReady = false;

  // Real road-following route to the selected (or best-ranked) center,
  // fetched from the same OSRM routing backend the website's evacuation
  // finder uses — falls back to a straight dashed line while loading or if
  // the routing request fails, matching the website's own fallback.
  List<LatLng>? _routePoints;
  int? _routedAreaId;
  LatLng? _routedFrom;
  int _routeRequestId = 0;

  @override
  void didUpdateWidget(covariant EvacuationCentersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_started) {
      _started = true;
      _acquireLocationAndLoad();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _started = true;
      _acquireLocationAndLoad();
    }
  }

  @override
  void dispose() {
    _geofenceSub?.cancel();
    _reroutePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _acquireLocationAndLoad() async {
    setState(() {
      _loadingPosition = true;
      _positionBanner = null;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are turned off.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _position = LatLng(position.latitude, position.longitude);
        _loadingPosition = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _position = _lipaFallback;
        _positionBanner = 'Location unavailable — showing centers near Lipa City.';
        _loadingPosition = false;
      });
    }

    await _loadCenters();
  }

  Future<void> _loadCenters() async {
    setState(() {
      _loadingCenters = true;
      _loadError = null;
    });
    try {
      final result = await widget.service.loadNearestEvacuationCenters(
        lat: _position.latitude,
        lon: _position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loadingCenters = false;
      });
      if (_mapReady) {
        _mapController.move(_position, 13);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load evacuation centers.';
        _loadingCenters = false;
      });
    }
  }

  void _startNavigation(EvacuationCenter center) async {
    _geofenceSub?.cancel();
    _reroutePollTimer?.cancel();

    setState(() {
      _selectedAreaId = center.areaId;
      _arrived = false;
      _geofenceError = null;
      _rerouteBanner = null;
    });

    final uri = Uri.parse(center.directionsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Maps app.')),
      );
    }

    _geofenceSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((pos) => _checkGeofence(pos, center));

    _reroutePollTimer = Timer.periodic(const Duration(seconds: 45), (_) => _reroutePoll(center));
  }

  Future<void> _checkGeofence(Position pos, EvacuationCenter center) async {
    final distanceMeters = Geolocator.distanceBetween(pos.latitude, pos.longitude, center.lat, center.lon);
    if (distanceMeters > _geofenceArrivalMeters) return;

    await _geofenceSub?.cancel();
    _geofenceSub = null;

    await _confirmArrival(center);
  }

  Future<void> _confirmArrival(EvacuationCenter center) async {
    try {
      await widget.service.confirmEvacuationArrival(areaId: center.areaId);
      if (!mounted) return;
      setState(() {
        _arrived = true;
        _geofenceError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Arrived at ${center.name} — check-in confirmed.")),
      );
      _reroutePollTimer?.cancel();
    } catch (e) {
      if (!mounted) return;
      setState(() => _geofenceError = 'Could not confirm check-in.');
    }
  }

  Future<void> _reroutePoll(EvacuationCenter selected) async {
    if (_arrived) {
      _reroutePollTimer?.cancel();
      return;
    }
    try {
      final result = await widget.service.loadNearestEvacuationCenters(
        lat: _position.latitude,
        lon: _position.longitude,
      );
      if (!mounted) return;
      final stillListed = result.centres.any((c) => c.areaId == selected.areaId && !c.isFull);
      setState(() {
        _result = result;
        _rerouteBanner = stillListed
            ? null
            : 'This center may now be full or unavailable — consider another option.';
      });
    } catch (_) {
      // Best-effort — keep the existing state on a failed poll.
    }
  }

  void _maybeFetchRoute(EvacuationCenter target) {
    final movedFar = _routedFrom != null &&
        const Distance().distance(_routedFrom!, _position) > 100;
    if (_routedAreaId == target.areaId && !movedFar) return;

    // Clear the stale route immediately (in this same build) so a switch to
    // a new center never shows the previous center's route mislabeled as
    // current — the fallback straight line takes over until this resolves.
    final requestId = ++_routeRequestId;
    _routedAreaId = target.areaId;
    _routedFrom = _position;
    _routePoints = null;
    fetchRoadRoute(_position, LatLng(target.lat, target.lon)).then((points) {
      // Ignore a response from a request a newer selection has superseded.
      if (!mounted || requestId != _routeRequestId) return;
      setState(() => _routePoints = points);
    });
  }

  int? _lastFitAreaId;
  bool _lastFitHadRoute = false;

  /// Reframes the map to the current route's full extent once per selection
  /// — and again once a fallback straight line upgrades to the real route —
  /// so switching centers doesn't leave the view zoomed into a shared local
  /// road segment that looks identical regardless of which center is picked.
  void _fitRouteOnce(EvacuationCenter target, List<LatLng>? roadRoute) {
    final hasRoute = roadRoute != null;
    if (_lastFitAreaId == target.areaId && _lastFitHadRoute == hasRoute) return;
    _lastFitAreaId = target.areaId;
    _lastFitHadRoute = hasRoute;

    final points = roadRoute ?? [_position, LatLng(target.lat, target.lon)];
    void fit() {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(32)),
      );
    }

    // flutter_map measures itself (emitting the *initial* camera) only after
    // its first frame; a fit before that leaves the tile layer loading the
    // stale view and the map grey until panned. Wait for the size event.
    if (_mapSized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fit());
    } else {
      _pendingFit = fit;
    }
  }

  bool _mapSized = false;
  VoidCallback? _pendingFit;

  void _onMapEvent(MapEvent event) {
    if (_mapSized || event is! MapEventNonRotatedSizeChange) return;
    _mapSized = true;
    final fit = _pendingFit;
    _pendingFit = null;
    if (fit != null) WidgetsBinding.instance.addPostFrameCallback((_) => fit());
  }

  @override
  Widget build(BuildContext context) {
    final showingMap = !(_loadingPosition || _loadingCenters) && _loadError == null;
    if (!showingMap) {
      // The map is removed while loading, so the next one must be measured
      // again before a fit.
      _mapSized = false;
      _mapReady = false;
    }

    return Scaffold(
      // A tab inside ReporterHomeShell, which paints the photo background.
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Nearest Evacuation Centers')),
      body: _loadingPosition || _loadingCenters
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _loadCenters, child: const Text('Retry')),
                ],
              ),
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final result = _result;
    final centres = result?.centres ?? const [];

    // Default to the top-ranked (nearest/best) center, matching the
    // website's self-rescue panel, until the reporter picks a different one
    // via "Get Directions".
    final routeTarget = centres.isEmpty
        ? null
        : centres.firstWhere((c) => c.areaId == _selectedAreaId, orElse: () => centres.first);
    if (routeTarget != null) {
      _maybeFetchRoute(routeTarget);
    }
    final routeColor = routeTarget != null ? _parseHexColor(routeTarget.statusColor) : RapidAlertColors.dispatchBlue;
    final roadRoute = routeTarget != null && _routedAreaId == routeTarget.areaId ? _routePoints : null;
    if (routeTarget != null) {
      _fitRouteOnce(routeTarget, roadRoute);
    }

    return Column(
      children: [
        if (result?.warning != null) _banner(result!.warning!, RapidAlertColors.warning),
        if (_positionBanner != null)
          _banner(_positionBanner!, RapidAlertColors.lightText, action: TextButton(
            onPressed: _acquireLocationAndLoad,
            child: const Text('Retry'),
          )),
        if (_rerouteBanner != null) _banner(_rerouteBanner!, RapidAlertColors.primaryRed),
        SizedBox(
          height: 260,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _position,
              initialZoom: 13,
              onMapReady: () => _mapReady = true,
              onMapEvent: _onMapEvent,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'site.rapidalert.app',
              ),
              if (routeTarget != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: roadRoute ?? [_position, LatLng(routeTarget.lat, routeTarget.lon)],
                      color: routeColor,
                      strokeWidth: roadRoute != null ? 4 : 3,
                      pattern: roadRoute != null
                          ? const StrokePattern.solid()
                          : StrokePattern.dashed(segments: const [10, 6]),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _position,
                    width: 24,
                    height: 24,
                    child: const Icon(Icons.my_location_rounded, color: RapidAlertColors.dispatchBlue),
                  ),
                  ...centres.map(
                    (c) => Marker(
                      point: LatLng(c.lat, c.lon),
                      width: 32,
                      height: 32,
                      child: Tooltip(
                        message: '${c.name}\n${c.statusLabel}',
                        child: Icon(Icons.location_on_rounded, color: _parseHexColor(c.statusColor), size: 32),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _acquireLocationAndLoad,
            child: centres.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No evacuation centers are currently available near you. Contact local authorities for guidance.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: RapidAlertColors.lightText),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    // Extra bottom space so the preparedness button never
                    // covers the last center's Get Directions button.
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: centres.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _centerCard(centres[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _banner(String text, Color color, {Widget? action}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          ?action,
        ],
      ),
    );
  }

  Widget _centerCard(EvacuationCenter center) {
    final isSelected = _selectedAreaId == center.areaId;
    final statusColor = _parseHexColor(center.statusColor);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(center.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  center.statusLabel,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${center.distanceKm.toStringAsFixed(1)} km · ${center.etaMinutes} min'
            '${center.isGrey ? ' · Capacity unknown' : ' · ${center.availableSlots}/${center.capacity} slots'}',
            style: const TextStyle(color: RapidAlertColors.lightText, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _startNavigation(center),
              icon: const Icon(Icons.directions_rounded),
              label: const Text('Get Directions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: RapidAlertColors.operationsBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (isSelected) ...[
            const SizedBox(height: 8),
            Text(
              _geofenceError ??
                  (_arrived
                      ? 'Arrived — check-in confirmed.'
                      : 'Monitoring your location — will confirm arrival within ${_geofenceArrivalMeters}m. Keep the app open to auto-confirm.'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _geofenceError != null
                    ? RapidAlertColors.primaryRed
                    : _arrived
                    ? RapidAlertColors.success
                    : RapidAlertColors.lightText,
              ),
            ),
            if (_geofenceError != null)
              TextButton(
                onPressed: () => _confirmArrival(center),
                child: const Text('Retry check-in'),
              ),
          ],
        ],
      ),
    );
  }

  Color _parseHexColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16) ?? 0x9ca3af;
    return Color(0xFF000000 | value);
  }
}
