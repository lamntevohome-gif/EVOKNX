import 'package:flutter/material.dart';

import 'app/app.dart';
import 'state/app_settings.dart';
import 'state/bus_controller.dart';
import 'state/project_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appSettings.load();
  final project = ProjectController();
  await project.init();
  runApp(EvoknxApp(project: project, bus: BusController(project)));
}
