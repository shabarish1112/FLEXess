import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_session.dart';
import 'firebase_identity.dart';
import 'firebase_sign_in.dart';
import 'service_api.dart';

final identityConfigProvider = Provider((_) => IdentityConfig.environment);
final sessionManagerProvider = Provider((ref) {
  final config = ref.watch(identityConfigProvider);
  return SessionManager(NativeIdentity(config), SecureSessionVault(config));
});

final accountProvider = AsyncNotifierProvider<AccountController, String?>(
  AccountController.new,
);

class AccountController extends AsyncNotifier<String?> {
  String? _firebaseAccount;
  String? _firebaseUid;
  @override
  Future<String?> build() async {
    final config = ref.watch(identityConfigProvider);
    if (config.configured) {
      final legacy = (await ref.watch(sessionManagerProvider).restore())?.id;
      if (legacy != null) return legacy;
    }
    if (FirebaseIdentity.ready && FirebaseIdentity.auth.currentUser != null) {
      return _firebaseId();
    }
    return null;
  }

  Future<String> _firebaseId({String? expected}) async {
    final firebaseUser = FirebaseIdentity.auth.currentUser;
    final api = ServiceApi(
      ref.read(identityConfigProvider).api,
      () async => FirebaseIdentity.auth.currentUser?.getIdToken(),
    );
    try {
      final result = await api.call('/v1/me');
      final id = result['id'];
      if (id is! String ||
          !RegExp(
            r'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
          ).hasMatch(id)) {
        throw const FormatException('Invalid account response');
      }
      if ((expected != null && expected != id) ||
          firebaseUser == null ||
          FirebaseIdentity.auth.currentUser?.uid != firebaseUser.uid) {
        throw StateError('Account changed. No records were transferred.');
      }
      _firebaseUid = firebaseUser.uid;
      return _firebaseAccount = id;
    } finally {
      api.close();
    }
  }

  Future<void> acceptFirebase() async {
    final existing = state.asData?.value;
    if (existing != null && _firebaseAccount == null) {
      final legacyToken = await ref
          .read(sessionManagerProvider)
          .tokenFor(existing);
      final api = ServiceApi(
        ref.read(identityConfigProvider).api,
        () async => legacyToken,
      );
      try {
        final token = await FirebaseIdentity.auth.currentUser?.getIdToken(true);
        if (token == null) throw StateError('Session unavailable');
        await api.call('/v1/account/link', body: {'token': token});
      } finally {
        api.close();
      }
    }
    final id = await _firebaseId(expected: existing);
    if (ref.mounted) state = AsyncData(id);
  }

  Future<void> signIn({required bool signup}) async {
    if (!ref.read(identityConfigProvider).configured) {
      throw StateError('Identity is not configured.');
    }
    final session = await ref
        .read(sessionManagerProvider)
        .signIn(signup: signup);
    if (ref.mounted) state = AsyncData(session.id);
  }

  Future<void> signOut({bool hosted = false}) async {
    final manager = ref.read(sessionManagerProvider);
    state = const AsyncData(null);
    _firebaseAccount = null;
    _firebaseUid = null;
    try {
      try {
        await FirebaseIdentity.signOut();
      } finally {
        await manager.signOut(hosted: hosted);
      }
    } catch (_) {
      if (ref.mounted && state.asData?.value == null) {
        state = AsyncError(
          StateError('Sign-out could not be fully confirmed.'),
          StackTrace.current,
        );
      }
      rethrow;
    }
  }

  Future<String?> tokenFor(String id) async {
    if (_firebaseAccount == id &&
        state.asData?.value == id &&
        FirebaseIdentity.ready &&
        FirebaseIdentity.auth.currentUser?.uid == _firebaseUid) {
      return FirebaseIdentity.auth.currentUser?.getIdToken();
    }
    final token = await ref.read(sessionManagerProvider).tokenFor(id);
    if (token == null && ref.mounted && state.asData?.value == id) {
      state = AsyncError(
        StateError('Account session expired.'),
        StackTrace.current,
      );
    }
    return token;
  }
}

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key, this.sync, this.transfer});
  final Future<String> Function()? sync;
  final Future<String> Function()? transfer;

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  bool busy = false;
  String? message;

  Future<void> run(Future<void> Function() action, String failure) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => message = failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountProvider);
    final id = state.asData?.value;
    final configured = ref.watch(identityConfigProvider).configured;
    final controller = ref.read(accountProvider.notifier);
    void authorize(bool signup) => run(
      () => controller.signIn(signup: signup),
      'Sign-in did not finish. Check the browser or try again.',
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (kIsWeb && !FirebaseIdentity.ready)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Browser edition: records stay in this browser on this site. '
                'Clearing site data removes them. They are not backed up or '
                'shared with Android. Cloud sign-in is unavailable.',
              ),
            ),
          if (state.isLoading || busy) const LinearProgressIndicator(),
          if (FirebaseIdentity.ready)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: FirebaseSignIn(
                onBusyChanged: (value) {
                  if (mounted) setState(() => busy = value);
                },
                link: id != null && FirebaseIdentity.auth.currentUser != null,
                onAuthenticated: controller.acceptFirebase,
              ),
            ),
          if (id == null) ...[
            Text(state.hasError ? 'Session unavailable' : 'Guest mode'),
            if (!configured && !FirebaseIdentity.ready)
              const Text('Account access is unavailable in this build.'),
            if (configured && state.hasError)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(
                        controller.signOut,
                        'Credential cleanup or revocation could not be confirmed.',
                      ),
                child: const Text('Clear saved session'),
              ),
            if (configured) ...[
              FilledButton(
                onPressed: busy || state.isLoading
                    ? null
                    : () => authorize(false),
                child: const Text('Sign in'),
              ),
              OutlinedButton(
                onPressed: busy || state.isLoading
                    ? null
                    : () => authorize(true),
                child: const Text('Create account'),
              ),
              const Text(
                'Use Forgot password on the hosted sign-in page to recover access.',
              ),
            ],
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Continue as guest'),
            ),
          ] else ...[
            const Text('Signed in'),
            SelectableText(id),
            if (widget.transfer != null)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(
                        () async {
                          final result = await widget.transfer!();
                          if (mounted) {
                            setState(() {
                              message = result;
                            });
                          }
                        },
                        'Transfer could not be staged. Guest data is still on this device.',
                      ),
                child: const Text('Transfer guest records'),
              ),
            if (widget.sync != null)
              FilledButton(
                onPressed: busy
                    ? null
                    : () => run(
                        () async {
                          final result = await widget.sync!();
                          if (mounted) setState(() => message = result);
                        },
                        'Sync interrupted. Saved entries are still on this device.',
                      ),
                child: const Text('Sync diary'),
              ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(
                      controller.signOut,
                      'Account closed. Credential cleanup or provider revocation could not be confirmed.',
                    ),
              child: const Text('Sign out'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(
                      () => controller.signOut(hosted: true),
                      'Browser logout could not be confirmed. FLEX is signed out.',
                    ),
              child: const Text('Sign out of browser too'),
            ),
          ],
          if (message != null)
            Semantics(liveRegion: true, child: Text(message!)),
        ],
      ),
    );
  }
}
