import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rapidalert/data/auth_service.dart';
import 'package:rapidalert/data/location_catalog_service.dart';
import 'package:rapidalert/screens/auth_components.dart';
import 'package:rapidalert/screens/register_screen.dart';

/// PSGC slice with the real data's shapes: provinces under regions, a
/// barangay name ("Sabang") in two provinces, and NCR's cities directly
/// under the region.
class _FakePsgc implements PsgcDirectory {
  _FakePsgc({this.failCitiesOnce = false, this.emptyBarangays = false});

  final bool failCitiesOnce;
  final bool emptyBarangays;
  Completer<void>? holdRegions;
  int cityCalls = 0;

  static const _provinces = {
    '0400000000': [PsgcPlace('0401000000', 'Batangas'), PsgcPlace('0402100000', 'Cavite')],
    '0100000000': [PsgcPlace('0102900000', 'Ilocos Sur'), PsgcPlace('0102800000', 'Ilocos Norte')],
    '1300000000': <PsgcPlace>[],
  };
  static const _municipalities = {
    '0401000000': [PsgcPlace('0401014000', 'City of Lipa')],
    '0102900000': [PsgcPlace('0102904000', 'Cabugao')],
    '1300000000': [PsgcPlace('1380100000', 'City of Caloocan')],
  };
  static const _barangays = {
    '0401014000': [PsgcPlace('0401014001', 'Sabang'), PsgcPlace('0401014002', 'Santo Niño')],
    '0102904000': [PsgcPlace('0102904001', 'Sabang')],
    '1380100000': [PsgcPlace('1380100001', 'Bagong Silang')],
  };

  @override
  Future<List<PsgcPlace>> regions() async {
    await holdRegions?.future;
    return const [
      PsgcPlace('0400000000', 'CALABARZON'),
      PsgcPlace('0100000000', 'Ilocos Region'),
      PsgcPlace('1300000000', 'NCR'),
    ];
  }

  @override
  Future<List<PsgcPlace>> provinces(String regionCode) async => _provinces[regionCode] ?? const [];

  @override
  Future<List<PsgcPlace>> municipalities(String parentCode) async {
    if (parentCode.endsWith('00000000')) return _municipalities[parentCode] ?? const []; // region
    cityCalls++;
    if (failCitiesOnce && cityCalls == 1) throw Exception('offline');
    return _municipalities[parentCode] ?? const [];
  }

  @override
  Future<List<PsgcPlace>> barangays(String cityCode) async =>
      emptyBarangays ? const [] : (_barangays[cityCode] ?? const []);
}

Future<void> _pumpRegister(WidgetTester tester, _FakePsgc psgc, {ValueChanged<UserSession>? onRegistered}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: RegisterScreen(onRegistered: onRegistered ?? (_) {}, psgc: psgc)),
  );
  await tester.pumpAndSettle();
}

Finder _dropdown(int index) => find.byType(DropdownButtonFormField<String>).at(index);

Future<void> _pick(WidgetTester tester, int dropdown, String option) async {
  await tester.tap(_dropdown(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _fillPersonalFields(WidgetTester tester) async {
  Future<void> type(String hint, String text) => tester.enterText(find.widgetWithText(TextField, hint), text);

  await type('Enter first name', 'Vera');
  await type('Enter last name', 'Fyre');
  await type('Enter email', 'vera@example.com');
  await type('09XXXXXXXXX', '09123456789');
  await type('House number', '12');
  await type('Purok', 'Purok 3');
  await type('Nearby landmark', 'Near the chapel');
  await type('Create password', 'StrongPass1!');
  await tester.pump();
}

bool _canSubmit(WidgetTester tester) =>
    tester.widget<AuthPrimaryButton>(find.widgetWithText(AuthPrimaryButton, 'Create Account')).onPressed != null;

Future<Map<String, dynamic>?> _submit(WidgetTester tester, {http.Response? response}) async {
  Map<String, dynamic>? sent;
  final client = MockClient((request) async {
    expect(request.url.path, '/api/auth/register');
    sent = jsonDecode(request.body) as Map<String, dynamic>;
    return response ??
        http.Response(
          jsonEncode({
            'token': 'test-token',
            'user': {'id': 9, 'first_name': 'Vera', 'last_name': 'Fyre', 'email': 'vera@example.com', 'role': 'reporter'},
          }),
          201,
        );
  });
  await http.runWithClient(() async {
    await tester.tap(find.widgetWithText(AuthPrimaryButton, 'Create Account'));
    await tester.pumpAndSettle();
  }, () => client);
  return sent;
}

Map<String, dynamic> _personalFields() => {
  'first_name': 'Vera',
  'last_name': 'Fyre',
  'email': 'vera@example.com',
  'phone': '09123456789',
  'password': 'StrongPass1!',
  'password_confirmation': 'StrongPass1!',
  'house_no': '12',
  'purok': 'Purok 3',
  'landmark': 'Near the chapel',
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Register address picker', () {
    testWidgets('shows a loading state, then Region > Province > City > Barangay with no free-text barangay', (
      tester,
    ) async {
      final psgc = _FakePsgc()..holdRegions = Completer<void>();
      await tester.pumpWidget(MaterialApp(home: RegisterScreen(onRegistered: (_) {}, psgc: psgc)));
      await tester.pump();

      expect(find.text('Loading regions…'), findsOneWidget);

      psgc.holdRegions!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Loading regions…'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(4));
      expect(find.text('Select a region first'), findsOneWidget);
      expect(find.text('Select a province first'), findsOneWidget);
      expect(find.text('Select a city / municipality first'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Enter barangay'), findsNothing);
      expect(find.text('Lipa City only.'), findsNothing);

      // Later levels can't be opened until their parent is chosen.
      final dropdowns = tester.widgetList<DropdownButtonFormField<String>>(find.byType(DropdownButtonFormField<String>));
      expect(dropdowns.map((d) => d.onChanged != null).toList(), [true, false, false, false]);
      await tester.tap(_dropdown(1));
      await tester.pumpAndSettle();
      expect(find.text('Batangas'), findsNothing);
    });

    testWidgets('a Lipa address submits its PSGC codes with every existing field', (tester) async {
      await _pumpRegister(tester, _FakePsgc());
      await _fillPersonalFields(tester);

      await _pick(tester, 0, 'CALABARZON');
      await _pick(tester, 1, 'Batangas');
      await _pick(tester, 2, 'City of Lipa');
      expect(_canSubmit(tester), isFalse);
      await _pick(tester, 3, 'Santo Niño');
      expect(_canSubmit(tester), isTrue);

      expect(await _submit(tester), {
        ..._personalFields(),
        'region_code': '0400000000',
        'province_code': '0401000000',
        'city_code': '0401014000',
        'barangay_code': '0401014002',
        'barangay': 'Santo Niño',
      });
    });

    testWidgets('an address outside Lipa is accepted, and a shared barangay name keeps its own code', (tester) async {
      await _pumpRegister(tester, _FakePsgc());
      await _fillPersonalFields(tester);

      await _pick(tester, 0, 'Ilocos Region');
      await _pick(tester, 1, 'Ilocos Sur');
      await _pick(tester, 2, 'Cabugao');
      await _pick(tester, 3, 'Sabang');

      final sent = await _submit(tester);
      expect(sent?['city_code'], '0102904000');
      expect(sent?['barangay_code'], '0102904001'); // Cabugao's Sabang, not Lipa's 0401014001
    });

    testWidgets('an NCR city sits directly under the region and is sent with an empty province code', (tester) async {
      await _pumpRegister(tester, _FakePsgc());
      await _fillPersonalFields(tester);

      await _pick(tester, 0, 'NCR');
      expect(find.text('No province (city directly under the region)'), findsOneWidget); // chosen automatically
      await _pick(tester, 2, 'City of Caloocan');
      await _pick(tester, 3, 'Bagong Silang');

      final sent = await _submit(tester);
      expect(sent?['region_code'], '1300000000');
      expect(sent?['province_code'], '');
      expect(sent?['city_code'], '1380100000');
      expect(sent?['barangay_code'], '1380100001');
    });

    testWidgets('changing the region clears the later choices', (tester) async {
      await _pumpRegister(tester, _FakePsgc());
      await _fillPersonalFields(tester);

      await _pick(tester, 0, 'CALABARZON');
      await _pick(tester, 1, 'Batangas');
      await _pick(tester, 2, 'City of Lipa');
      await _pick(tester, 3, 'Sabang');
      expect(_canSubmit(tester), isTrue);

      await _pick(tester, 0, 'Ilocos Region');

      expect(_canSubmit(tester), isFalse);
      expect(find.text('Select province'), findsOneWidget);
      expect(find.text('Select a province first'), findsOneWidget);
      expect(find.text('City of Lipa'), findsNothing);
    });

    testWidgets('a failed list shows an error with Retry, and Retry loads it', (tester) async {
      final psgc = _FakePsgc(failCitiesOnce: true);
      await _pumpRegister(tester, psgc);

      await _pick(tester, 0, 'CALABARZON');
      await _pick(tester, 1, 'Batangas');

      expect(find.textContaining("Couldn't load this list"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(psgc.cityCalls, 2);
      expect(find.textContaining("Couldn't load"), findsNothing);
      await _pick(tester, 2, 'City of Lipa');
    });

    testWidgets('an empty list is shown as a message with Retry, never as an empty dropdown', (tester) async {
      await _pumpRegister(tester, _FakePsgc(emptyBarangays: true));

      await _pick(tester, 0, 'CALABARZON');
      await _pick(tester, 1, 'Batangas');
      await _pick(tester, 2, 'City of Lipa');

      expect(find.text('No barangays are available for this city yet.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
    });

    testWidgets("the server's location validation message is shown, not a generic error", (tester) async {
      await _pumpRegister(tester, _FakePsgc());
      await _fillPersonalFields(tester);
      await _pick(tester, 0, 'CALABARZON');
      await _pick(tester, 1, 'Batangas');
      await _pick(tester, 2, 'City of Lipa');
      await _pick(tester, 3, 'Sabang');

      await _submit(
        tester,
        response: http.Response(
          jsonEncode({
            'message': 'Please select a valid barangay.',
            'errors': {
              'barangay_code': ['Please select a valid barangay.'],
            },
          }),
          422,
        ),
      );

      expect(find.text('Please select a valid barangay.'), findsOneWidget);
      expect(find.textContaining('having trouble'), findsNothing);

      // The chosen address and every typed field survive the rejection, so
      // the user can fix one level and resubmit the same codes.
      for (final label in ['CALABARZON', 'Batangas', 'City of Lipa', 'Sabang']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('vera@example.com'), findsOneWidget);
      expect(_canSubmit(tester), isTrue);
      final resent = await _submit(tester);
      expect(resent?['barangay_code'], '0401014001');
      expect(resent?['city_code'], '0401014000');
    });
  });

  group('ApiPsgcDirectory', () {
    test('reads codes and UTF-8 names, and never caches an empty list', () async {
      var barangays = <Map<String, String>>[];
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/psgc/barangays/0401014000');
        // Laravel sends JSON without a charset; it must still decode as UTF-8.
        return http.Response.bytes(
          utf8.encode(jsonEncode({'barangays': barangays})),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await http.runWithClient(() async {
        final psgc = ApiPsgcDirectory('http://psgc.test');
        expect(await psgc.barangays('0401014000'), isEmpty);

        barangays = [
          {'psgc_code': '0401014002', 'name': 'Santo Niño'},
        ];
        final loaded = await psgc.barangays('0401014000');
        expect(loaded.single.code, '0401014002');
        expect(loaded.single.name, 'Santo Niño');

        await psgc.barangays('0401014000'); // cached now
      }, () => client);

      expect(calls, 2);
    });
  });
}
