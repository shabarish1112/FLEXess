import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseIdentity {
  static const environment = String.fromEnvironment(
    'FLEX_ENVIRONMENT',
    defaultValue: 'production',
  );
  static const phoneTests = bool.fromEnvironment('FLEX_FIREBASE_PHONE_TESTS');
  static const testNumbers = String.fromEnvironment(
    'FLEX_FIREBASE_TEST_PHONE_NUMBERS',
  );
  static bool allowsTestNumber(String number) =>
      environment == 'development' &&
      phoneTests &&
      testNumbers
          .split(',')
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty)
          .contains(number);
  static const project = String.fromEnvironment('FLEX_FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('FLEX_FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FLEX_FIREBASE_APP_ID');
  static const sender = String.fromEnvironment('FLEX_FIREBASE_SENDER_ID');
  static const authDomain = String.fromEnvironment('FLEX_FIREBASE_AUTH_DOMAIN');
  static const googleClient = String.fromEnvironment(
    'FLEX_GOOGLE_SERVER_CLIENT_ID',
  );
  static bool get configured =>
      [project, apiKey, appId, sender].every((s) => s.isNotEmpty);
  static bool ready = false;
  static Future<void>? _googleInitialization;
  static FirebaseAuth get auth => FirebaseAuth.instance;

  static Future<void> initialize() async {
    if (!configured) return;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: sender,
          projectId: project,
          authDomain: authDomain.isEmpty
              ? '$project.firebaseapp.com'
              : authDomain,
        ),
      );
      await auth.authStateChanges().first;
      ready = true;
    } catch (_) {
      // Local diary access must survive a provider/configuration failure.
      ready = false;
    }
  }

  static Future<void> google({bool link = false}) async {
    final user = auth.currentUser;
    if (link && user == null) {
      throw StateError('Sign in before linking a provider.');
    }
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      if (link) {
        await user!.linkWithPopup(provider);
      } else {
        await auth.signInWithPopup(provider);
      }
    } else {
      await (_googleInitialization ??= GoogleSignIn.instance.initialize(
        serverClientId: googleClient.isEmpty ? null : googleClient,
      ));
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      if (link) {
        await user!.linkWithCredential(credential);
      } else {
        await auth.signInWithCredential(credential);
      }
    }
  }

  static Future<void> credential(
    AuthCredential credential, {
    required bool link,
  }) async {
    if (link) {
      final user = auth.currentUser;
      if (user == null) throw StateError('Session expired.');
      await user.linkWithCredential(credential);
    } else {
      await auth.signInWithCredential(credential);
    }
  }

  static Future<void> signOut() async {
    if (!ready) return;
    try {
      await auth.signOut();
    } finally {
      if (!kIsWeb && _googleInitialization != null) {
        await GoogleSignIn.instance.signOut();
      }
    }
  }
}
