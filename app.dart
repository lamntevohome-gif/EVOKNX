import 'package:flutter/material.dart';

import '../state/app_settings.dart';
import '../state/bus_controller.dart';
import '../state/project_controller.dart';
import '../ui/shell.dart';
import 'theme.dart';

class EvoknxApp extends StatelessWidget {
  const EvoknxApp({super.key, required this.project, required this.bus});
  final ProjectController project;
  final BusController bus;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => MaterialApp(
        title: 'EVOKNX Editor',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: appSettings.themeMode,
        home: Shell(project: project, bus: bus),
      ),
    );
  }
}
