import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Nothing asks the server a question it cannot yet phrase.
///
/// Screens refresh the moment they appear, which at start-up is before
/// Firebase has produced its user. Those calls went out with nothing to
/// authenticate with and came back "not signed in" - and that complaint then
/// sat on the home screen, over the person's own data, while a later working
/// call spun underneath it.
///
/// It was fixed twice at the call site and came back both times, because there
/// is more than one call site and they all have a perfectly good reason to
/// refresh when they open. The wait belongs in the single place they pass
/// through. These tests cover that gate's behaviour on its own, because a
/// mistake in it stalls the whole app rather than one screen.
void main() {
  late Completer<void> gate;

  setUp(() => gate = Completer<void>());

  /// What refresh() does: wait for the gate, but never for ever.
  Future<String> syncWhenReady({
    Duration patience = const Duration(seconds: 20),
  }) async {
    await gate.future.timeout(patience, onTimeout: () {});
    return 'synced';
  }

  test('a refresh raised before the session is ready waits for it', () async {
    final pending = syncWhenReady();

    var finished = false;
    unawaited(pending.then((_) => finished = true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(finished, isFalse, reason: 'it should still be waiting');

    gate.complete();
    expect(await pending, 'synced');
  });

  test('once open, later refreshes do not wait at all', () async {
    gate.complete();

    final clock = Stopwatch()..start();
    await syncWhenReady();
    clock.stop();

    expect(clock.elapsed, lessThan(const Duration(milliseconds: 50)),
        reason: 'every refresh after the first must be immediate');
  });

  test('a gate that never opens gives up rather than hanging for ever',
      () async {
    // Firebase never answering must not leave the app spinning with no way
    // out - the request goes anyway and fails honestly.
    final result = await syncWhenReady(patience: const Duration(milliseconds: 80));
    expect(result, 'synced');
  });

  test('signing out releases whoever was waiting', () async {
    final pending = syncWhenReady();

    // setUser(null) completes the old gate before replacing it. Without that,
    // a refresh raised just before a sign-out hangs on a gate nobody will ever
    // open.
    if (!gate.isCompleted) gate.complete();
    gate = Completer<void>();

    expect(await pending, 'synced');
    expect(gate.isCompleted, isFalse,
        reason: 'the next person signing in gets a closed gate of their own');
  });

  test('opening an already-open gate is harmless', () async {
    // markSessionReady is called from more than one path and they can race.
    void open() {
      if (!gate.isCompleted) gate.complete();
    }

    open();
    open();
    open();

    expect(gate.isCompleted, isTrue);
    await syncWhenReady();
  });
}
