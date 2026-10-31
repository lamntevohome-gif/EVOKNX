import 'package:flutter/material.dart';

import 'app/app.dart';
import 'state/bus_controller.dart';
import 'state/project_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final project = ProjectController();
  await project.init();
  runApp(EvoknxApp(project: project, bus: BusController(project)));
}
