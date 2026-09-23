import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smvec_od/widgets/role_shell.dart';

/// Every tab has to be reachable.
///
/// The student app shipped with four tabs and three titles, so opening Profile
/// read past the end of a list and the release build showed a blank grey
/// screen - the error widget, which says nothing to the person holding the
/// phone. These tests walk every tab of a shell the way a person would.
void main() {
  ShellTab tab(String name) => ShellTab(
        title: '$name title',
        label: name,
        icon: Icons.circle_outlined,
        selectedIcon: Icons.circle,
        body: Center(child: Text('$name body')),
      );

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('every tab opens, from two up to six', (tester) async {
    for (var count = 2; count <= 6; count++) {
      final names = List.generate(count, (i) => 'Tab$i');

      await tester.pumpWidget(wrap(RoleShell(
        subtitle: 'Department of Information Technology',
        tabs: (_) => [for (final n in names) tab(n)],
      )));
      await tester.pumpAndSettle();

      for (var i = 0; i < count; i++) {
        await tester.tap(find.text(names[i]).last);
        await tester.pumpAndSettle();

        // The app bar follows the tab, which is the part that used to break.
        expect(find.text('${names[i]} title'), findsOneWidget,
            reason: 'tab $i of $count did not put its title in the app bar');
        expect(tester.takeException(), isNull,
            reason: 'tab $i of $count threw while building');
      }
    }
  });

  testWidgets('a tab can open another by name', (tester) async {
    await tester.pumpWidget(wrap(RoleShell(
      subtitle: 'x',
      tabs: (goTo) => [
        ShellTab(
          title: 'Dashboard title',
          label: 'Dashboard',
          icon: Icons.circle_outlined,
          selectedIcon: Icons.circle,
          body: Center(
            child: ElevatedButton(
              onPressed: () => goTo('Requests'),
              child: const Text('Open requests'),
            ),
          ),
        ),
        tab('Requests'),
      ],
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open requests'));
    await tester.pumpAndSettle();

    expect(find.text('Requests title'), findsOneWidget);
  });

  testWidgets('a name that is not in the bar does nothing', (tester) async {
    await tester.pumpWidget(wrap(RoleShell(
      subtitle: 'x',
      tabs: (goTo) => [
        ShellTab(
          title: 'First title',
          label: 'First',
          icon: Icons.circle_outlined,
          selectedIcon: Icons.circle,
          body: Center(
            child: ElevatedButton(
              onPressed: () => goTo('Nowhere'),
              child: const Text('Go nowhere'),
            ),
          ),
        ),
        tab('Second'),
      ],
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go nowhere'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('First title'), findsOneWidget);
  });

  testWidgets('a badge is shown only when there is something to count',
      (tester) async {
    await tester.pumpWidget(wrap(RoleShell(
      subtitle: 'x',
      tabs: (_) => [
        ShellTab(
          title: 'Requests title',
          label: 'Requests',
          icon: Icons.circle_outlined,
          selectedIcon: Icons.circle,
          badgeCount: 3,
          body: const SizedBox(),
        ),
        tab('Quiet'),
      ],
    )));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty shell says so instead of going blank', (tester) async {
    await tester.pumpWidget(wrap(RoleShell(subtitle: 'x', tabs: (_) => [])));
    await tester.pumpAndSettle();

    expect(find.text('This role has nothing to show.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
