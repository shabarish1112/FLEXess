import 'package:flutter/material.dart';
import 'core/firebase_identity.dart';
import 'admin/admin_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseIdentity.initialize();
  runApp(const FlexAdmin());
}
