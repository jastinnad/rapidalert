import 'package:flutter_test/flutter_test.dart';

import 'package:rapidalert/data/report_submission_ids.dart';

// client_report_id is a per-report idempotency key. The app used to send its
// fixed device ID as every report's client_report_id, so each device could
// store exactly one report and every later one failed on the unique index.
void main() {
  const deviceId = '11111111-1111-4111-8111-111111111111';
  final uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  late MemoryReportIdStorage storage;
  late ReportSubmissionIds ids;
  var deviceIdCalls = 0;

  /// What the backend has stored, by client_report_id -> tracking ID; the
  /// fake status check answers from it. [statusChecks] records every check.
  late Map<String, String> storedOnServer;
  late List<String> statusChecks;

  ReportSubmissionIds idsOverStorage() => ReportSubmissionIds(
    storage: storage,
    deviceId: () async {
      deviceIdCalls++;
      return deviceId;
    },
  );

  setUp(() {
    storage = MemoryReportIdStorage();
    ids = idsOverStorage();
    deviceIdCalls = 0;
    storedOnServer = {};
    statusChecks = [];
  });

  Map<String, Object?> report(String barangay, {String purok = '1'}) =>
      {'Hazard': ['Flood'], 'Barangay': barangay, 'Purok': purok};

  var nextTracking = 0;

  Future<bool> isStored(String id) async {
    statusChecks.add(id);
    return storedOnServer.containsKey(id);
  }

  /// Submits the current draft successfully; the backend stores it under the
  /// ID sent (unless it already has it) and answers with its tracking ID.
  Future<ReportSubmitOutcome<String>> submitOk(Map<String, Object?> contents, {String? trackingId}) => ids.submit(
    contents,
    (id) async => storedOnServer[id] ??= trackingId ?? 'RA-${++nextTracking}',
    isStored: isStored,
    trackingId: (t) => t,
  );

  /// Submits the current draft and gets no response. With [stored], the
  /// backend stored it anyway (the response was lost). Returns the ID sent.
  Future<String> submitFailing(Map<String, Object?> contents, {bool stored = false}) async {
    late String sent;
    await expectLater(
      ids.submit<String>(contents, (id) async {
        sent = id;
        if (stored) storedOnServer[id] = 'RA-${++nextTracking}';
        throw Exception('no response');
      }, isStored: isStored, trackingId: (t) => t),
      throwsException,
    );
    return sent;
  }

  test('each new report from the same device gets a new UUIDv4 client_report_id', () async {
    final a = (await submitOk(report('A'))).clientReportId;
    final b = (await submitOk(report('B'))).clientReportId;
    final c = (await submitOk(report('C'))).clientReportId;

    expect({a, b, c}, hasLength(3));
    for (final id in [a, b, c]) {
      expect(id, matches(uuidV4));
      expect(id, isNot(deviceId));
    }
  });

  test('a new report with identical contents to the previous one still gets a new ID', () async {
    final b = (await submitOk(report('Same'))).clientReportId;
    final c = (await submitOk(report('Same'))).clientReportId;

    expect(c, isNot(b));
  });

  test('retrying the same report reuses its client_report_id until it is confirmed', () async {
    final attempts = [
      await submitFailing(report('B')),
      await submitFailing(report('B')),
      (await submitOk(report('B'))).clientReportId,
    ];

    expect(attempts.toSet(), hasLength(1));
    expect(await ids.pendingId(), isNull);
  });

  test('an unchanged retry reuses the ID without asking the backend first', () async {
    final first = await submitFailing(report('B'), stored: true);
    final retry = await submitOk(report('B'));

    expect(retry.clientReportId, first);
    expect(retry.result, storedOnServer[first], reason: 'the backend returned the stored report');
    expect(statusChecks, isEmpty);
  });

  test("changed contents are never sent under the earlier attempt's ID", () async {
    final sent = <String>[];
    Future<String> record(String id) async {
      sent.add(id);
      return storedOnServer[id] ??= 'RA-${++nextTracking}';
    }

    final first = await submitFailing(report('Balintawak', purok: '5'));
    final outcome = await ids.submit(
      report('Calamias', purok: '9'),
      record,
      isStored: isStored,
      trackingId: (t) => t,
    );

    expect(statusChecks, [first], reason: 'asked whether the earlier attempt was stored');
    expect(outcome.result, isNotNull);
    expect(outcome.clientReportId, isNot(first), reason: 'the earlier attempt never arrived, so the change is a new report');
    expect(sent, [outcome.clientReportId]);
    expect(storedOnServer.containsKey(first), isFalse);
  });

  test('if the earlier attempt was stored, a changed report sends nothing and names the missing changes', () async {
    final first = await submitFailing(report('Balintawak', purok: '5'), stored: true);
    var sends = 0;

    final outcome = await ids.submit(
      report('Calamias', purok: '9'),
      (id) async {
        sends++;
        return 'unexpected';
      },
      isStored: isStored,
      trackingId: (t) => t,
    );

    expect(sends, 0);
    expect(outcome.result, isNull);
    expect(outcome.clientReportId, first);
    expect(outcome.earlierAttemptStored, isTrue);
    expect(outcome.earlierTrackingId, isNull, reason: 'no lookup was given');
    expect(outcome.notAdded, unorderedEquals(['Barangay', 'Purok']));
    expect(await ids.pendingId(), isNull, reason: 'that draft is finished');
    expect(await ids.latestSubmittedId(), first, reason: 'and a guest blank search finds it');

    // Submitting the changes now makes them a new report with a new ID.
    final changes = await submitOk(report('Calamias', purok: '9'));
    expect(changes.clientReportId, isNot(first));
  });

  test("the stored earlier report's tracking ID is looked up and remembered when possible", () async {
    final first = await submitFailing(report('Balintawak'), stored: true);

    final outcome = await ids.submit(
      report('Calamias'),
      (id) async => 'unexpected',
      isStored: isStored,
      lookUpTrackingId: (id) async => storedOnServer[id],
      trackingId: (t) => t,
    );

    expect(outcome.earlierTrackingId, storedOnServer[first]);
    expect(await ids.clientReportIdFor(storedOnServer[first]!), first);
  });

  test('a failed tracking ID lookup does not change the outcome', () async {
    await submitFailing(report('Balintawak'), stored: true);

    final outcome = await ids.submit(
      report('Calamias'),
      (id) async => 'unexpected',
      isStored: isStored,
      lookUpTrackingId: (_) async => throw Exception('offline'),
      trackingId: (t) => t,
    );

    expect(outcome.earlierAttemptStored, isTrue);
    expect(outcome.earlierTrackingId, isNull);
  });

  test('if the backend cannot say whether the earlier attempt was stored, nothing is sent', () async {
    final first = await submitFailing(report('B'));
    var sends = 0;

    await expectLater(
      ids.submit(
        report('B, changed'),
        (id) async {
          sends++;
          return 'unexpected';
        },
        isStored: (_) async => throw Exception('offline'),
        trackingId: (t) => t,
      ),
      throwsA(isA<EarlierAttemptCheckFailed>()),
    );

    expect(sends, 0);
    expect(await ids.pendingId(), first, reason: 'the draft is kept for the next try');
  });

  test('the unconfirmed draft keeps its ID across tab switches and app restarts', () async {
    final beforeRestart = await submitFailing(report('B'));

    // A new instance over the same storage = the form was rebuilt or the
    // app was killed and reopened.
    ids = idsOverStorage();
    expect(await ids.pendingId(), beforeRestart);
    expect((await submitOk(report('B'))).clientReportId, beforeRestart);
  });

  test('a discarded draft is not reused', () async {
    final first = await submitFailing(report('B'));
    await ids.discardDraft();

    expect((await submitOk(report('B'))).clientReportId, isNot(first));
  });

  test('the device ID is persistent and never a report ID', () async {
    final reportIds = [
      for (final b in ['A', 'B', 'C']) (await submitOk(report(b))).clientReportId,
    ];

    expect(await ids.deviceId(), deviceId);
    expect(deviceIdCalls, greaterThanOrEqualTo(3), reason: 'every submit makes sure the device ID exists');
    expect(reportIds, isNot(contains(deviceId)));
  });

  test('each stored report is remembered with its tracking ID, without collisions', () async {
    final first = (await submitOk(report('A'), trackingId: 'RA-20260928-AAAAAA')).clientReportId;
    final second = (await submitOk(report('B'), trackingId: 'RA-20260928-BBBBBB')).clientReportId;

    expect(await ids.latestSubmittedId(), second);
    expect(await ids.clientReportIdFor('RA-20260928-AAAAAA'), first);
    expect(await ids.clientReportIdFor('ra-20260928-bbbbbb '), second);
    expect(await ids.clientReportIdFor('RA-SOMEONE-ELSE'), isNull);
  });

  test('remembered reports survive an app restart', () async {
    final stored = (await submitOk(report('A'), trackingId: 'RA-1')).clientReportId;

    ids = idsOverStorage();
    expect(await ids.clientReportIdFor('RA-1'), stored);
  });

  test('an install that reported with an older app version still finds that report', () async {
    // Older versions sent the device ID as client_report_id.
    expect(await ids.latestSubmittedId(), deviceId);
  });

  test('a report merged into an existing incident is not used for tracking', () async {
    final stored = (await submitOk(report('A'))).clientReportId;
    await ids.submit(report('B'), (id) async => 'merged', isStored: isStored, trackingId: (t) => t, trackable: (_) => false);

    expect(await ids.latestSubmittedId(), stored);
    expect(await ids.pendingId(), isNull);
  });

  test('only the most recent 20 reports are remembered', () async {
    final all = [for (var i = 0; i < 25; i++) (await submitOk(report('$i'))).clientReportId];

    expect(await ids.submittedIds(), all.sublist(5));
  });
}
