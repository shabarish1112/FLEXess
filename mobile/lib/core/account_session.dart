import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class IdentityConfig {
  const IdentityConfig(this.issuer, this.audience, this.clientId, this.api);
  final String issuer, audience, clientId, api;

  static const environment = IdentityConfig(
    String.fromEnvironment('FLEX_IDENTITY_ISSUER'),
    String.fromEnvironment('FLEX_IDENTITY_AUDIENCE'),
    String.fromEnvironment('FLEX_IDENTITY_CLIENT_ID'),
    String.fromEnvironment('FLEX_API_URL'),
  );

  static const redirect = 'dev.independent.fitness_diary.auth://callback';
  static const logoutRedirect = 'dev.independent.fitness_diary.auth://logout';
  static const scopes = ['openid', 'profile', 'email', 'offline_access'];

  bool get configured =>
      // Browser authentication needs its own redirect and session design.
      !kIsWeb &&
      [issuer, api].every((value) {
        final uri = Uri.tryParse(value);
        return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment &&
            (uri.path.isEmpty || uri.path == '/');
      }) &&
      clientId.isNotEmpty &&
      audience.isNotEmpty;
}

typedef Tokens = ({
  String access,
  String? refresh,
  String? idToken,
  DateTime expires,
});
typedef AccountSession = ({String id, Tokens tokens});

abstract interface class IdentityGateway {
  Future<Tokens> authorize({required bool signup});
  Future<Tokens> refresh(String token);
  Future<String> account(String token);
  Future<void> revoke(String token);
  Future<void> endBrowserSession(String? idToken);
}

abstract interface class SessionVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureSessionVault implements SessionVault {
  SecureSessionVault(IdentityConfig config)
    : _key =
          'flex.refresh.${config.issuer}.${config.audience}.${config.clientId}.${config.api}';
  static const _storage = FlutterSecureStorage();
  final String _key;

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class NativeIdentity implements IdentityGateway {
  NativeIdentity(this.config);
  final IdentityConfig config;
  static const _appAuth = FlutterAppAuth();
  static const _timeout = Duration(seconds: 12);

  Tokens _tokens(TokenResponse response) {
    final access = response.accessToken;
    final expires = response.accessTokenExpirationDateTime;
    if (access == null ||
        access.isEmpty ||
        expires == null ||
        !expires.isAfter(DateTime.now())) {
      throw const FormatException('Invalid provider session.');
    }
    return (
      access: access,
      refresh: response.refreshToken,
      idToken: response.idToken,
      expires: expires,
    );
  }

  @override
  Future<Tokens> authorize({required bool signup}) async => _tokens(
    await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        config.clientId,
        IdentityConfig.redirect,
        issuer: config.issuer,
        scopes: IdentityConfig.scopes,
        promptValues: ['login'],
        additionalParameters: {
          'audience': config.audience,
          if (signup) 'screen_hint': 'signup',
        },
      ),
    ),
  );

  @override
  Future<Tokens> refresh(String token) async => _tokens(
    await _appAuth
        .token(
          TokenRequest(
            config.clientId,
            IdentityConfig.redirect,
            issuer: config.issuer,
            refreshToken: token,
            scopes: IdentityConfig.scopes,
          ),
        )
        .timeout(_timeout),
  );

  @override
  Future<String> account(String token) async {
    final raw = await _call(
      Uri.parse(config.api).resolve('/v1/me'),
      access: token,
    );
    final response = jsonDecode(raw);
    final id = response is Map ? response['id'] : null;
    if (id is! String || !_uuid.hasMatch(id)) {
      throw const FormatException('Invalid account response.');
    }
    return id;
  }

  @override
  Future<void> revoke(String token) async {
    await _call(
      Uri.parse(config.issuer).resolve('/oauth/revoke'),
      body: {'client_id': config.clientId, 'token': token},
    );
  }

  @override
  Future<void> endBrowserSession(String? idToken) async {
    await _appAuth.endSession(
      EndSessionRequest(
        issuer: config.issuer,
        idTokenHint: idToken,
        postLogoutRedirectUrl: IdentityConfig.logoutRedirect,
        additionalParameters: {'client_id': config.clientId},
      ),
    );
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  Future<String> _call(
    Uri uri, {
    String? access,
    Map<String, String>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .openUrl(body == null ? 'GET' : 'POST', uri)
          .timeout(_timeout);
      request.followRedirects = false;
      if (access != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $access');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Identity request rejected.');
      }
      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }
}

class SessionManager {
  SessionManager(this.gateway, this.vault);
  final IdentityGateway gateway;
  final SessionVault vault;
  AccountSession? current;
  Future<void> _tail = Future.value();
  bool _signingOut = false;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<AccountSession?> restore() => _serialize(() async {
    final stored = await vault.read();
    if (stored == null || _signingOut) return null;
    return _refresh(stored);
  });

  Future<AccountSession> signIn({required bool signup}) => _serialize(() async {
    final tokens = await gateway.authorize(signup: signup);
    return _accept(tokens);
  });

  Future<AccountSession> _accept(
    Tokens tokens, {
    String? fallback,
    String? expected,
  }) async {
    final refresh = tokens.refresh ?? fallback;
    // Store the rotated credential before validation so a network failure
    // after renewal does not strand the device with a revoked refresh token.
    if (fallback != null && refresh != null) await vault.write(refresh);
    final id = await gateway.account(tokens.access);
    if (_signingOut || (expected != null && id != expected)) {
      if (!_signingOut) await vault.clear();
      throw StateError('Account session changed.');
    }
    if (fallback == null) {
      if (refresh == null) {
        await vault.clear();
      } else {
        await vault.write(refresh);
      }
    }
    if (_signingOut) throw StateError('Account session changed.');
    return current = (
      id: id,
      tokens: (
        access: tokens.access,
        refresh: refresh,
        expires: tokens.expires,
        idToken:
            tokens.idToken ?? (expected == id ? current?.tokens.idToken : null),
      ),
    );
  }

  Future<AccountSession> _refresh(String token, {String? expected}) async =>
      _accept(
        await gateway.refresh(token),
        fallback: token,
        expected: expected,
      );

  Future<String?> tokenFor(String id) => _serialize(() async {
    final active = current;
    if (_signingOut || active == null || active.id != id) return null;
    if (active.tokens.expires.isAfter(
      DateTime.now().add(const Duration(seconds: 30)),
    )) {
      return active.tokens.access;
    }
    final refresh = active.tokens.refresh;
    if (refresh == null) return null;
    try {
      return (await _refresh(refresh, expected: id)).tokens.access;
    } catch (_) {
      current = null;
      return null;
    }
  });

  Future<void> signOut({bool hosted = false}) {
    if (_signingOut) {
      return Future.error(StateError('Sign-out already in progress.'));
    }
    final idToken = current?.tokens.idToken;
    _signingOut = true;
    current = null;
    return _serialize(() async {
      try {
        String? refresh;
        try {
          refresh = await vault.read();
        } finally {
          // A corrupt entry must not prevent an attempt to remove it.
          await vault.clear();
        }
        try {
          if (refresh != null) await gateway.revoke(refresh);
        } finally {
          if (hosted) await gateway.endBrowserSession(idToken);
        }
      } finally {
        _signingOut = false;
      }
    });
  }
}
