import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smvec_od/models/user.dart';
import 'package:smvec_od/services/session_service.dart';

/// A class advisor or the HOD signs in with a password once, and stays signed
/// in.
///
/// Their session is the one the app has to keep itself - Firebase holds
/// nothing for them, because they have no Firebase account. Every step of that
/// round trip is silent on failure by design, so that a device refusing
/// storage does not crash the app; the cost is that a mistake anywhere in it
/// shows up only as "please sign in again", every launch, with nothing in the
/// logs. Hence these.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppUser staff({
    String token = 'staff.body.signature',
    UserRole role = UserRole.advisor,
  }) =>
      AppUser(
        name: 'Padmapriya',
        email: 'padmapriya@smvec.ac.in',
        role: role,
        classes: const [
          AdvisorClass(year: 1, section: 'A', label: 'Padmapriya', batch: '2026-2030'),
        ],
        staffToken: token,
      );

  test('a signed-in advisor is still signed in next launch', () async {
    await SessionService.saveStaff(staff());

    final restored = await SessionService.loadStaff();

    expect(restored, isNotNull, reason: 'the session was not kept at all');
    expect(restored!.staffToken, 'staff.body.signature');
    expect(restored.email, 'padmapriya@smvec.ac.in');
    expect(restored.name, 'Padmapriya');
    expect(restored.role, UserRole.advisor);
  });

  test('the HOD keeps their role, not just their name', () async {
    await SessionService.saveStaff(staff(role: UserRole.hod));

    final restored = await SessionService.loadStaff();

    // Getting this wrong would open the advisor app for the HOD, which is the
    // kind of thing nobody reports as a bug - they just find half their
    // screens missing.
    expect(restored?.role, UserRole.hod);
  });

  test('the classes they advise survive the round trip', () async {
    await SessionService.saveStaff(staff());

    final restored = await SessionService.loadStaff();

    expect(restored?.classes, hasLength(1));
    expect(restored?.classes.first.year, 1);
    expect(restored?.classes.first.section, 'A');
    expect(restored?.classes.first.batch, '2026-2030');
  });

  test('the route is remembered so start-up knows how to wait', () async {
    await SessionService.rememberRoute(SignInRoute.staff.name);
    expect(await SessionService.lastRoute(), SignInRoute.staff.name);

    await SessionService.rememberRoute(SignInRoute.google.name);
    expect(await SessionService.lastRoute(), SignInRoute.google.name);
  });

  test('the route names are the ones start-up compares against', () {
    // lastRoute() is compared as a string at start-up, so renaming either of
    // these would quietly stop the app waiting for a Google session - and the
    // symptom would be everybody asked to sign in again, which is exactly the
    // bug this pins down.
    expect(SignInRoute.google.name, 'google');
    expect(SignInRoute.staff.name, 'staff');
  });

  test('a stored staff session always comes back with its token', () async {
    // The token used to be read back off widget state while refreshing the
    // session. Whenever that state was not yet set the refresh adopted a user
    // carrying no token, which wiped it from the client and made the next call
    // a 401 - signing the person out and clearing the session. Whatever else
    // changes, a loaded staff session has a token or it is not a session.
    await SessionService.saveStaff(staff());

    final restored = await SessionService.loadStaff();

    expect(restored, isNotNull);
    expect(restored!.staffToken, isNotNull);
    expect(restored.staffToken, isNotEmpty);
  });

  test('a renewed token replaces the old one', () async {
    await SessionService.saveStaff(staff());
    await SessionService.saveStaff(staff(token: 'staff.newer.signature'));

    expect((await SessionService.loadStaff())?.staffToken, 'staff.newer.signature');
  });

  test('a session with no token is not written at all', () async {
    // A student reaching this by mistake must not leave a half-session behind
    // that the next launch would try to use.
    await SessionService.saveStaff(
      AppUser(name: 'A Student', email: 's@smvec.ac.in', role: UserRole.student),
    );

    expect(await SessionService.loadStaff(), isNull);
  });

  test('signing out leaves nothing behind', () async {
    await SessionService.saveStaff(staff());
    await SessionService.rememberRoute('staff');

    await SessionService.clear();

    expect(await SessionService.loadStaff(), isNull);
    expect(await SessionService.lastRoute(), isNull);
  });

  test('a half-written session is treated as none', () async {
    // The token without the profile, which is what a crash between the two
    // writes would leave.
    SharedPreferences.setMockInitialValues({
      'smvec_staff_token_v3': 'staff.body.signature',
    });

    expect(await SessionService.loadStaff(), isNull);
  });
}
