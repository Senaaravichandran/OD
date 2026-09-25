import 'package:flutter_test/flutter_test.dart';
import 'package:smvec_od/services/api_client.dart';

/// A session survives a bad connection.
///
/// This is the rule that kept getting broken. Every launch asks the server who
/// we are, and that call was wrapped in a catch that signed the person out for
/// *any* failure. A timeout, a dropped connection, a radio still waking up -
/// none of which say anything about whether the session is good - all
/// destroyed it. It looked exactly like the app forgetting people: fine while
/// you were using it, asking again when you came back later.
///
/// So the whole decision now rests on telling a refusal from a failure to ask,
/// and that is what these pin down. Three places act on it: the launch session
/// exchange, the staff session refresh, and every sync.
void main() {
  group('the server refused us', () {
    test('401 is a refusal', () {
      final e = ApiException('Please sign in first.', 401);
      expect(e.isRefused, isTrue);
      expect(e.isOffline, isFalse);
    });

    test('403 is a refusal', () {
      // A removed advisor, or an address outside the college.
      final e = ApiException('This account has been removed.', 403);
      expect(e.isRefused, isTrue);
      expect(e.isOffline, isFalse);
    });
  });

  group('we could not ask', () {
    test('a timeout is not a refusal', () {
      final e = ApiException('The server took too long to respond.');
      expect(e.isRefused, isFalse,
          reason: 'signing out on a timeout is what threw people out of the app');
      expect(e.isOffline, isTrue);
    });

    test('an unreachable server is not a refusal', () {
      final e = ApiException('Could not reach the server. Check your connection.');
      expect(e.isRefused, isFalse);
      expect(e.isOffline, isTrue);
    });

    test('sign-in services being unreachable is not a refusal', () {
      // Firebase holds a user but cannot mint a token, which is almost always
      // the network. Reporting that as 401 used to sign the person out.
      final e = ApiException('Could not reach sign-in services.');
      expect(e.isRefused, isFalse);
      expect(e.isOffline, isTrue);
    });
  });

  group('the server answered, badly', () {
    test('a server error is not a refusal', () {
      final e = ApiException('Server error. Please try again.', 500);
      expect(e.isRefused, isFalse,
          reason: 'our own outage must not sign the department out');
      expect(e.isOffline, isFalse);
    });

    test('a bad request is not a refusal', () {
      final e = ApiException('No OD request was specified.', 400);
      expect(e.isRefused, isFalse);
    });

    test('a conflict is not a refusal', () {
      final e = ApiException('This request was already reviewed.', 409);
      expect(e.isRefused, isFalse);
      expect(e.isConflict, isTrue);
    });

    test('not found is not a refusal', () {
      expect(ApiException('Request not found.', 404).isRefused, isFalse);
    });
  });

  test('every status that ends a session is deliberate', () {
    // Anything not in this set leaves the session alone. Adding to it is a
    // decision to sign people out, so it should be made on purpose.
    const endsTheSession = {401, 403};

    for (final status in [null, 400, 404, 409, 413, 500, 502, 503, 504]) {
      expect(ApiException('x', status).isRefused, endsTheSession.contains(status),
          reason: 'status $status');
    }
    for (final status in endsTheSession) {
      expect(ApiException('x', status).isRefused, isTrue, reason: 'status $status');
    }
  });
}
