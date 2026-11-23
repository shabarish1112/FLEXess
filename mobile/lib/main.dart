import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/database_setup.dart';
import 'core/firebase_identity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabase();
  await FirebaseIdentity.initialize();
  runApp(const ProviderScope(child: FitnessApp()));
}
