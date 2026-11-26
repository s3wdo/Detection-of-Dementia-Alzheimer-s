import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/auth/session.dart';
import 'package:neurosense/core/network/api_clinical_repositories.dart';
import 'package:neurosense/core/network/api_support_repositories.dart';
import 'package:neurosense/features/appointments/data/appointments_repository.dart';
import 'package:neurosense/features/appointments/data/models/appointment.dart';
import 'package:neurosense/features/diagnosis/data/analyses_repository.dart';
import 'package:neurosense/features/diagnosis/data/models/analysis.dart';
import 'package:neurosense/features/diagnosis/data/models/analysis_job.dart';
import 'package:neurosense/features/diagnosis/data/models/model_class.dart';
import 'package:neurosense/features/diagnosis/data/models/mri_file.dart';
import 'package:neurosense/features/diagnosis/data/models/upload_models.dart';
import 'package:neurosense/features/notifications/data/models/app_notification.dart';
import 'package:neurosense/features/patients/data/models/patient.dart';
import 'package:neurosense/features/reviews/data/models/review_draft.dart';

import 'fakes.dart';

ApiAnalysesRepository _analyses(FakeServer server) => ApiAnalysesRepository(
      clientFor(server, MemoryTokenStorage(access: 'A')),
      prepareImage: (bytes) async => bytes,
      pollInterval: Duration.zero,
    );

final _file = MriFile(name: 'slice.png', bytes: Uint8List.fromList([1, 2, 3, 4]));

void main() {
  group('analyses', () {
    test('a doctor analysis keeps the simulated flag, scores and doctor-only fields', () async {
      final server = FakeServer((c) => (200, analysisJson(reviewed: true)));
      final a = await _analyses(server).getAnalysis('a-1', patientView: false);

      expect(server.calls.single.path, '/analyses/a-1');
      expect(a.simulated, isTrue, reason: 'stub results must stay labelled as simulated');
      expect(a.predicted, ModelClass.earlyMci);
      expect(a.confidence, 0.91);
      expect(a.probabilities[ModelClass.cognitivelyNormal], 0.03);
      expect(a.status, ReviewStatus.confirmed);
      expect(a.released, isFalse);
      expect(a.clinicalNotes, 'private note');
      expect(a.modelName, 'Stub predictor (no model connected)');
      expect(a.createdAt.isUtc, isFalse, reason: 'server times are shown in local time');
      expect(a.createdAt.toUtc(), DateTime.utc(2026, 10, 5, 8, 30));
    });

    test('a patient analysis has no scores or doctor-only fields to show', () async {
      final server = FakeServer((c) => (200, [analysisJson(reviewed: true, released: true, forPatient: true)]));
      final list = await _analyses(server).listForPatient('p-1', patientView: true);

      expect(server.calls.single.path, '/patients/p-1/analyses');
      final a = list.single;
      expect(a.released, isTrue);
      expect(a.simulated, isTrue);
      expect(a.probabilities, isEmpty);
      expect(a.clinicalNotes, isNull);
      expect(a.overrideReason, isNull);
      expect(a.patientSummary, 'We will talk it through.');
    });

    test('a doctor upload names the patient; a patient upload does not', () async {
      final server = FakeServer((c) => (202, {'scan_id': 's-1', 'analysis_id': 'a-9', 'status': 'received'}));
      final repo = _analyses(server);

      expect(await repo.startAnalysis(patientId: 'p-7', file: _file), 'a-9');
      await repo.uploadForReview(_file);

      final encoded = base64Encode(_file.bytes);
      expect(server.calls[0].body, {'image_base64': encoded, 'filename': 'slice.png', 'patient_id': 'p-7'});
      expect(server.calls[1].body, {'image_base64': encoded, 'filename': 'slice.png'});
      expect(server.paths, ['POST /scans', 'POST /scans']);
    });

    test('the image is prepared (downscaled) before it is sent', () async {
      final server = FakeServer((c) => (202, {'scan_id': 's', 'analysis_id': 'a', 'status': 'received'}));
      final repo = ApiAnalysesRepository(
        clientFor(server, MemoryTokenStorage(access: 'A')),
        prepareImage: (bytes) async => Uint8List.fromList([9, 9]),
      );
      await repo.uploadForReview(_file);
      expect((server.calls.single.body as Map)['image_base64'], base64Encode([9, 9]));
    });

    test('the patient upload list carries only a coarse state', () async {
      final server = FakeServer((c) => (200, [
            {'scan_id': 's2', 'analysis_id': 'a2', 'uploaded_at': '2026-10-07T10:00:00Z', 'state': 'needs_reupload'},
            {'scan_id': 's1', 'analysis_id': 'a1', 'uploaded_at': '2026-10-06T10:00:00Z', 'state': 'received'},
            {'scan_id': 's0', 'analysis_id': 'a0', 'uploaded_at': '2026-10-01T10:00:00Z', 'state': 'released'},
          ]));
      final uploads = await _analyses(server).myUploads();
      expect(server.calls.single.path, '/scans/mine');
      expect(uploads.map((u) => u.state), [UploadState.needsReupload, UploadState.received, UploadState.released]);
    });

    test('job polling maps the server status onto the progress steps', () async {
      final statuses = ['queued', 'queued', 'running', 'completed'];
      var i = 0;
      final server = FakeServer((c) => (200, {'analysis_id': 'a-1', 'job_status': statuses[i++], 'error_code': null}));

      final steps = await _analyses(server).watchJob('a-1').map((j) => j.step).toList();
      expect(steps, [AnalysisStep.validating, AnalysisStep.runningModel, AnalysisStep.completed]);
      expect(server.calls.length, 4);
      expect(server.calls.first.path, '/analyses/a-1/status');
    });

    test('a failed job ends the progress stream with a readable error', () async {
      final server = FakeServer((c) => (200, {'analysis_id': 'a-1', 'job_status': 'failed', 'error_code': 'MODEL_ERROR'}));
      await expectLater(_analyses(server).watchJob('a-1').toList(), throwsA(isA<ConflictException>()));
    });

    test('the image is decoded, and a purged image is simply absent', () async {
      final stored = FakeServer((c) => (200, {'image_base64': base64Encode([7, 8, 9]), 'mime': 'image/png', 'width': 1, 'height': 1}));
      expect(await _analyses(stored).imageFor('a-1'), [7, 8, 9]);

      final purged = FakeServer((c) => error(404, 'NOT_FOUND', 'The image for this scan is no longer stored.'));
      expect(await _analyses(purged).imageFor('a-1'), isNull);
    });
  });

  group('review', () {
    test('the review is validated, sent as the server expects, and a second review is a conflict', () async {
      final server = FakeServer((c) => (201, analysisJson(reviewed: true, released: true)));
      final repo = ApiReviewsRepository(clientFor(server, MemoryTokenStorage(access: 'A')));
      const draft = ReviewDraft(
        analysisId: 'a-1',
        decision: ReviewDecision.confirm,
        predicted: ModelClass.earlyMci,
        clinicalNotes: ' private ',
        patientSummary: 'Summary',
        releaseToPatient: true,
      );

      final result = await repo.submitReview(draft, doctorName: 'Someone Else');
      expect(result.released, isTrue);
      expect(server.calls.single.path, '/analyses/a-1/review');
      // The doctor's name is not sent: the server takes it from the token.
      expect(server.calls.single.body, {
        'decision': 'confirmed',
        'clinical_notes': 'private',
        'patient_summary': 'Summary',
        'release_to_patient': true,
      });

      const invalid = ReviewDraft(
          analysisId: 'a-1', decision: ReviewDecision.override, predicted: ModelClass.earlyMci);
      await expectLater(repo.submitReview(invalid, doctorName: 'x'), throwsArgumentError);

      final twice = ApiReviewsRepository(clientFor(
          FakeServer((c) => error(409, 'CONFLICT', 'This analysis has already been reviewed.')),
          MemoryTokenStorage(access: 'A')));
      await expectLater(twice.submitReview(draft, doctorName: 'x'), throwsA(isA<ConflictException>()));
      await expectLater(twice.releaseToPatient('a-1'), throwsA(isA<ConflictException>()));
    });
  });

  group('patients and dashboards', () {
    test('the patient list sends search and filter and parses the latest analysis', () async {
      final server = FakeServer((c) => (200, [
            {
              'id': 'p-1',
              'mrn': 'P-1024',
              'full_name': 'Sarah Johnson',
              'date_of_birth': '1958-03-12',
              'sex': 'female',
              'phone': '+000',
              'email': 'sarah.johnson@neurosense.test',
              'emergency_contact': 'Daniel Johnson (son)',
              'latest_analysis': analysisJson(),
            }
          ]));
      final repo = ApiPatientsRepository(clientFor(server, MemoryTokenStorage(access: 'A')));

      final patients = await repo.listAssigned((text: ' sarah ', filter: PatientFilter.needsReview));
      expect(server.calls.single.query, {'search': 'sarah', 'filter': 'needsReview'});
      expect(patients.single.mrn, 'P-1024');
      expect(patients.single.sex, Sex.female);
      expect(patients.single.latestAnalysis?.status, ReviewStatus.awaitingConfirmation);
      expect(patients.single.matchesFilter(PatientFilter.needsReview), isTrue);
    });

    test('a note is posted without an author: the server uses the signed-in doctor', () async {
      final server = FakeServer((c) => (201, {
            'id': 'n-1',
            'patient_id': 'p-1',
            'author': 'Dr. Ahmed Khan',
            'body': 'note',
            'created_at': '2026-10-05T08:30:00Z',
          }));
      final repo = ApiPatientsRepository(clientFor(server, MemoryTokenStorage(access: 'A')));
      final note = await repo.addNote('p-1', body: ' note ', author: 'Someone Else');
      expect(server.calls.single.body, {'body': 'note'});
      expect(note.author, 'Dr. Ahmed Khan');
    });

    test('the review queue distinguishes analyses to review from failed ones', () async {
      final server = FakeServer((c) => (200, [
            {
              'analysis_id': 'a-1',
              'patient_id': 'p-1',
              'patient_name': 'Sarah Johnson',
              'patient_display_id': 'P-1024',
              'uploaded_at': '2026-10-05T08:30:00Z',
              'job_status': 'completed',
              'analysis': analysisJson(),
            },
            {
              'analysis_id': 'a-2',
              'patient_id': 'p-2',
              'patient_name': 'Robert Smith',
              'patient_display_id': 'P-1031',
              'uploaded_at': '2026-10-05T09:00:00Z',
              'job_status': 'failed',
              'analysis': null,
            },
          ]));
      final queue = await ApiDashboardRepository(clientFor(server, MemoryTokenStorage(access: 'A'))).reviewQueue();
      expect(server.calls.single.path, '/doctor/review-queue');
      expect(queue.map((i) => i.failed), [false, true]);
      expect(queue.first.analysis?.simulated, isTrue);
    });

    test('dashboards are parsed', () async {
      final event = {
        'id': 'a-1-ai',
        'patient_id': 'p-1',
        'date': '2026-10-05T08:30:00Z',
        'type': 'mriAnalysis',
        'source': 'ai',
        'title': 'MRI analysis',
        'summary': 'Early MCI · 91.0% model confidence',
        'patient_name': 'Sarah Johnson',
        'pending': true,
      };
      final server = FakeServer((c) => switch (c.path) {
            '/doctor/dashboard' => (200, {
                'patient_count': 8,
                'pending_reviews': 2,
                'recent_analyses': 3,
                'upcoming_appointments': 1,
                'recent_activity': [event],
              }),
            _ => (200, {
                'latest_released': analysisJson(reviewed: true, released: true, forPatient: true),
                'next_appointment': null,
                'recent_activity': <Object>[],
              }),
          });
      final repo = ApiDashboardRepository(clientFor(server, MemoryTokenStorage(access: 'A')));

      final doctor = await repo.doctorDashboard();
      expect((doctor.patientCount, doctor.pendingReviews, doctor.upcomingAppointments), (8, 2, 1));
      expect(doctor.recentActivity.single.pending, isTrue);

      // The patient id argument is not sent: the server knows the patient from the token.
      final patient = await repo.patientDashboard('someone-else');
      expect(server.calls.last.path, '/patient/dashboard');
      expect(patient.latestReleased?.released, isTrue);
      expect(patient.nextAppointment, isNull);
    });
  });

  group('appointments, messages, notifications', () {
    final appointment = {
      'id': 'ap-1',
      'patient_id': 'p-1',
      'patient_name': 'Sarah Johnson',
      'doctor_name': 'Dr. Ahmed Khan',
      'starts_at': '2026-10-09T10:00:00Z',
      'duration_min': 30,
      'reason': 'Follow-up',
      'status': 'requested',
      'location': null,
    };

    test('an appointment request sends UTC time and never a patient id', () async {
      final server = FakeServer((c) => (201, appointment));
      final repo = ApiAppointmentsRepository(clientFor(server, MemoryTokenStorage(access: 'A')));
      final when = DateTime.now().add(const Duration(days: 2));

      final created = await repo.request(AppointmentRequest(patientId: 'p-other', reason: 'Follow-up', startsAt: when));
      expect(created.status, AppointmentStatus.requested);
      expect(server.calls.single.body,
          {'reason': 'Follow-up', 'starts_at': when.toUtc().toIso8601String(), 'notes': ''});

      await repo.setStatus('ap-1', AppointmentStatus.cancelled);
      expect(server.calls.last.method, 'PATCH');
      expect(server.calls.last.body, {'status': 'cancelled'});
    });

    test('a message is sent without sender details', () async {
      final server = FakeServer((c) => (201, {
            'id': 'm-1',
            'patient_id': 'p-1',
            'from_doctor': false,
            'sender_name': 'Sarah Johnson',
            'body': 'Hello',
            'created_at': '2026-10-05T08:30:00Z',
            'read_at': null,
            'linked_to': null,
          }));
      final repo = ApiMessagesRepository(clientFor(server, MemoryTokenStorage(access: 'A')));
      final sent = await repo.send(patientId: 'p-1', body: ' Hello ', fromDoctor: true, senderName: 'Dr. Fake');
      expect(server.calls.single.body, {'body': 'Hello'});
      expect(sent.fromDoctor, isFalse);
      expect(sent.senderName, 'Sarah Johnson');
    });

    test('notifications open the right screen for each role', () async {
      Map<String, dynamic> n(String type, String? entity, {String? id = 'x-1', String? patient = 'p-1'}) => {
            'id': 'n-$entity',
            'user_id': 'u',
            'type': type,
            'title': 't',
            'body': 'b',
            'created_at': '2026-10-05T08:30:00Z',
            'read_at': null,
            'entity_type': entity,
            'entity_id': id,
            'patient_id': patient,
          };
      final rows = [
        n('analysis', 'analysis'),
        n('appointment', 'appointment'),
        n('message', 'message'),
        n('analysis', 'patient'),
        n('analysis', 'upload'),
        n('review', null),
      ];
      Future<List<String?>> routes(UserRole role) async {
        final repo = ApiNotificationsRepository(
          clientFor(FakeServer((c) => (200, rows)), MemoryTokenStorage(access: 'A')),
          role: () => role,
        );
        return [for (final AppNotification x in await repo.listFor('ignored')) x.route];
      }

      expect(await routes(UserRole.doctor), [
        '/doctor/patients/p-1/analyses/x-1',
        '/doctor/appointments/x-1',
        '/doctor/messages/p-1',
        '/doctor/patients/p-1',
        null,
        null,
      ]);
      expect(await routes(UserRole.patient), [
        '/patient/results/x-1',
        '/patient/appointments/x-1',
        '/patient/messages',
        null,
        '/patient/upload',
        null,
      ]);
    });
  });
}
