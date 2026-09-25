import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smvec_od/services/auth_service.dart';

/// Coming back to the app should not mean signing in again.
///
/// This went wrong twice. First by reading currentUser the instant after
/// Firebase started, which is always null because the restore from disk has
/// not happened yet. Then by taking the first authStateChanges event, which
/// does not wait either - it emits the same premature null, and the restored
/// user turns up afterwards as a second event.
///
/// So these tests drive the waiting rule with the stream shapes Firebase
/// actually produces.
void main() {
  /// The cold-start shape: nobody, then a moment later the restored user.
  Stream<String?> nullThenUser({Duration after = const Duration(milliseconds: 40)}) async* {
    yield null;
    await Future<void>.delayed(after);
    yield 'restored-user';
  }

  group('when a session is expected', () {
    test('the premature null is not mistaken for an answer', () async {
      final user = await AuthService.awaitRestore<String>(
        current: null,
        changes: nullThenUser(),
        expectUser: true,
      );
      expect(user, 'restored-user');
    });

    test('a user already to hand is returned without waiting', () async {
      final user = await AuthService.awaitRestore<String>(
        current: 'already-here',
        changes: const Stream<String?>.empty(),
        expectUser: true,
      );
      expect(user, 'already-here');
    });

    test('a slow restore is still caught', () async {
      final user = await AuthService.awaitRestore<String>(
        current: null,
        changes: nullThenUser(after: const Duration(milliseconds: 300)),
        expectUser: true,
        patient: const Duration(seconds: 2),
      );
      expect(user, 'restored-user');
    });

    test('nobody ever arriving gives up rather than hanging', () async {
      final user = await AuthService.awaitRestore<String>(
        current: null,
        changes: Stream<String?>.fromIterable([null, null]),
        expectUser: true,
        patient: const Duration(milliseconds: 150),
      );
      expect(user, isNull);
    });

    test('a stream that errors falls back instead of throwing', () async {
      final user = await AuthService.awaitRestore<String>(
        current: null,
        changes: Stream<String?>.error(StateError('no channel')),
        expectUser: true,
        patient: const Duration(milliseconds: 150),
        fallback: () => 'from-fallback',
      );
      expect(user, 'from-fallback');
    });
  });

  group('when no session is expected', () {
    test('the first answer is taken and start-up stays quick', () async {
      final clock = Stopwatch()..start();
      final user = await AuthService.awaitRestore<String>(
        current: null,
        changes: nullThenUser(after: const Duration(seconds: 5)),
        expectUser: false,
        brief: const Duration(milliseconds: 500),
      );
      clock.stop();

      expect(user, isNull);
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 400)),
          reason: 'a fresh install should not sit waiting for nobody');
    });

    test('a user on the first event is still honoured', () async {
      final user = await AuthService.awaitRestore<String>(
        current: null,
        changes: Stream<String?>.fromIterable(['signed-in']),
        expectUser: false,
      );
      expect(user, 'signed-in');
    });
  });
}
