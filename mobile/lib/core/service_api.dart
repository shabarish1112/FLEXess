import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ServiceError implements Exception {
  const ServiceError(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => code;
}

class ServiceApi {
  ServiceApi(this.endpoint, this.token, {http.Client? client})
    : _client = client ?? http.Client() {
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError('A service requires an HTTPS origin.');
    }
  }
  final String endpoint;
  final Future<String?> Function() token;
  final http.Client _client;
  void close() => _client.close();

  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final access = await token();
    if (access == null) {
      throw const ServiceError(401, 'authentication_required');
    }
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            Uri.parse(endpoint).resolve(path).replace(queryParameters: query),
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $access',
            'Content-Type': 'application/json',
          });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 15)),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      // Never display raw server responses, credentials or personal data.
      throw ServiceError(response.statusCode, switch (response.statusCode) {
        401 => 'Sign in again to continue.',
        403 =>
          'Access denied. Check your role or sign in again for a sensitive action.',
        409 =>
          'Conflict: refresh the record. Existing accounts cannot be merged automatically.',
        422 => 'Check the form values.',
        429 => 'Too many requests. Retry in one minute.',
        _ => 'Service unavailable. Retry shortly.',
      });
    }
    final value = jsonDecode(response.body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid service response');
    }
    return value;
  }
}
