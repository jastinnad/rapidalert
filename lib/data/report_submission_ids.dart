import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'device_id_service.dart';

/// Key-value persistence for [ReportSubmissionIds]; tests pass an in-memory
/// map instead of the device's secure storage.
abstract class ReportIdStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureReportIdStorage implements ReportIdStorage {
  const SecureReportIdStorage();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

class MemoryReportIdStorage implements ReportIdStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

/// The result of [ReportSubmissionIds.submit]: either the report was sent,
/// or nothing was sent because the draft's earlier attempt turned out to be
/// stored already and the report has changed since.
class ReportSubmitOutcome<T> {
  const ReportSubmitOutcome.sent(T this.result, {required this.clientReportId})
    : earlierAttemptStored = false,
      earlierTrackingId = null,
      notAdded = const [];

  const ReportSubmitOutcome.earlierAttemptStored({
    required this.clientReportId,
    required this.notAdded,
    this.earlierTrackingId,
  }) : result = null,
       earlierAttemptStored = true;

  /// The API's answer, when the report was sent.
  final T? result;

  /// The client_report_id the report was sent under, or the earlier
  /// attempt's ID when nothing was sent.
  final String clientReportId;

  /// Nothing was sent: the earlier attempt had already stored the report.
  final bool earlierAttemptStored;

  /// The stored earlier report's tracking ID, when it could be looked up.
  final String? earlierTrackingId;

  /// Labels of the fields changed since that earlier attempt, which the
  /// stored report does not contain.
  final List<String> notAdded;
}

/// Thrown by [ReportSubmissionIds.submit] when a report changed after an
/// unconfirmed attempt and the backend couldn't say whether that attempt was
/// stored. Nothing was sent; the draft is kept for the next try.
class EarlierAttemptCheckFailed implements Exception {
  const EarlierAttemptCheckFailed(this.cause);

  final Object cause;

  @override
  String toString() => 'EarlierAttemptCheckFailed($cause)';
}

/// A report this install submitted: its idempotency key and tracking ID
/// (empty when only its existence is known, see [ReportSubmissionIds.submit]).
typedef SubmittedReport = ({String clientReportId, String trackingId});

/// The API's `client_report_id`: a per-report idempotency key. It is never
/// the device ID and never derived from the report's contents.
///
/// The report being written is a draft with its own random UUIDv4, persisted
/// here rather than in the form (the form is rebuilt on every tab switch)
/// so it also survives an app restart. Retrying the draft unchanged sends
/// the same ID, and the backend returns the report it may already have
/// stored instead of creating a second one. Once the backend confirms the
/// report the draft is finished: the next report is a new draft with a new
/// ID, even if its contents are identical.
///
/// Changed contents are never sent under an earlier attempt's ID. After an
/// unconfirmed attempt, a changed report first asks the backend whether that
/// attempt was stored: if it was, nothing is sent and the caller is told
/// which changes are missing from it; if not, the ID was never used and the
/// changed report goes out as a new draft with a new ID.
///
/// Confirmed reports are remembered with their tracking IDs so a guest can
/// look up their own reports by client_report_id instead of by IP address.
///
/// This is not an offline queue: nothing is resent automatically, and the
/// draft's contents aren't saved. The user retries by tapping Submit again.
class ReportSubmissionIds {
  ReportSubmissionIds({
    ReportIdStorage storage = const SecureReportIdStorage(),
    Future<String> Function()? deviceId,
  }) : _storage = storage,
       _deviceId = deviceId ?? DeviceIdService.getOrCreate;

  final ReportIdStorage _storage;
  final Future<String> Function() _deviceId;

  static const _draftKey = 'rapid_alert_report_draft';
  static const _submittedKey = 'rapid_alert_submitted_reports';
  static const _maxRemembered = 20;
  static const _uuid = Uuid();

  /// Sends the current draft (see the class comment for what happens when
  /// its contents changed after an unconfirmed attempt). [contents] maps
  /// field labels to this attempt's values; it never picks the ID.
  /// [isStored] asks the backend whether a report is stored under an ID; if
  /// it throws, nothing is sent, the draft is kept and
  /// [EarlierAttemptCheckFailed] is thrown. If it is stored,
  /// [lookUpTrackingId] (when given) fetches its tracking ID, best effort.
  /// [trackingId] reads the stored report's tracking ID from the result;
  /// [trackable] says whether the backend stored the report under this ID
  /// (a report merged into an existing incident isn't).
  Future<ReportSubmitOutcome<T>> submit<T>(
    Map<String, Object?> contents,
    Future<T> Function(String clientReportId) send, {
    required Future<bool> Function(String clientReportId) isStored,
    Future<String?> Function(String clientReportId)? lookUpTrackingId,
    required String Function(T result) trackingId,
    bool Function(T result)? trackable,
  }) async {
    await _deviceId(); // every install that reports has its persistent device ID

    final attempt = jsonDecode(jsonEncode(contents)) as Map<String, dynamic>;
    var draft = await _draft();

    if (draft != null) {
      final changed = _changedFields(draft.firstContents, attempt);
      if (changed.isNotEmpty) {
        final bool stored;
        try {
          stored = await isStored(draft.id);
        } catch (e) {
          throw EarlierAttemptCheckFailed(e);
        }
        if (stored) {
          await _storage.write(_draftKey, null);
          String? earlierTrackingId;
          try {
            earlierTrackingId = await lookUpTrackingId?.call(draft.id);
          } catch (_) {
            earlierTrackingId = null; // still remembered by its ID below
          }
          await _remember((clientReportId: draft.id, trackingId: earlierTrackingId ?? ''));
          return ReportSubmitOutcome.earlierAttemptStored(
            clientReportId: draft.id,
            notAdded: changed,
            earlierTrackingId: earlierTrackingId,
          );
        }
        draft = null; // the earlier attempt never arrived; its ID was never used
      }
    }

    if (draft == null) {
      draft = (id: _uuid.v4(), firstContents: attempt);
      await _storage.write(_draftKey, jsonEncode({'id': draft.id, 'first_contents': draft.firstContents}));
    }

    final result = await send(draft.id);

    await _storage.write(_draftKey, null);
    if (trackable == null || trackable(result)) {
      await _remember((clientReportId: draft.id, trackingId: trackingId(result)));
    }
    return ReportSubmitOutcome.sent(result, clientReportId: draft.id);
  }

  static List<String> _changedFields(Map<String, dynamic> first, Map<String, dynamic> attempt) => [
    for (final label in {...first.keys, ...attempt.keys})
      if (jsonEncode(first[label]) != jsonEncode(attempt[label])) label,
  ];

  /// This install's persistent device ID; the same for every report.
  Future<String> deviceId() => _deviceId();

  /// The ID of the draft that has been sent but not confirmed, if any.
  Future<String?> pendingId() async => (await _draft())?.id;

  /// Ends the current draft without it being confirmed, so the next report
  /// gets a new ID; for when the backend says the ID belongs to someone else.
  Future<void> discardDraft() => _storage.write(_draftKey, null);

  /// The ID of this install's most recent stored report, used to find a
  /// guest's latest report. Installs that reported before per-report IDs
  /// existed sent their device ID instead, so that is the fallback.
  Future<String?> latestSubmittedId() async {
    final submitted = await submittedReports();
    return submitted.isNotEmpty ? submitted.last.clientReportId : await _deviceId();
  }

  /// The client_report_id of this install's report with [trackingId], or
  /// null if it isn't one of this install's remembered reports.
  Future<String?> clientReportIdFor(String trackingId) async {
    final wanted = trackingId.trim().toUpperCase();
    for (final report in (await submittedReports()).reversed) {
      if (report.trackingId.toUpperCase() == wanted) return report.clientReportId;
    }
    return null;
  }

  Future<List<String>> submittedIds() async => [for (final r in await submittedReports()) r.clientReportId];

  Future<List<SubmittedReport>> submittedReports() async {
    final raw = await _storage.read(_submittedKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [
        for (final item in jsonDecode(raw) as List<dynamic>)
          (clientReportId: item['id'] as String, trackingId: item['tracking_id'] as String),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<({String id, Map<String, dynamic> firstContents})?> _draft() async {
    final raw = await _storage.read(_draftKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (id: json['id'] as String, firstContents: json['first_contents'] as Map<String, dynamic>);
    } catch (_) {
      return null; // unreadable: start a new draft
    }
  }

  Future<void> _remember(SubmittedReport report) async {
    final submitted = (await submittedReports())
      ..removeWhere((r) => r.clientReportId == report.clientReportId)
      ..add(report);
    final kept = submitted.length > _maxRemembered
        ? submitted.sublist(submitted.length - _maxRemembered)
        : submitted;
    await _storage.write(
      _submittedKey,
      jsonEncode([for (final r in kept) {'id': r.clientReportId, 'tracking_id': r.trackingId}]),
    );
  }
}
