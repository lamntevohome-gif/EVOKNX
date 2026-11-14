import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart' hide Text;

import 'account_panel.dart';
import 'app_store.dart';

/// The content of the User page: the account (sign in, sign up, reset password), the plan of the account and the users of the home.
/// The account server is not connected yet, so the plan and the users only say what they will hold.
class UserPanel extends StatelessWidget {
  const UserPanel({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, store.account]),
      builder: (context, _) {
        final pal = AppPalette.of(store.mode);
        final acc = store.account;
        Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: pal.sMuted),
                ),
              ),
              child,
            ],
          ),
        );
        Widget card(List<Widget> children) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.tile,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.tileEdge),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            section('Account', AccountPanel(account: acc, pal: pal)),
            section(
              'Plan',
              card([
                Row(
                  children: [
                    Icon(Icons.workspace_premium_outlined, size: 28, color: pal.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current plan', style: TextStyle(fontSize: 13, color: pal.muted)),
                          Text(
                            acc.signedIn ? 'Account plan' : 'Local use (no account)',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.ink),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'The plans of an account will be shown and changed here when the account server is connected.',
                  style: TextStyle(fontSize: 13.5, height: 1.35, color: pal.muted),
                ),
              ]),
            ),
            section(
              'Users of this home',
              card([
                Row(
                  children: [
                    Icon(Icons.group_outlined, size: 28, color: pal.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(acc.signedIn ? acc.email ?? '' : 'Sign in to manage the users of this home.', style: TextStyle(fontSize: 15, color: pal.ink)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Adding, removing and choosing what each user can control will be done here when the account server is connected.',
                  style: TextStyle(fontSize: 13.5, height: 1.35, color: pal.muted),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }
}

/// The User page: the account, the plan and the users. Settings (profiles, appearance, connections, about) are opened with
/// the button at the top right.
class UserScreen extends StatelessWidget {
  const UserScreen({super.key, required this.store, required this.onSettings});
  final AppStore store;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final pal = AppPalette.of(store.mode);
        return Theme(
          data: ThemeData(
            brightness: pal.sInk.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
            fontFamily: kEvoFont,
            useMaterial3: true,
            colorSchemeSeed: pal.accent,
          ),
          child: Scaffold(
            backgroundColor: pal.screen,
            appBar: AppBar(
              backgroundColor: pal.screen,
              foregroundColor: pal.sInk,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(
                'User',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.sInk),
              ),
              actions: [
                IconButton(tooltip: tr('Settings'), icon: const Icon(Icons.settings_outlined), onPressed: onSettings),
                const SizedBox(width: 4),
              ],
            ),
            body: UserPanel(store: store),
          ),
        );
      },
    );
  }
}
