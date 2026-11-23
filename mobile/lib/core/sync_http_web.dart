import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'diary_outbox.dart';

class SyncHttp {
  SyncHttp(this.endpoint, this.tokenForAccount) {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment) {
      throw ArgumentError('Sync requires HTTPS.');
    }
  }
  final Uri endpoint;
  final Future<String?> Function(String) tokenForAccount;
  final _client = http.Client();
  void close() => _client.close();

  Future<http.Response> request(
    String path,
    String token, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final req =
        http.Request(
            body == null ? 'GET' : 'POST',
            endpoint.resolve(path).replace(queryParameters: query),
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          });
    if (body != null) req.body = jsonEncode(body);
    return http.Response.fromStream(
      await _client.send(req).timeout(const Duration(seconds: 10)),
    ).timeout(const Duration(seconds: 10));
  }

  Future<List<Map<String, dynamic>>> changes(
    String accountId,
    int after,
  ) async {
    final token = await tokenForAccount(accountId);
    if (token == null) throw StateError('Account session unavailable.');
    final response = await request(
      '/v1/sync/changes',
      token,
      query: {'after': '$after', 'limit': '50'},
    );
    if (response.statusCode != 200) {
      throw StateError('Change retrieval failed.');
    }
    final page = jsonDecode(response.body);
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
      final response = await request('/v1/sync/operations', token, body: body);
      final status = response.statusCode;
      if (status == 401 || status == 403) {
        return const SyncResult(Delivery.unauthorized);
      }
      if (status == 408 || status == 429 || status >= 500) {
        return const SyncResult(Delivery.retry);
      }
      if (status == 200) {
        final parsed = jsonDecode(response.body);
        return SyncResult(
          parsed is Map && parsed['operation_id'] == body['operation_id']
              ? Delivery.acknowledged
              : Delivery.retry,
        );
      }
      if (status == 409) {
        final parsed = jsonDecode(response.body);
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
    } on http.ClientException {
      return const SyncResult(Delivery.retry);
    } on FormatException {
      return const SyncResult(Delivery.retry);
    }
  }
}
