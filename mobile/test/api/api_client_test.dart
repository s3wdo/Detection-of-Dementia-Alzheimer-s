import 'package:flutter_test/flutter_test.dart';
import 'package:neurosense/core/auth/api_auth_repository.dart';
import 'package:neurosense/core/auth/auth_repository.dart';
import 'package:neurosense/core/auth/session.dart';
import 'package:neurosense/core/network/api_error.dart';
import 'package:neurosense/features/diagnosis/data/analyses_repository.dart';

import 'fakes.dart';

void main() {
  group('tokens', () {
    test('the access token is sent on API calls but not on auth calls', () async {
      final server = FakeServer((c) => (200, <String, dynamic>{}));
      final api = clientFor(server, MemoryTokenStorage(access: 'A1', refresh: 'R1'));
      await api.getJson('/me');
      await api.postJson('/auth/login', body: {'email': 'e', 'password': 'p'});
      expect(server.calls[0].authorization, 'Bearer A1');
      expect(server.calls[1].authorization, isNull);
    });

    test('an expired access token is refreshed once and the request repeated', () async {
      final tokens = MemoryTokenStorage(access: 'old', refresh: 'R1');
      final server = FakeServer((c) {
        if (c.path == '/auth/refresh') return (200, {'access_token': 'new', 'refresh_token': 'R2', 'user': patientUser});
        return c.authorization == 'Bearer new' ? (200, patientUser) : error(401, 'UNAUTHENTICATED', 'Please sign in.');
      });
      var expired = 0;
      final api = clientFor(server, tokens, onSessionExpired: () => expired++);

      expect((await api.getJson('/me'))['full_name'], 'Sarah Johnson');
      expect(server.paths, ['GET /me', 'POST /auth/refresh', 'GET /me']);
      expect(server.calls[1].body, {'refresh_token': 'R1'});
      expect((tokens.access, tokens.refresh), ('new', 'R2'));
      expect(expired, 0);
    });

    test('a rejected refresh clears the tokens and reports the expired session', () async {
      final tokens = MemoryTokenStorage(access: 'old', refresh: 'R1');
      final server = FakeServer((c) => error(401, 'UNAUTHENTICATED', 'Your session has ended. Please sign in again.'));
      var expired = 0;
      final api = clientFor(server, tokens, onSessionExpired: () => expired++);

      await expectLater(api.getJson('/me'), throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 401)));
      expect(server.paths, ['GET /me', 'POST /auth/refresh']); // no endless retry
      expect((tokens.access, tokens.refresh), (null, null));
      expect(expired, 1);
    });

    test('a network failure during refresh does not sign the user out', () async {
      final tokens = MemoryTokenStorage(access: 'old', refresh: 'R1');
      final server = FakeServer((c) {
        if (c.path == '/auth/refresh') return (503, null);
        return error(401, 'UNAUTHENTICATED', 'Please sign in.');
      });
      var expired = 0;
      final api = clientFor(server, tokens, onSessionExpired: () => expired++);

      await expectLater(api.getJson('/me'), throwsA(isA<ApiError>()));
      expect(tokens.refresh, 'R1');
      expect(expired, 0);
    });
  });

  group('errors', () {
    test('server errors become the exceptions the screens already handle', () async {
      final server = FakeServer((c) => switch (c.path) {
            '/missing' => error(404, 'NOT_FOUND', 'This item was not found.'),
            '/twice' => error(409, 'CONFLICT', 'This analysis has already been reviewed.'),
            '/invalid' => error(422, 'VALIDATION_ERROR', 'An override must differ from the AI prediction.'),
            _ => (500, null),
          });
      final api = clientFor(server, MemoryTokenStorage(access: 'A'));

      await expectLater(api.getJson('/missing'), throwsA(isA<NotFoundException>()));
      await expectLater(
        api.postJson('/twice'),
        throwsA(isA<ConflictException>().having((e) => '$e', 'message', 'This analysis has already been reviewed.')),
      );
      await expectLater(
        api.postJson('/invalid'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', 'An override must differ from the AI prediction.')),
      );
      // Anything unexpected is a generic message, never raw server output.
      await expectLater(
          api.getJson('/boom'), throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Something went wrong.')));
    });

    test('an unreachable server gives a connection message', () async {
      final api = clientFor(FakeServer.offline(), MemoryTokenStorage(access: 'A'));
      await expectLater(api.getJson('/me'), throwsA(isA<ApiError>().having((e) => e.code, 'code', 'NETWORK')));
    });
  });

  group('sign-in', () {
    test('signing in stores the tokens and returns the session', () async {
      final tokens = MemoryTokenStorage();
      final server = FakeServer((c) => (200, {'access_token': 'A', 'refresh_token': 'R', 'user': patientUser}));
      final auth = ApiAuthRepository(clientFor(server, tokens), tokens);

      final session = await auth.signIn(email: 'sarah.johnson@neurosense.test', password: 'pw');
      expect(session.role, UserRole.patient);
      expect(session.patientId, 'p-1');
      expect(session.subtitle, 'Patient ID P-1024');
      expect(session.isDemo, isFalse);
      expect((tokens.access, tokens.refresh), ('A', 'R'));
      expect(server.calls.single.body, {'email': 'sarah.johnson@neurosense.test', 'password': 'pw'});
    });

    test('a wrong password shows the server message; an unreachable server says so', () async {
      final tokens = MemoryTokenStorage();
      final wrong = ApiAuthRepository(
        clientFor(FakeServer((c) => error(401, 'INVALID_CREDENTIALS', 'The email or password is incorrect.')), tokens),
        tokens,
      );
      await expectLater(
        wrong.signIn(email: 'e', password: 'p'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'The email or password is incorrect.')),
      );
      expect(tokens.access, isNull);

      final offline = ApiAuthRepository(clientFor(FakeServer.offline(), tokens), tokens);
      await expectLater(
        offline.signIn(email: 'e', password: 'p'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', ApiAuthRepository.unreachable)),
      );
    });

    test('restore returns the saved session, or null when there is none or it is rejected', () async {
      final none = MemoryTokenStorage();
      expect(await ApiAuthRepository(clientFor(FakeServer((c) => (200, doctorUser)), none), none).restore(), isNull);

      final saved = MemoryTokenStorage(access: 'A', refresh: 'R');
      final restored = await ApiAuthRepository(clientFor(FakeServer((c) => (200, doctorUser)), saved), saved).restore();
      expect(restored?.fullName, 'Dr. Ahmed Khan');
      expect(restored?.role, UserRole.doctor);

      final stale = MemoryTokenStorage(access: 'A', refresh: 'R');
      final rejected = FakeServer((c) => error(401, 'UNAUTHENTICATED', 'Please sign in.'));
      expect(await ApiAuthRepository(clientFor(rejected, stale), stale).restore(), isNull);
      expect(stale.refresh, isNull);
    });

    test('signing out clears the tokens and revokes the refresh token', () async {
      final tokens = MemoryTokenStorage(access: 'A', refresh: 'R');
      final server = FakeServer((c) => (204, null));
      await ApiAuthRepository(clientFor(server, tokens), tokens).signOut();
      expect((tokens.access, tokens.refresh), (null, null));
      expect(server.calls.single.path, '/auth/logout');
      expect(server.calls.single.body, {'refresh_token': 'R'});

      // Still signed out locally when the server cannot be reached.
      final offlineTokens = MemoryTokenStorage(access: 'A', refresh: 'R');
      await ApiAuthRepository(clientFor(FakeServer.offline(), offlineTokens), offlineTokens).signOut();
      expect(offlineTokens.refresh, isNull);
    });
  });
}
