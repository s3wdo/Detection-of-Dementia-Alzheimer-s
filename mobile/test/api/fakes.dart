import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:neurosense/core/network/api_client.dart';
import 'package:neurosense/core/storage/token_storage.dart';

/// Tokens kept in memory (the real class needs the platform keystore).
class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage({this.access, this.refresh});

  String? access;
  String? refresh;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> clear() async => access = refresh = null;
}

/// One reply from the fake server.
typedef Reply = (int status, Object? json);

/// One request the fake server received.
typedef Call = ({String method, String path, Object? body, String? authorization, Map<String, dynamic> query});

/// A stand-in for the NeuroSense server: answers from [handler] and records every call.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.handler);

  /// Never reachable: every request fails like a dropped connection.
  FakeServer.offline() : handler = ((_) => throw const _Offline());

  final Reply Function(Call call) handler;
  final List<Call> calls = [];

  List<String> get paths => [for (final c in calls) '${c.method} ${c.path}'];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final call = (
      method: options.method,
      path: options.path,
      body: options.data,
      authorization: options.headers['Authorization'] as String?,
      query: options.queryParameters,
    );
    calls.add(call);
    final Reply reply;
    try {
      reply = handler(call);
    } on _Offline {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final (status, json) = reply;
    if (json is Uint8List) {
      // A file reply, e.g. a report PDF.
      return ResponseBody.fromBytes(json, status, headers: {
        Headers.contentTypeHeader: ['application/pdf'],
        'content-disposition': ['attachment; filename="NeuroSense-report-P-1024-2026-11-23.pdf"'],
      });
    }
    return ResponseBody.fromString(
      json == null ? '' : jsonEncode(json),
      status,
      headers: {
        if (json != null) Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Offline implements Exception {
  const _Offline();
}

Reply error(int status, String code, String message) => (status, {'error': {'code': code, 'message': message}});

ApiClient clientFor(FakeServer server, TokenStorage tokens, {void Function()? onSessionExpired}) => ApiClient(
      baseUrl: 'http://test.invalid/api/v1',
      tokens: tokens,
      adapter: server,
      onSessionExpired: onSessionExpired,
    );

// ---------------------------------------------------------------- sample server JSON

Map<String, dynamic> analysisJson({
  String id = 'a-1',
  String patientId = 'p-1',
  bool reviewed = false,
  bool released = false,
  bool forPatient = false,
}) =>
    {
      'id': id,
      'patient_id': patientId,
      'created_at': '2026-10-05T08:30:00Z',
      'predicted_label': 'EMCI',
      if (!forPatient) 'confidence': 0.91,
      if (!forPatient)
        'probabilities': {
          'CN': 0.03,
          'EMCI': 0.91,
          'LMCI': 0.04,
          'AD': 0.02,
        },
      'status': reviewed ? 'confirmed' : 'awaitingConfirmation',
      'model_name': 'Stub predictor (no model connected)',
      'model_version': 'stub',
      'simulated': true,
      if (reviewed)
        'review': {
          'final_label': 'EMCI',
          'doctor_name': 'Dr. Ahmed Khan',
          'reviewed_at': '2026-10-06T09:00:00Z',
          if (!forPatient) 'override_reason': null,
          if (!forPatient) 'clinical_notes': 'private note',
          'patient_summary': 'We will talk it through.',
          'released_to_patient': released,
        },
    };

const patientUser = {
  'id': 'u-patient',
  'full_name': 'Sarah Johnson',
  'role': 'patient',
  'subtitle': 'Patient ID P-1024',
  'patient_id': 'p-1',
  'display_id': 'P-1024',
};

const doctorUser = {
  'id': 'u-doctor',
  'full_name': 'Dr. Ahmed Khan',
  'role': 'doctor',
  'subtitle': 'Neurologist',
  'patient_id': null,
  'display_id': 'D-1001',
};
