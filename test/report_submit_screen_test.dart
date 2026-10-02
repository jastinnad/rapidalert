import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rapidalert/data/report_submission_ids.dart';
import 'package:rapidalert/data/reporter_service.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/screens/report_submit_screen.dart';

/// A small hazard catalogue: Flood/Water has all three colors, Fire/Smoke
/// only red.
const _catalogue = [
  HazardOption(hazardType: 'Flood', particular: 'Water', particularColor: 'green', particularDetail: 'Ankle deep'),
  HazardOption(hazardType: 'Flood', particular: 'Water', particularColor: 'orange', particularDetail: 'Knee deep'),
  HazardOption(hazardType: 'Flood', particular: 'Water', particularColor: 'red', particularDetail: 'Waist deep'),
  HazardOption(hazardType: 'Fire', particular: 'Smoke', particularColor: 'red', particularDetail: 'Thick smoke'),
];

class _Service extends Fake implements ReporterService {
  Map<String, Object?>? submitted;

  @override
  Future<ReportFormOptions> loadHazardOptions() async => const ReportFormOptions(
    hazardOptions: _catalogue,
    situationConfig: CurrentSituationConfig.empty,
    rapidAssessment: null,
  );

  @override
  Future<bool> submittedReportExists(String clientReportId) async => false;

  @override
  Future<TrackedReport?> trackReport({String? trackingId, String? clientReportId}) async => null;

  @override
  Future<ReportSubmitResult> submitReport({
    required String hazardType,
    required String particular,
    required String particularColor,
    required String particularDetail,
    required String region,
    required String province,
    required String city,
    required String barangay,
    required String purok,
    required String houseNo,
    String? landmark,
    double? latitude,
    double? longitude,
    int pregnantCount = 0,
    int elderlyCount = 0,
    int childCount = 0,
    int pwdCount = 0,
    bool needHelp = false,
    List<String> needs = const [],
    List<String> currentSituation = const [],
    String? imagePath,
    String? clientReportId,
    String? phone,
    String? alternateContact,
    String? reporterName,
    String? reporterEmail,
  }) async {
    submitted = {
      'hazardType': hazardType,
      'particular': particular,
      'particularColor': particularColor,
      'particularDetail': particularDetail,
      'city': city,
      'barangay': barangay,
      'purok': purok,
      'houseNo': houseNo,
      'pregnantCount': pregnantCount,
      'needHelp': needHelp,
      'needs': needs,
      'imagePath': imagePath,
      'clientReportId': clientReportId,
      'phone': phone,
      'alternateContact': alternateContact,
      'reporterName': reporterName,
      'reporterEmail': reporterEmail,
    };
    return const ReportSubmitResult(trackingId: 'RA-20261002-TEST01', message: 'ok', duplicate: false);
  }
}

/// The public PSGC lookups behind the Lipa barangay list.
final _psgc = MockClient((request) async {
  final body = switch (request.url.path) {
    '/api/psgc/regions' => {
      'regions': [
        {'psgc_code': '0400000000', 'name': 'CALABARZON'},
      ],
    },
    '/api/psgc/provinces/0400000000' => {
      'provinces': [
        {'psgc_code': '0401000000', 'name': 'Batangas'},
      ],
    },
    '/api/psgc/municipalities/0401000000' => {
      'municipalities': [
        {'psgc_code': '0401014000', 'name': 'City of Lipa'},
      ],
    },
    '/api/psgc/barangays/0401014000' => {
      'barangays': [
        {'psgc_code': '0401014030', 'name': 'Marauoy'},
      ],
    },
    _ => <String, Object>{},
  };
  return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
});

Future<_Service> _pump(WidgetTester tester, {bool isGuest = true}) async {
  tester.view.physicalSize = const Size(900, 5200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final service = _Service();
  await http.runWithClient(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportSubmitScreen(
          service: service,
          isGuest: isGuest,
          submissionIds: ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => 'device-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }, () => _psgc);
  return service;
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

Future<void> _pickDropdown(WidgetTester tester, Finder dropdown, String option) async {
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Finder _dropdownWithHint(String hint) =>
    find.ancestor(of: find.text(hint), matching: find.byType(DropdownButtonFormField<String>));

Future<void> _chooseHazard(WidgetTester tester, {String color = 'orange', String detail = 'Knee deep'}) async {
  await tester.tap(find.byKey(Key('report-color-$color')));
  await tester.pumpAndSettle();
  await _pickDropdown(tester, _dropdownWithHint('Select hazard type...'), 'Flood');
  await _pickDropdown(tester, _dropdownWithHint('Select particular...'), 'Water');
  await _pickDropdown(tester, _dropdownWithHint('Choose detail...'), detail);
}

Future<void> _fillLocation(WidgetTester tester) async {
  await _pickDropdown(tester, _dropdownWithHint('Select Barangay'), 'Marauoy');
  await tester.enterText(find.widgetWithText(TextField, 'Purok'), 'Purok 4');
  await tester.enterText(find.widgetWithText(TextField, 'House No.'), '12');
  await tester.pump();
}

TextField _field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key)));

bool _canSubmit(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Submit Report')).onPressed != null;

void main() {
  group('Report form layout', () {
    testWidgets('sections follow the website order, with Color above Hazard Type', (tester) async {
      await _pump(tester);

      final order = [
        'report-section-assessment',
        'report-section-location',
        'report-section-personal',
        'report-section-needs',
        'report-section-priority',
        'report-section-photo',
        'report-section-consent',
        'report-section-submit',
      ].map((key) => _top(tester, find.byKey(Key(key)))).toList();
      expect(order, [...order]..sort(), reason: 'sections in website order');

      expect(_top(tester, find.text('Color')), lessThan(_top(tester, find.text('Hazard Type'))));
      for (final title in ['Rapid Assessment', 'Location Information', 'Personal Information', 'Immediate Needs',
          'Priority Persons', 'Emergency Photo (Optional)', 'Consent']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Need Help (Urgent follow-up requested)'), findsOneWidget);
      for (final person in ['Pregnant', 'Elderly', 'Child', 'PWD']) {
        expect(find.text(person), findsOneWidget);
      }
    });

    testWidgets('severity uses the website legend labels', (tester) async {
      await _pump(tester);

      expect(find.text('GREEN — GOOD'), findsOneWidget);
      expect(find.text('ORANGE — MODERATE'), findsOneWidget);
      expect(find.text('RED — CRITICAL'), findsOneWidget);
    });

    testWidgets('the consent notice is the website text', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('report-consent-notice')), findsOneWidget);
      expect(find.text(reportConsentNotice), findsOneWidget);
      expect(reportConsentNotice, contains('retained for two (2) weeks only'));
      expect(find.byType(Checkbox).evaluate().length, greaterThan(0)); // needs/need-help only
      expect(find.widgetWithText(CheckboxListTile, 'I agree'), findsNothing); // no new consent checkbox
    });
  });

  group('Hazard catalogue', () {
    testWidgets('choosing a color first does not narrow hazard types or particulars', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('report-color-green')));
      await tester.pumpAndSettle();
      await tester.tap(_dropdownWithHint('Select hazard type...'));
      await tester.pumpAndSettle();
      expect(find.text('Flood'), findsWidgets);
      expect(find.text('Fire'), findsWidgets, reason: 'Fire has no green option but is still listed');
      await tester.tap(find.text('Fire').last);
      await tester.pumpAndSettle();
      await _pickDropdown(tester, _dropdownWithHint('Select particular...'), 'Smoke');

      // The website's Color options for Fire/Smoke: red only.
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('report-color-green'))).selected, isFalse);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('report-color-green'))).onSelected, isNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('report-color-red'))).onSelected, isNotNull);
      expect(find.text('Choose a color available for this particular.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-color-red')));
      await tester.pumpAndSettle();
      await _pickDropdown(tester, _dropdownWithHint('Choose detail...'), 'Thick smoke');
      expect(find.text('Thick smoke'), findsOneWidget);
    });
  });

  group('Contact numbers', () {
    testWidgets('primary contact keeps digits only and stops at 11', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byKey(const Key('report-phone')), '0917-ABC-123 45678999');
      await tester.pump();
      expect(_field(tester, 'report-phone').controller!.text, '09171234567');

      await tester.enterText(find.byKey(const Key('report-phone')), '091712345678901');
      await tester.pump();
      expect(_field(tester, 'report-phone').controller!.text, '09171234567');
    });

    testWidgets('alternate contact follows the same rules and blocks submit until valid', (tester) async {
      await _pump(tester);
      await _chooseHazard(tester);
      await _fillLocation(tester);
      await tester.enterText(find.byKey(const Key('report-phone')), '09171234567');
      await tester.pump();
      expect(_canSubmit(tester), isTrue);

      await tester.enterText(find.byKey(const Key('report-alternate-contact')), 'x09+18 765 43210 99');
      await tester.pump();
      expect(_field(tester, 'report-alternate-contact').controller!.text, '09187654321');
      expect(_canSubmit(tester), isTrue);

      await tester.enterText(find.byKey(const Key('report-alternate-contact')), '0918');
      await tester.pump();
      expect(find.text('Enter 11 digits (09XXXXXXXXX), or leave it blank.'), findsOneWidget);
      expect(_canSubmit(tester), isFalse);
    });

    test('the contact rule matches the website and server: exactly 11 digits', () {
      expect(isValidContactNumber('09171234567'), isTrue);
      expect(isValidContactNumber('0917123456'), isFalse);
      expect(isValidContactNumber('091712345678'), isFalse);
      expect(isValidContactNumber('0917-123456'), isFalse);
    });
  });

  group('Submission', () {
    testWidgets('a guest report sends the website fields, including the optional contact details', (tester) async {
      final service = await _pump(tester);
      await _chooseHazard(tester);
      await _fillLocation(tester);
      await tester.enterText(find.byKey(const Key('report-phone')), '09171234567');
      await tester.enterText(find.byKey(const Key('report-alternate-contact')), '09187654321');
      await tester.enterText(find.byKey(const Key('report-name')), 'Vera Fyre');
      await tester.enterText(find.byKey(const Key('report-email')), 'vera@example.com');
      await tester.tap(find.byKey(const Key('report-need-help')));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Report'));
      await tester.pumpAndSettle();

      final sent = service.submitted!;
      expect(sent['hazardType'], 'Flood');
      expect(sent['particular'], 'Water');
      expect(sent['particularColor'], 'orange');
      expect(sent['particularDetail'], 'Knee deep');
      expect(sent['city'], 'Lipa City');
      expect(sent['barangay'], 'Marauoy');
      expect(sent['purok'], 'Purok 4');
      expect(sent['houseNo'], '12');
      expect(sent['needHelp'], isTrue);
      expect(sent['phone'], '09171234567');
      expect(sent['alternateContact'], '09187654321');
      expect(sent['reporterName'], 'Vera Fyre');
      expect(sent['reporterEmail'], 'vera@example.com');
      expect(sent['clientReportId'], isNotEmpty);
      expect(find.text('RA-20261002-TEST01'), findsOneWidget);
    });

    testWidgets('an invalid optional email blocks submit with a clear message', (tester) async {
      await _pump(tester);
      await _chooseHazard(tester);
      await _fillLocation(tester);
      await tester.enterText(find.byKey(const Key('report-phone')), '09171234567');
      await tester.enterText(find.byKey(const Key('report-email')), 'not-an-email');
      await tester.pump();

      expect(find.text('Enter a valid email address, or leave it blank.'), findsOneWidget);
      expect(_canSubmit(tester), isFalse);
    });

    testWidgets('a signed-in reporter has no Personal Information section and sends no contact fields', (tester) async {
      final service = await _pump(tester, isGuest: false);
      expect(find.byKey(const Key('report-section-personal')), findsNothing);
      expect(find.byKey(const Key('report-phone')), findsNothing);

      await _chooseHazard(tester, color: 'red', detail: 'Waist deep');
      // Changing the color keeps hazard and particular but clears the detail.
      await tester.tap(find.byKey(const Key('report-color-orange')));
      await tester.pumpAndSettle();
      expect(find.text('Waist deep'), findsNothing);
      expect(find.text('Flood'), findsOneWidget);
      await _pickDropdown(tester, _dropdownWithHint('Choose detail...'), 'Knee deep');
      await _fillLocation(tester);
      expect(_canSubmit(tester), isTrue);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Report'));
      await tester.pumpAndSettle();

      final sent = service.submitted!;
      expect(sent['particularColor'], 'orange');
      expect(sent['phone'], isNull);
      expect(sent['alternateContact'], isNull);
      expect(sent['reporterName'], isNull);
      expect(sent['reporterEmail'], isNull);
    });
  });

  group('Emergency photo', () {
    test('a photo over 5 MB is refused with a clear message; 5 MB or less is fine', () {
      expect(emergencyPhotoMaxBytes, 5 * 1024 * 1024);
      expect(emergencyPhotoSizeError(5 * 1024 * 1024), isNull);
      expect(emergencyPhotoSizeError(1200 * 1024), isNull);
      expect(emergencyPhotoSizeError(5 * 1024 * 1024 + 1), contains('larger than 5 MB'));
    });

    testWidgets('the photo section shows the website limits', (tester) async {
      await _pump(tester);

      expect(find.text('JPG, PNG, GIF or WEBP (Max 5MB)'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
    });
  });
}
