import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/bootstrap/app_bootstrap.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final bootstrap = await AppBootstrap.load(args);
  runApp(
    RePaperTodoApp(
      controller: bootstrap.controller,
      store: bootstrap.store,
    ),
  );
}
