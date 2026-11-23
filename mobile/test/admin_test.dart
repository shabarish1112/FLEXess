import 'dart:convert';
import 'package:fitness_diary/admin/admin_app.dart';
import 'package:fitness_diary/core/service_api.dart';
import 'package:fitness_diary/core/firebase_sign_in.dart';
import 'package:fitness_diary/ui/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('invalid phone input never reaches the authentication SDK', (
    tester,
  ) async {
    var authenticated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FirebaseSignIn(
              onAuthenticated: () async {
                authenticated = true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Request test code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose a country code'), findsOneWidget);
    expect(authenticated, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('real phone verification is blocked before reaching Firebase', (
    tester,
  ) async {
    var authenticated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FirebaseSignIn(
              onAuthenticated: () async {
                authenticated = true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '+16505551234',
    );
    await tester.tap(find.text('Request test code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Real SMS is disabled.'), findsOneWidget);
    expect(authenticated, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'global search uses the real catalog contract and opens its record',
    (tester) async {
      final api = ServiceApi(
        'https://api.invalid',
        () async => 'test-token',
        client: MockClient((request) async {
          if (request.url.path == '/v1/admin/catalog') {
            expect(request.url.queryParameters['q'], 'Apple');
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'test-food',
                    'name': 'Apple',
                    'category': 'Fruit',
                    'serving_grams': 100,
                    'energy_kcal': 52,
                    'protein_mg': 300,
                    'carbs_mg': 14000,
                    'fat_mg': 200,
                    'verified': true,
                    'revision': 1,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'id': 'test-account', 'role': 'admin'}),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: flexTheme(Brightness.dark),
          home: AdminShell(
            api: api,
            identity: const {'id': 'test-account', 'role': 'admin'},
            section: 5,
            onTheme: () {},
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Global search (Ctrl+K)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Apple');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Apple'), findsWidgets);
      await tester.tap(find.widgetWithText(ListTile, 'Apple'));
      await tester.pumpAndSettle();
      expect(find.text('Edit food'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );
  test(
    'service rejects unsafe endpoints and never follows token redirects',
    () async {
      expect(
        () => ServiceApi('http://api.invalid', () async => 'token'),
        throwsArgumentError,
      );
      final api = ServiceApi(
        'https://api.invalid',
        () async => 'test-token',
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['Authorization'], 'Bearer test-token');
          return http.Response('private raw response', 403);
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.call('/v1/admin/me'),
        throwsA(
          isA<ServiceError>().having(
            (e) => e.code,
            'safe error',
            isNot(contains('private raw')),
          ),
        ),
      );
    },
  );

  for (final size in [const Size(390, 844), const Size(1440, 960)]) {
    for (var section = 0; section < 6; section++) {
      testWidgets('admin section $section fits $size and uses protected API', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = ServiceApi(
          'https://api.invalid',
          () async => 'test-token',
          client: MockClient((request) async {
            expect(request.url.path, startsWith('/v1/admin/'));
            return http.Response(
              jsonEncode(switch (request.url.path) {
                '/v1/admin/users' ||
                '/v1/admin/catalog' => {'total': 0, 'items': []},
                '/v1/admin/audit' => {'items': []},
                '/v1/admin/me' => {'id': 'test-account', 'role': 'admin'},
                _ => {
                  'users': 0,
                  'enabled_accounts': 0,
                  'new_registrations': 0,
                  'catalog_foods': 0,
                  'growth': [],
                  'activity': {},
                  'legacy_registration_unknown': 0,
                  'definitions': {'users': 'All backend accounts'},
                },
              }),
              200,
            );
          }),
        );
        addTearDown(api.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: flexTheme(Brightness.dark),
            home: AdminShell(
              api: api,
              identity: const {'id': 'test-account', 'role': 'admin'},
              section: section,
              onTheme: () {},
              onSignOut: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Workspace / ${adminLabels[section]}'),
          findsOneWidget,
        );
        if (section == 2) {
          await tester.tap(find.text('Add food'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save food'));
          await tester.pumpAndSettle();
          expect(find.text('Required'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
  testWidgets('unconfigured admin fails closed', (tester) async {
    await tester.pumpWidget(const FlexAdmin());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Administration is not configured'),
      findsOneWidget,
    );
    expect(find.byType(AdminShell), findsNothing);
  });
  testWidgets('calorie ring respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: GoalRing(value: 0.6, label: '1200', detail: 'kcal consumed'),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      0.6,
    );
  });
}
