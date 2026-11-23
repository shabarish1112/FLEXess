import 'dart:async';

import 'package:fitness_diary/core/account_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fitness_diary/core/account_ui.dart';

class Vault implements SessionVault {
  String? value;
  bool unreadable = false;
  @override
  Future<String?> read() async {
    if (unreadable) throw StateError('Synthetic vault read failure');
    return value;
  }

  @override
  Future<void> write(String token) async => value = token;
  @override
  Future<void> clear() async => value = null;
}

class Gateway implements IdentityGateway {
  String owner = 'first';
  int renewals = 0;
  bool? signupIntent;
  bool invalid = false;
  String? revoked;
  bool hostedFailure = false;
  bool endBrowserCalled = false;
  String? hint;
  Completer<void>? blocked;
  final syncing = Completer<void>();

  @override
  Future<Tokens> authorize({required bool signup}) async {
    signupIntent = signup;
    if (invalid) throw StateError('Denied');
    return (
      access: 'first',
      refresh: 'initial',
      idToken: 'synthetic-id',
      expires: DateTime.now(),
    );
  }

  @override
  Future<Tokens> refresh(String token) async {
    renewals++;
    if (invalid) throw StateError('Expired');
    if (blocked != null) {
      syncing.complete();
      await blocked!.future;
    }
    return (
      access: 'renewed',
      refresh: 'rotated',
      idToken: null,
      expires: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<String> account(String token) async => owner;
  @override
  Future<void> revoke(String token) async => revoked = token;

  @override
  Future<void> endBrowserSession(String? idToken) async {
    endBrowserCalled = true;
    hint = idToken;
    if (hostedFailure) throw StateError('Synthetic browser cancellation');
  }
}

void main() {
  testWidgets('native adapter sends the configured AppAuth logout request', (
    tester,
  ) async {
    const channel = MethodChannel('crossingthestreams.io/flutter_appauth');
    final messenger = tester.binding.defaultBinaryMessenger;
    MethodCall? invocation;
    messenger.setMockMethodCallHandler(channel, (call) async {
      invocation = call;
      return <String, Object?>{};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final identity = NativeIdentity(
      const IdentityConfig(
        'https://tenant.invalid/',
        'urn:test',
        'public-client',
        'https://api.invalid/',
      ),
    );
    await identity.endBrowserSession(null);
    expect(invocation?.method, 'endSession');
    expect(
      invocation?.arguments,
      containsPair('issuer', 'https://tenant.invalid/'),
    );
    expect(
      invocation?.arguments,
      containsPair(
        'postLogoutRedirectUrl',
        'dev.independent.fitness_diary.auth://logout',
      ),
    );
    expect(
      invocation?.arguments,
      containsPair('additionalParameters', {'client_id': 'public-client'}),
    );
  });

  test('hosted logout cancellation preserves local sign-out', () async {
    final gateway = Gateway()..hostedFailure = true;
    final vault = Vault();
    final service = SessionManager(gateway, vault);
    await service.signIn(signup: false);
    await service.tokenFor('first');
    await expectLater(service.signOut(hosted: true), throwsStateError);
    expect(vault.value, isNull);
    expect(gateway.revoked, 'rotated');
    expect(gateway.endBrowserCalled, isTrue);
    expect(gateway.hint, 'synthetic-id');
    expect(await service.tokenFor('first'), isNull);
  });

  test(
    'a restored session can request hosted logout without an ID token hint',
    () async {
      final gateway = Gateway();
      final vault = Vault()..value = 'initial';
      final service = SessionManager(gateway, vault);
      await service.restore();
      await service.signOut(hosted: true);
      expect(vault.value, isNull);
      expect(gateway.endBrowserCalled, isTrue);
      expect(gateway.hint, isNull);
    },
  );

  testWidgets('a guest can clear a session that failed restoration', (
    tester,
  ) async {
    final vault = Vault()
      ..value = 'synthetic'
      ..unreadable = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityConfigProvider.overrideWithValue(
            const IdentityConfig(
              'https://tenant.invalid/',
              'urn:test',
              'public-client',
              'https://api.invalid/',
            ),
          ),
          sessionManagerProvider.overrideWithValue(
            SessionManager(Gateway(), vault),
          ),
        ],
        child: const MaterialApp(home: AccountPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Session unavailable'), findsOneWidget);
    await tester.tap(find.text('Clear saved session'));
    await tester.pumpAndSettle();
    expect(vault.value, isNull);
    expect(find.text('Session unavailable'), findsOneWidget);
  });

  test(
    'unreadable vault fails closed and logout still clears storage',
    () async {
      final vault = Vault()..value = 'synthetic';
      final service = SessionManager(Gateway(), vault);
      vault.unreadable = true;
      await expectLater(service.restore(), throwsStateError);
      expect(service.current, isNull);
      await expectLater(service.signOut(), throwsStateError);
      expect(vault.value, isNull);
      expect(await service.tokenFor('first'), isNull);
    },
  );

  test(
    'guest launch, signup, serialized renewal, restart and revocation',
    () async {
      final gateway = Gateway();
      final vault = Vault();
      final service = SessionManager(gateway, vault);
      expect(await service.restore(), isNull);
      expect((await service.signIn(signup: true)).id, 'first');
      expect(gateway.signupIntent, true);
      expect(vault.value, 'initial');
      expect(await service.tokenFor('other'), isNull);
      expect(
        await Future.wait([
          service.tokenFor('first'),
          service.tokenFor('first'),
        ]),
        ['renewed', 'renewed'],
      );
      expect(gateway.renewals, 1);
      expect(vault.value, 'rotated');
      final restored = SessionManager(gateway, vault);
      expect((await restored.restore())?.id, 'first');
      await restored.signOut();
      expect(vault.value, isNull);
      expect(gateway.revoked, 'rotated');
      expect(await restored.tokenFor('first'), isNull);
    },
  );

  test(
    'failed sign in, expired sessions and changed identity fail closed',
    () async {
      final gateway = Gateway()..invalid = true;
      final vault = Vault();
      final service = SessionManager(gateway, vault);
      await expectLater(service.signIn(signup: false), throwsStateError);
      expect(service.current, isNull);
      gateway.invalid = false;
      await service.signIn(signup: false);
      gateway.invalid = true;
      expect(await service.tokenFor('first'), isNull);
      expect(service.current, isNull);
      gateway.invalid = false;
      await service.signIn(signup: false);
      gateway.owner = 'other';
      expect(await service.tokenFor('first'), isNull);
      expect(service.current, isNull);
      expect(vault.value, isNull);
    },
  );

  test('logout during renewal does not publish a replacement token', () async {
    final gateway = Gateway()..blocked = Completer<void>();
    final vault = Vault();
    final service = SessionManager(gateway, vault);
    await service.signIn(signup: false);
    final renewing = service.tokenFor('first');
    await gateway.syncing.future;
    final logout = service.signOut();
    gateway.blocked!.complete();
    expect(await renewing, isNull);
    await logout;
    expect(service.current, isNull);
    expect(vault.value, isNull);
    expect(gateway.revoked, 'rotated');
  });
}
