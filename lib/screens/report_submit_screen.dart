import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../app/theme.dart';
import '../data/app_config.dart';
import '../data/location_catalog_service.dart';
import '../data/report_submission_ids.dart';
import '../data/reporter_service.dart';
import '../models/reporter_models.dart';

const List<(String value, String label)> _immediateNeedsOptions = [
  ('medical_assistance', 'Medical Assistance'),
  ('food_water', 'Food & Water'),
  ('shelter_repair_materials', 'Shelter repair materials'),
  ('electricity_restoration', 'Electricity restoration'),
  ('communication_services', 'Communication services'),
  ('rescue', 'Rescue assistance'),
];

const _retrySameReport =
    "Tap Submit Report again without changing anything. Resubmitting the same report is safe and won't create a duplicate.";

/// What to tell the user after a report went through, shown next to the
/// Submit button (and in the confirmation dialog).
String reportSubmitSuccessMessage(ReportSubmitResult result) {
  if (result.replayed) {
    return 'Report received. Your earlier attempt had already reached Rapid Alert, so no duplicate was created. Tracking ID: ${result.trackingId}';
  }
  if (result.duplicate) {
    return 'Report received. It matches an active report you just sent, so it was added to that report. Tracking ID: ${result.trackingId}';
  }
  return 'Report submitted. Tracking ID: ${result.trackingId}';
}

/// What to tell the user when nothing was sent because the report was
/// changed after an attempt that had, it turns out, already been stored.
String reportEarlierAttemptStoredMessage(List<String> notAdded, {String? trackingId}) =>
    'Your original report was already stored before you changed it'
    '${trackingId == null || trackingId.isEmpty ? ' (see Track)' : ' (Tracking ID: $trackingId)'}. '
    'These changes were NOT added: ${notAdded.join(', ')}. '
    'Nothing new was sent. Your changes are still in the form: tap Submit Report to send them as a new report.';

/// What to tell the user when a report didn't go through: whether it was
/// sent, and whether tapping Submit again is safe.
String reportSubmitErrorMessage(Object error) {
  if (error is EarlierAttemptCheckFailed) {
    return "Not sent: you changed this report after an attempt that may already have reached Rapid Alert, and Rapid Alert couldn't be reached to check. "
        'Nothing was sent. Tap Submit Report again when you have a connection.';
  }
  if (error is! ReportSubmitException) {
    return 'Not confirmed: your report may not have been sent. $_retrySameReport';
  }

  // With no response, or a server error, the report may or may not have
  // been stored; resending the same report is safe either way.
  final serverMessage = error.serverMessage?.trim();
  return switch (error.statusCode) {
    null =>
      "Not confirmed: Rapid Alert couldn't be reached, so your report may not have been sent. Check your connection. $_retrySameReport",
    401 => 'Not sent: your session has expired. Sign in again, then submit your report.',
    409 => 'Not sent: this submission ID was already used by another report. Tap Submit Report to send it as a new report.',
    422 =>
      'Not sent: ${serverMessage == null || serverMessage.isEmpty ? 'some details are missing or invalid.' : serverMessage} Correct this, then tap Submit Report again.',
    429 => 'Not sent: too many reports in a short time. Wait a minute, then tap Submit Report again.',
    final code =>
      'Not confirmed: the server had a problem (error $code), so your report may not have been sent. $_retrySameReport',
  };
}

class ReportSubmitScreen extends StatefulWidget {
  const ReportSubmitScreen({super.key, required this.service, this.isGuest = false, this.submissionIds});

  final ReporterService service;

  /// Per-report `client_report_id`s; defaults to the device's secure storage.
  final ReportSubmissionIds? submissionIds;

  /// When true, shows a required phone field — the backend requires a
  /// contact number for reports submitted without an account.
  final bool isGuest;

  @override
  State<ReportSubmitScreen> createState() => _ReportSubmitScreenState();
}

class _ReportSubmitScreenState extends State<ReportSubmitScreen> {
  List<HazardOption> _options = const [];
  CurrentSituationConfig _situationConfig = CurrentSituationConfig.empty;
  RapidAssessmentPrefill? _rapidAssessment;
  bool _loadingOptions = true;
  String? _loadError;

  String? _selectedHazardType;
  String? _selectedParticular;
  String? _selectedColor;
  String? _selectedDetail;
  final Set<String> _selectedSituations = {};
  final Set<String> _selectedNeeds = {};

  List<String> _barangayOptions = const [];
  String? _selectedBarangay;
  bool _loadingBarangays = true;
  String? _barangayLoadError;

  final _purokController = TextEditingController();
  final _houseNoController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _phoneController = TextEditingController();
  final _regionController = TextEditingController(text: 'Region IV-A');
  final _provinceController = TextEditingController(text: 'Batangas');
  final _cityController = TextEditingController(text: 'Lipa City');

  int _pregnantCount = 0;
  int _elderlyCount = 0;
  int _childCount = 0;
  int _pwdCount = 0;
  bool _needHelp = false;

  double? _latitude;
  double? _longitude;
  bool _capturingLocation = false;

  XFile? _pickedImage;
  final _picker = ImagePicker();
  late final _submissionIds = widget.submissionIds ?? ReportSubmissionIds();

  bool _submitting = false;
  /// Outcome of the last submit, shown next to the Submit button.
  ({_SubmitStatus kind, String text})? _submitStatus;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _loadBarangays();
  }

  @override
  void dispose() {
    _purokController.dispose();
    _houseNoController.dispose();
    _landmarkController.dispose();
    _phoneController.dispose();
    _regionController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _loadError = null;
    });
    try {
      final formOptions = await widget.service.loadHazardOptions();
      if (!mounted) return;
      setState(() {
        _options = formOptions.hazardOptions;
        _situationConfig = formOptions.situationConfig;
        _rapidAssessment = formOptions.rapidAssessment;
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load hazard types. Pull to retry.';
        _loadingOptions = false;
      });
    }
  }

  Future<void> _loadBarangays() async {
    setState(() {
      _loadingBarangays = true;
      _barangayLoadError = null;
    });
    try {
      final barangays = await LocationCatalogService.loadLipaBarangays(AppConfig.apiBaseUrl);
      if (!mounted) return;
      setState(() {
        _barangayOptions = barangays;
        _loadingBarangays = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _barangayLoadError = 'Failed to load barangays.';
        _loadingBarangays = false;
      });
    }
  }

  static const _colorPriority = ['green', 'orange', 'red'];

  List<String> get _hazardTypes => _options.map((o) => o.hazardType).toSet().toList();

  List<String> get _particularOptions =>
      _options.where((o) => o.hazardType == _selectedHazardType).map((o) => o.particular).toSet().toList();

  List<String> get _colorOptions {
    final present = _options
        .where((o) => o.hazardType == _selectedHazardType && o.particular == _selectedParticular)
        .map((o) => o.particularColor)
        .toSet();
    return _colorPriority.where(present.contains).toList();
  }

  List<String> get _detailOptions => _options
      .where(
        (o) =>
            o.hazardType == _selectedHazardType &&
            o.particular == _selectedParticular &&
            o.particularColor == _selectedColor,
      )
      .map((o) => o.particularDetail)
      .toSet()
      .toList();

  /// The fully-resolved catalog entry once all four cascading dropdowns
  /// (hazard type -> category -> severity -> details) are picked — mirrors
  /// the web form's hazard_type/particular/particular_color/particular_detail
  /// selection, just as separate sequential dropdowns instead of one long
  /// scrolling list.
  HazardOption? get _selectedOption {
    final hazardType = _selectedHazardType;
    final particular = _selectedParticular;
    final color = _selectedColor;
    final detail = _selectedDetail;
    if (hazardType == null || particular == null || color == null || detail == null) return null;

    for (final option in _options) {
      if (option.hazardType == hazardType &&
          option.particular == particular &&
          option.particularColor == color &&
          option.particularDetail == detail) {
        return option;
      }
    }
    return null;
  }

  List<String> get _currentSituationOptions {
    final option = _selectedOption;
    if (option == null) return _situationConfig.defaultSet;
    return _situationConfig.situationsFor(
      hazardType: option.hazardType,
      color: option.particularColor,
      detail: option.particularDetail,
    );
  }

  void _applyRapidAssessment() {
    final assessment = _rapidAssessment;
    if (assessment == null) return;

    HazardOption? match = _firstOrNull(
      _options.where(
        (o) =>
            o.hazardType == assessment.hazardType &&
            o.particular == assessment.particular &&
            o.particularColor == assessment.particularColor &&
            o.particularDetail == assessment.particularDetail,
      ),
    );

    match ??= _firstOrNull(
      _options.where(
        (o) =>
            o.hazardType == assessment.hazardType &&
            o.particular == assessment.particular &&
            o.particularColor == assessment.particularColor,
      ),
    );

    if (match == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('That hazard option is no longer available.')));
      return;
    }

    setState(() {
      _selectedHazardType = match!.hazardType;
      _selectedParticular = match.particular;
      _selectedColor = match.particularColor;
      _selectedDetail = match.particularDetail;
      _selectedSituations.addAll(assessment.currentSituation.where(_situationConfig.labels.containsKey));
    });
  }

  Future<void> _captureLocation() async {
    setState(() => _capturingLocation = true);
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
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get location: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _capturingLocation = false);
    }
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
    if (image != null && mounted) {
      setState(() => _pickedImage = image);
    }
  }

  Future<void> _pickImageFromGallery() async {
    final image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    if (image != null && mounted) {
      setState(() => _pickedImage = image);
    }
  }

  bool get _canSubmit =>
      !_submitting &&
      _selectedOption != null &&
      _selectedBarangay != null &&
      _purokController.text.trim().isNotEmpty &&
      _houseNoController.text.trim().isNotEmpty &&
      (!widget.isGuest || RegExp(r'^\d{11}$').hasMatch(_phoneController.text.trim()));

  Future<void> _submit() async {
    final option = _selectedOption;
    if (option == null) return;

    setState(() {
      _submitting = true;
      _submitStatus = null;
    });

    final landmark = _landmarkController.text.trim();
    final phone = widget.isGuest ? _phoneController.text.trim() : null;
    // This attempt's contents by field label. They don't pick the
    // client_report_id (the draft has its own); they only show which fields
    // changed after an attempt that may already have been stored.
    final contents = <String, Object?>{
      'Hazard': [option.hazardType, option.particular, option.particularColor, option.particularDetail],
      'Area': [_regionController.text.trim(), _provinceController.text.trim(), _cityController.text.trim()],
      'Barangay': _selectedBarangay,
      'Purok': _purokController.text.trim(),
      'House number': _houseNoController.text.trim(),
      'Landmark': landmark,
      'GPS location': [_latitude, _longitude],
      'Vulnerable population': [_pregnantCount, _elderlyCount, _childCount, _pwdCount],
      'I need immediate help': _needHelp,
      'Immediate needs': _selectedNeeds.toList()..sort(),
      'Current situation': _selectedSituations.toList()..sort(),
      'Photo': _pickedImage?.path,
      'Contact number': phone,
    };

    try {
      final outcome = await _submissionIds.submit(
        contents,
        (clientReportId) => widget.service.submitReport(
          hazardType: option.hazardType,
          particular: option.particular,
          particularColor: option.particularColor,
          particularDetail: option.particularDetail,
          region: _regionController.text.trim(),
          province: _provinceController.text.trim(),
          city: _cityController.text.trim(),
          barangay: _selectedBarangay ?? '',
          purok: _purokController.text.trim(),
          houseNo: _houseNoController.text.trim(),
          landmark: landmark.isEmpty ? null : landmark,
          latitude: _latitude,
          longitude: _longitude,
          pregnantCount: _pregnantCount,
          elderlyCount: _elderlyCount,
          childCount: _childCount,
          pwdCount: _pwdCount,
          needHelp: _needHelp,
          needs: _selectedNeeds.toList(),
          currentSituation: _selectedSituations.toList(),
          imagePath: _pickedImage?.path,
          clientReportId: clientReportId,
          phone: phone,
        ),
        isStored: widget.service.submittedReportExists,
        // A guest's original is found by its client_report_id (the same
        // lookup as guest tracking); a signed-in reporter's is on the account.
        lookUpTrackingId: widget.isGuest
            ? (id) async => (await widget.service.trackReport(clientReportId: id))?.trackingId
            : null,
        trackingId: (result) => result.trackingId,
        // A report merged into an existing incident isn't stored under its
        // own ID, so guest tracking can't look it up by that ID.
        trackable: (result) => !result.duplicate,
      );

      if (!mounted) return;
      final result = outcome.result;
      final String title;
      final String message;
      if (result == null) {
        // Nothing was sent: the original, unchanged report is already stored.
        title = 'Original report already stored';
        message = reportEarlierAttemptStoredMessage(outcome.notAdded, trackingId: outcome.earlierTrackingId);
      } else {
        title = result.replayed || result.duplicate ? 'Report received' : 'Report submitted';
        message = reportSubmitSuccessMessage(result);
      }
      setState(() => _submitStatus = (kind: result == null ? _SubmitStatus.warning : _SubmitStatus.success, text: message));
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(result == null ? message : '$message\n\nSave this ID to track your report\'s status.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      // Keep changes that weren't stored, so they can be sent as a new
      // report (the draft is finished, so the next submit gets a new ID).
      if (result != null) _resetForm();
    } catch (e) {
      if (e is ReportSubmitException && e.statusCode == 409) {
        await _submissionIds.discardDraft();
      }
      if (!mounted) return;
      setState(() => _submitStatus = (kind: _SubmitStatus.error, text: reportSubmitErrorMessage(e)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetForm() {
    setState(() {
      _selectedHazardType = null;
      _selectedParticular = null;
      _selectedColor = null;
      _selectedDetail = null;
      _selectedSituations.clear();
      _selectedNeeds.clear();
      _selectedBarangay = null;
      _purokController.clear();
      _houseNoController.clear();
      _landmarkController.clear();
      _pregnantCount = 0;
      _elderlyCount = 0;
      _childCount = 0;
      _pwdCount = 0;
      _needHelp = false;
      _latitude = null;
      _longitude = null;
      _pickedImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A tab inside ReporterHomeShell, which paints the photo background.
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Report a Hazard')),
      body: _loadingOptions
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _loadOptions, child: const Text('Retry')),
                ],
              ),
            )
          : SingleChildScrollView(
              // Extra bottom space so the preparedness button never covers
              // the submit button at the end of the form.
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              child: _FormSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_rapidAssessment != null) ...[
                      OutlinedButton.icon(
                        onPressed: _applyRapidAssessment,
                        icon: const Icon(Icons.bolt_rounded),
                        label: const Text('Apply latest admin rapid assessment'),
                        style: OutlinedButton.styleFrom(foregroundColor: RapidAlertColors.operationsBlue),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _sectionLabel('Hazard type'),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedHazardType,
                      decoration: _fieldDecoration(),
                      hint: const Text('Select hazard type'),
                      items: _hazardTypes.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedHazardType = value;
                          _selectedParticular = null;
                          _selectedColor = null;
                          _selectedDetail = null;
                        });
                      },
                    ),
                    if (_selectedHazardType != null) ...[
                      const SizedBox(height: 14),
                      _sectionLabel('Category'),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedParticular,
                        decoration: _fieldDecoration(),
                        isExpanded: true,
                        hint: const Text('What is happening?'),
                        items: _particularOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                        onChanged: (value) => setState(() {
                          _selectedParticular = value;
                          _selectedColor = null;
                          _selectedDetail = null;
                        }),
                      ),
                    ],
                    if (_selectedParticular != null) ...[
                      const SizedBox(height: 14),
                      _sectionLabel('Severity'),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedColor,
                        decoration: _fieldDecoration(),
                        hint: const Text('Select severity'),
                        items: _colorOptions
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [_severityDot(c), const SizedBox(width: 8), Text(_severityLabel(c))],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          _selectedColor = value;
                          _selectedDetail = null;
                        }),
                      ),
                    ],
                    if (_selectedColor != null) ...[
                      const SizedBox(height: 14),
                      _sectionLabel('Details'),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedDetail,
                        decoration: _fieldDecoration(),
                        isExpanded: true,
                        hint: const Text('Select the closest description'),
                        items: _detailOptions
                            .map(
                              (d) => DropdownMenuItem(
                                value: d,
                                child: Text(d, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _selectedDetail = value),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_selectedOption != null) ...[
                      _sectionLabel('Current Situation'),
                      ..._currentSituationOptions.map(
                        (key) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selectedSituations.contains(key),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selectedSituations.add(key);
                            } else {
                              _selectedSituations.remove(key);
                            }
                          }),
                          title: Text(_situationConfig.labels[key] ?? key),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (widget.isGuest) ...[
                      _sectionLabel('Your contact number'),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setState(() {}),
                        decoration: _fieldDecoration(hint: '09XXXXXXXXX (11 digits, required)'),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _sectionLabel('Location'),
                    Row(
                      children: [
                        Expanded(child: _textField('House / block no.', _houseNoController)),
                        const SizedBox(width: 12),
                        Expanded(child: _textField('Purok', _purokController)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _loadingBarangays
                        ? const LinearProgressIndicator(minHeight: 2)
                        : _barangayLoadError != null
                        ? Row(
                            children: [
                              Expanded(
                                child: Text(_barangayLoadError!, style: const TextStyle(color: Color(0xFFB91C1C))),
                              ),
                              TextButton(onPressed: _loadBarangays, child: const Text('Retry')),
                            ],
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _selectedBarangay,
                            decoration: _fieldDecoration(hint: 'Barangay'),
                            isExpanded: true,
                            hint: const Text('Select barangay'),
                            items: _barangayOptions.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                            onChanged: (value) => setState(() => _selectedBarangay = value),
                          ),
                    const SizedBox(height: 10),
                    _textField('Landmark (optional)', _landmarkController),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _capturingLocation ? null : _captureLocation,
                      icon: _capturingLocation
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded),
                      label: Text(
                        _latitude != null
                            ? 'GPS captured (${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)})'
                            : 'Capture current GPS location',
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionLabel('Photo (optional)'),
                    if (_pickedImage != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(_pickedImage!.path), height: 160, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Camera'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickImageFromGallery,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Gallery'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _sectionLabel('Vulnerable population at this location'),
                    _counterRow('Pregnant', _pregnantCount, (v) => setState(() => _pregnantCount = v)),
                    _counterRow('Elderly', _elderlyCount, (v) => setState(() => _elderlyCount = v)),
                    _counterRow('Children', _childCount, (v) => setState(() => _childCount = v)),
                    _counterRow('PWD', _pwdCount, (v) => setState(() => _pwdCount = v)),
                    const SizedBox(height: 12),
                    _sectionLabel('Immediate Needs'),
                    ..._immediateNeedsOptions.map(
                      (option) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selectedNeeds.contains(option.$1),
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            _selectedNeeds.add(option.$1);
                          } else {
                            _selectedNeeds.remove(option.$1);
                          }
                        }),
                        title: Text(option.$2),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _needHelp,
                      onChanged: (v) => setState(() => _needHelp = v),
                      title: const Text('I need immediate help'),
                    ),
                    const SizedBox(height: 20),
                    // Right above the button, where the user's eyes are when
                    // they tap it — the top of this long form is off-screen.
                    if (_submitStatus case final status?) ...[
                      _SubmitStatusBanner(kind: status.kind, text: status.text),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _canSubmit ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: RapidAlertColors.primaryRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  T? _firstOrNull<T>(Iterable<T> items) {
    for (final item in items) {
      return item;
    }
    return null;
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
  );

  Widget _severityDot(String color) {
    final c = switch (color) {
      'red' => Colors.red,
      'orange' => Colors.orange,
      _ => Colors.green,
    };
    return CircleAvatar(radius: 6, backgroundColor: c);
  }

  String _severityLabel(String color) => color.isEmpty ? color : color[0].toUpperCase() + color.substring(1);

  Widget _textField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      decoration: _fieldDecoration(hint: label),
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: RapidAlertColors.border),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: RapidAlertColors.border),
      ),
    );
  }

  Widget _counterRow(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
          ),
          Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => onChanged(value + 1)),
        ],
      ),
    );
  }
}

enum _SubmitStatus { success, warning, error }

/// The outcome of the last submit, right above the Submit button: green when
/// the report went through, amber when nothing was sent because the original
/// was already stored before the user changed it, red when it didn't go
/// through (or isn't confirmed).
class _SubmitStatusBanner extends StatelessWidget {
  const _SubmitStatusBanner({required this.kind, required this.text});

  final _SubmitStatus kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, border, icon) = switch (kind) {
      _SubmitStatus.success => (const Color(0xFF15803D), const Color(0xFFF0FDF4), const Color(0xFFBBF7D0), Icons.check_circle_outline_rounded),
      _SubmitStatus.warning => (const Color(0xFFB45309), const Color(0xFFFFFBEB), const Color(0xFFFDE68A), Icons.info_outline_rounded),
      _SubmitStatus.error => (const Color(0xFFB91C1C), const Color(0xFFFFF5F5), const Color(0xFFFEE2E2), Icons.error_outline_rounded),
    };
    return Container(
      key: Key('report-submit-${kind.name}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: foreground))),
        ],
      ),
    );
  }
}

/// The website's report form card (public/css/report.css .form-section):
/// white, hairline border, 3px red top edge, radius 18.
class _FormSection extends StatelessWidget {
  const _FormSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFFAFDFF)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4DFEB)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ColoredBox(color: Color(0xFFD91F32), child: SizedBox(height: 3)),
            Padding(padding: const EdgeInsets.all(14), child: child),
          ],
        ),
      ),
    );
  }
}
