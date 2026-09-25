import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smvec_od/services/auth_service.dart';

/// Opening the app must not sign you out.
///
/// This is the shape of the bug that survived four fixes, and it is worth
/// stating plainly because every part of it looks reasonable on its own.
///
/// Firebase restores a session from disk a moment after start-up. Until it
/// does, currentUser is null. The API client asked "is anybody signed in?",
/// got that null, and threw a 401. A 401 means the server refused the
/// session, so the app signed the person out and wiped their stored session.
/// The first call of every launch lands in exactly that instant - so the app
/// threw people out precisely because it had just been opened, and the
/// message it showed, "your session was refused by the server", was true of
/// nothing that had happened.
///
/// The rule these pin down: a null that means "not yet" must never be read as
/// a null that means "nobody".
void main() {
  /// What Firebase actually does on a cold start: nothing, then the user.
  Stream<String?> coldStart({
    Duration after = const Duration(milliseconds: 60),
  }) async* {
    yield null;
    await Future<void>.delayed(after);
    yield 'restored-student';
  }

  test('the first call of a launch waits instead of concluding', () async {
    final user = await AuthService.awaitRestore<String>(
      current: null,
      changes: coldStart(),
      expectUser: true,
    );

    expect(user, 'restored-student',
        reason: 'reading the cold-start null as "signed out" is what threw '
            'people out of the app the moment they opened it');
  });

  test('a genuinely signed-out app still reaches the sign-in screen', () async {
    final user = await AuthService.awaitRestore<String>(
      current: null,
      changes: Stream<String?>.fromIterable([null, null]),
      expectUser: true,
      patient: const Duration(milliseconds: 120),
    );

    // Nobody is coming. Being asked to sign in here is correct - it is only
    // being asked while somebody *is* signed in that was the bug.
    expect(user, isNull);
  });

  test('a slow restore is waited out rather than given up on', () async {
    final user = await AuthService.awaitRestore<String>(
      current: null,
      changes: coldStart(after: const Duration(milliseconds: 400)),
      expectUser: true,
      patient: const Duration(seconds: 3),
    );

    expect(user, 'restored-student');
  });

  test('a session already to hand costs nothing', () async {
    final clock = Stopwatch()..start();
    final user = await AuthService.awaitRestore<String>(
      current: 'already-here',
      changes: const Stream<String?>.empty(),
      expectUser: true,
    );
    clock.stop();

    expect(user, 'already-here');
    expect(clock.elapsed, lessThan(const Duration(milliseconds: 50)),
        reason: 'every call after the first must not pay for the wait');
  });

  test('a broken stream falls back instead of hanging or throwing', () async {
    final user = await AuthService.awaitRestore<String>(
      current: null,
      changes: Stream<String?>.error(StateError('no channel')),
      expectUser: true,
      patient: const Duration(milliseconds: 120),
      fallback: () => 'from-fallback',
    );

    expect(user, 'from-fallback');
  });
}
