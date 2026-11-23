import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'diary_outbox.dart';

class SyncHttp {
  SyncHttp(this.endpoint, this.tokenForAccount, {SecurityContext? trust})
    : _client = HttpClient(context: trust) {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment) {
      throw ArgumentError('Sync requires an HTTPS endpoint.');
    }
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri endpoint;
  final Future<String?> Function(String accountId) tokenForAccount;
  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<List<Map<String, dynamic>>> changes(
    String accountId,
    int after,
  ) async {
    final token = await tokenForAccount(accountId);
    if (token == null) {
      throw const HttpException('Account session unavailable.');
    }
    const timeout = Duration(seconds: 10);
    final uri = endpoint
        .resolve('/v1/sync/changes')
        .replace(queryParameters: {'after': '$after', 'limit': '50'});
    final request = await _client.getUrl(uri).timeout(timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>().timeout(timeout);
      throw HttpException('Change retrieval failed (${response.statusCode}).');
    }
    final raw = await response.transform(utf8.decoder).join().timeout(timeout);
    final page = jsonDecode(raw);
    if (page is! List ||
        page.length > 50 ||
        page.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid change page.');
    }
    return page.cast<Map<String, dynamic>>();
  }

  Future<SyncResult> submit(String accountId, Map<String, dynamic> body) async {
    final token = await tokenForAccount(accountId);
    if (token == null) return const SyncResult(Delivery.unauthorized);
    try {
      final request = await _client
          .postUrl(endpoint.resolve('/v1/sync/operations'))
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final status = response.statusCode;
      final raw = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      if (status == 401 || status == 403) {
        return const SyncResult(Delivery.unauthorized);
      }
      if (status == 408 || status == 429 || status >= 500) {
        return const SyncResult(Delivery.retry);
      }
      if (status == 200) {
        final parsed = jsonDecode(raw);
        if (parsed is Map && parsed['operation_id'] == body['operation_id']) {
          return const SyncResult(Delivery.acknowledged);
        }
        return const SyncResult(Delivery.retry);
      }
      if (status == 409) {
        final parsed = jsonDecode(raw);
        final detail = parsed is Map ? parsed['detail'] : null;
        final current = detail is Map ? detail['current'] : null;
        return SyncResult(
          Delivery.conflict,
          remote: current is Map<String, dynamic> ? current : null,
        );
      }
      return const SyncResult(Delivery.rejected);
    } on TimeoutException {
      return const SyncResult(Delivery.retry);
    } on IOException {
      return const SyncResult(Delivery.retry);
    } on FormatException {
      return const SyncResult(Delivery.retry);
    }
  }
}
