import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'data/push_notification_service.dart';
import 'screens/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  runApp(const RapidAlertApp());
}

class RapidAlertApp extends StatelessWidget {
  const RapidAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rapid Alert Responder',
      debugShowCheckedModeBanner: false,
      theme: buildRapidAlertTheme(),
      home: const AuthGate(),
    );
  }
}
