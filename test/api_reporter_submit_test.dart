import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:rapidalert/data/api_reporter_service.dart';
import 'package:rapidalert/data/report_submission_ids.dart';
import 'package:rapidalert/models/reporter_models.dart';
import 'package:rapidalert/screens/report_submit_screen.dart'
    show reportEarlierAttemptStoredMessage, reportSubmitErrorMessage, reportSubmitSuccessMessage;

/// The fields of a multipart request body, by name.
Map<String, String> multipartFields(http.Request request) {
  final body = latin1.decode(request.bodyBytes);
  return {
    for (final m in RegExp(r'name="([^"]+)"\r\n\r\n([^\r]*)\r\n').allMatches(body)) m.group(1)!: m.group(2)!,
  };
}

Future<ReportSubmitResult> submit(ApiReporterService service, String clientReportId) {
  return service.submitReport(
    hazardType: 'Flood',
    particular: 'Flood depth',
    particularColor: 'orange',
    particularDetail: 'Knee-to-waist deep, rising',
    region: 'Region IV-A',
    province: 'Batangas',
    city: 'Lipa City',
    barangay: 'Banaybanay',
    purok: '1',
    houseNo: '10',
    clientReportId: clientReportId,
    phone: '09171234567',
  );
}

void main() {
  final service = ApiReporterService(baseUrl: 'http://api.test', bearerToken: '');

  test('the same device sends a different client_report_id for each report, and the same one on retry', () async {
    final sent = <String>[];
    final ids = ReportSubmissionIds(storage: MemoryReportIdStorage(), deviceId: () async => 'device-1');
    var failNext = false;

    final client = MockClient((request) async {
      expect(request.url.path, '/api/reporter/reports');
      final id = multipartFields(request)['client_report_id']!;
      final retry = sent.contains(id);
      sent.add(id);
      if (failNext) {
        failNext = false;
        return http.Response('{"message":"Server Error"}', 500);
      }
      return http.Response(
        jsonEncode({'tracking_id': 'RA-${sent.length}', 'duplicate': false, 'replayed': retry, 'message': 'ok'}),
        200,
      );
    });

    await http.runWithClient(() async {
      String tracking(ReportSubmitResult r) => r.trackingId;
      Future<ReportSubmitOutcome<ReportSubmitResult>> send(String report) => ids.submit(
        {'r': report},
        (id) => submit(service, id),
        isStored: service.submittedReportExists,
        trackingId: tracking,
      );
      await send('A');
      await send('B');

      failNext = true;
      await expectLater(send('C'), throwsA(isA<ReportSubmitException>()));
      final retried = await send('C');
      expect(retried.result!.replayed, isTrue);
    }, () => client);

    expect(sent, hasLength(4));
    expect(sent.sublist(0, 3).toSet(), hasLength(3), reason: 'three separate reports');
    expect(sent[3], sent[2], reason: 'the retry reuses the failed report\'s ID');
    expect(sent, isNot(contains('device-1')));
  });

  test('a server error becomes a ReportSubmitException with its status and message', () async {
    final client = MockClient((_) async => http.Response('{"message":"Server Error"}', 500));

    final error = await http.runWithClient(
      () => submit(service, 'id-1').then<Object?>((_) => null, onError: (Object e) => e),
      () => client,
    );

    expect(error, isA<ReportSubmitException>());
    expect((error as ReportSubmitException).statusCode, 500);
    expect(error.serverMessage, 'Server Error');
  });

  test('no connection becomes a ReportSubmitException without a status', () async {
    final client = MockClient((_) async => throw http.ClientException('Connection refused'));

    final error = await http.runWithClient(
      () => submit(service, 'id-1').then<Object?>((_) => null, onError: (Object e) => e),
      () => client,
    );

    expect(error, isA<ReportSubmitException>());
    expect((error as ReportSubmitException).statusCode, isNull);
  });

  test('guest tracking asks for the report by its client_report_id', () async {
    Uri? requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(jsonEncode({'found': false, 'report': null}), 200);
    });

    await http.runWithClient(() => service.trackReport(clientReportId: 'report-id-2'), () => client);

    expect(requested!.path, '/api/reporter/reports/track');
    expect(requested!.queryParameters, {'client_report_id': 'report-id-2'});
  });

  group('the success message says the report went through', () {
    test('new report', () {
      final text = reportSubmitSuccessMessage(const ReportSubmitResult(trackingId: 'RA-1', message: '', duplicate: false));
      expect(text, startsWith('Report submitted.'));
      expect(text, contains('RA-1'));
    });

    test('retry of a report that had already arrived', () {
      final text = reportSubmitSuccessMessage(
        const ReportSubmitResult(trackingId: 'RA-1', message: '', duplicate: false, replayed: true),
      );
      expect(text, contains('no duplicate was created'));
      expect(text, contains('RA-1'));
    });
  });

  test('a changed report whose original was already stored names the fields not added', () {
    final text = reportEarlierAttemptStoredMessage(['Barangay', 'Purok'], trackingId: 'RA-1');
    expect(text, contains('original report was already stored'));
    expect(text, contains('Tracking ID: RA-1'));
    expect(reportEarlierAttemptStoredMessage(['Barangay']), contains('see Track'));
    expect(text, contains('NOT added: Barangay, Purok'));
    expect(text, contains('Nothing new was sent'));
    expect(text, contains('send them as a new report'));
  });

  test('a failed check of the earlier attempt says nothing was sent', () {
    final text = reportSubmitErrorMessage(EarlierAttemptCheckFailed(Exception('offline')));
    expect(text, startsWith('Not sent'));
    expect(text, contains('Nothing was sent'));
  });

  group('asking whether a client_report_id is already stored', () {
    Future<Object?> ask(http.Response Function(http.Request) respond) => http.runWithClient(
      () => service.submittedReportExists('8849a75f-8837-4e90-a6fd-ee2f4eb48406').then<Object?>((v) => v, onError: (Object e) => e),
      () => MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/reporter/report-submission-status/8849a75f-8837-4e90-a6fd-ee2f4eb48406');
        expect(request.url.query, isEmpty);
        return respond(request);
      }),
    );

    test('EXISTS', () async {
      expect(await ask((_) => http.Response('{"exists":true}', 200)), isTrue);
    });

    test('NOT_FOUND', () async {
      expect(await ask((_) => http.Response('{"exists":false}', 200)), isFalse);
    });

    test('CHECK_FAILED: a 404 (e.g. a backend without this endpoint)', () async {
      expect(await ask((_) => http.Response('<html>Not Found</html>', 404)), isA<ReportSubmitException>());
    });

    test('CHECK_FAILED: a server error', () async {
      expect(await ask((_) => http.Response('{"message":"Server Error"}', 500)), isA<ReportSubmitException>());
    });

    test('CHECK_FAILED: an answer without a boolean "exists"', () async {
      expect(await ask((_) => http.Response('{"exists":"yes"}', 200)), isA<ReportSubmitException>());
    });

    test('CHECK_FAILED: no connection', () async {
      expect(await ask((_) => throw http.ClientException('offline')), isA<ReportSubmitException>());
    });
  });

  group('the failed-submission message says what happened', () {
    test('no connection', () {
      final text = reportSubmitErrorMessage(const ReportSubmitException());
      expect(text, startsWith('Not confirmed'));
      expect(text, contains("couldn't be reached"));
      expect(text, contains('without changing anything'));
      expect(text, contains("won't create a duplicate"));
    });

    test('server error (the report may or may not have been stored)', () {
      final text = reportSubmitErrorMessage(const ReportSubmitException(statusCode: 500));
      expect(text, contains('error 500'));
      expect(text, contains('may not have been sent'));
      expect(text, contains("won't create a duplicate"));
    });

    test('validation error shows the server reason', () {
      final text = reportSubmitErrorMessage(
        const ReportSubmitException(statusCode: 422, serverMessage: 'Emergency reports are currently accepted for Lipa City only.'),
      );
      expect(text, startsWith('Not sent'));
      expect(text, contains('Lipa City only'));
    });

    test('rate limited', () {
      expect(reportSubmitErrorMessage(const ReportSubmitException(statusCode: 429)), contains('Wait a minute'));
    });

    test('expired session', () {
      expect(reportSubmitErrorMessage(const ReportSubmitException(statusCode: 401)), contains('Sign in again'));
    });

    test('ID conflict', () {
      expect(reportSubmitErrorMessage(const ReportSubmitException(statusCode: 409)), contains('new report'));
    });
  });

  test('guest contact details go out under the website field names, and are left out when empty', () async {
    final sent = <Map<String, String>>[];
    final client = MockClient((request) async {
      sent.add(multipartFields(request));
      return http.Response(jsonEncode({'tracking_id': 'RA-1', 'duplicate': false, 'message': 'ok'}), 200);
    });

    await http.runWithClient(() async {
      await service.submitReport(
        hazardType: 'Flood',
        particular: 'Flood depth',
        particularColor: 'orange',
        particularDetail: 'Knee-to-waist deep, rising',
        region: 'Region IV-A',
        province: 'Batangas',
        city: 'Lipa City',
        barangay: 'Banaybanay',
        purok: '1',
        houseNo: '10',
        clientReportId: 'id-with-contacts',
        phone: '09171234567',
        alternateContact: '09187654321',
        reporterName: 'Vera Fyre',
        reporterEmail: 'vera@example.com',
      );
      await submit(service, 'id-without-contacts');
    }, () => client);

    expect(sent[0], containsPair('alternate_contact', '09187654321'));
    expect(sent[0], containsPair('reporter_name', 'Vera Fyre'));
    expect(sent[0], containsPair('reporter_email', 'vera@example.com'));
    expect(sent[0], containsPair('phone', '09171234567'));
    expect(sent[0], containsPair('client_report_id', 'id-with-contacts'));

    // Without them the request is exactly what it was before.
    expect(sent[1].keys, isNot(contains('alternate_contact')));
    expect(sent[1].keys, isNot(contains('reporter_name')));
    expect(sent[1].keys, isNot(contains('reporter_email')));
    expect(sent[1].keys.toSet(), {
      'hazard_type', 'particular', 'particular_color', 'particular_detail', 'region', 'province', 'city', 'barangay',
      'purok', 'house_no', 'pregnant_count', 'elderly_count', 'child_count', 'pwd_count', 'client_report_id', 'phone',
    });
  });
}
