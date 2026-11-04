import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_store.dart';
import 'home_screen.dart';
import 'welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Mdi.load();
  final store = AppStore();
  await store.load();
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(EvoknxApp(store: store));
}

class EvoknxApp extends StatelessWidget {
  const EvoknxApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final pal = AppPalette.of(store.config == null ? 'light' : store.mode);
        final dark = pal.screen.computeLuminance() < 0.35;
        SystemChrome.setSystemUIOverlayStyle(dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
        return MaterialApp(
          title: 'EVOKNX',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: kEvoFont,
            colorSchemeSeed: pal.accent,
            scaffoldBackgroundColor: pal.screen,
          ),
          home: store.config == null
              ? WelcomeScreen(store: store)
              : HomeScreen(
                  // A new configuration starts a fresh home screen.
                  key: ValueKey('config-${store.configVersion}'),
                  store: store,
                ),
        );
      },
    );
  }
}
