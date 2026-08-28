import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/emergency_report.dart';
import '../models/official_alert.dart';
import '../models/user.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class AuthData {
  final String access;
  final String refresh;
  AuthData({required this.access, required this.refresh});
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _accessToken;

  void setToken(String? token) => _accessToken = token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Never _throw(http.Response resp) {
    String message = 'Request failed (${resp.statusCode})';
    try {
      final body = jsonDecode(resp.body);
      final detail = body['detail'] ?? body;
      if (detail is Map) {
        final parts = detail.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('; ');
        if (parts.isNotEmpty) message = parts;
      } else if (detail is String && detail.isNotEmpty) {
        message = detail;
      }
    } catch (_) {}
    throw ApiException(message, statusCode: resp.statusCode);
  }

  // ---- Auth ----
  Future<AuthData> login(String username, String password) async {
    final resp = await _client.post(
      _uri('/auth/login/'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (resp.statusCode != 200) _throw(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return AuthData(access: data['access'] as String, refresh: data['refresh'] as String);
  }

  Future<User> register(String username, String password, {String? email}) async {
    final resp = await _client.post(
      _uri('/auth/register/'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
      }),
    );
    if (resp.statusCode != 201) _throw(resp);
    return User.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<User> me() async {
    final resp = await _client.get(_uri('/auth/me/'), headers: _headers);
    if (resp.statusCode != 200) _throw(resp);
    return User.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ---- Reports ----
  Future<List<EmergencyReport>> getReports() async {
    final resp = await _client.get(_uri('/emergencies/'), headers: _headers);
    if (resp.statusCode != 200) _throw(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>;
    return results
        .map((e) => EmergencyReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EmergencyReport> getReportDetail(int id) async {
    final resp = await _client.get(_uri('/emergencies/$id/'), headers: _headers);
    if (resp.statusCode != 200) _throw(resp);
    return EmergencyReport.fromJsonDetail(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<EmergencyReport> createReport(EmergencyReport report) async {    final resp = await _client.post(
      _uri('/emergencies/'),
      headers: _headers,
      body: jsonEncode(report.toCreatePayload()),
    );
    if (resp.statusCode != 201) _throw(resp);
    return EmergencyReport.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<EmergencyReport> updateReportOperational(
    int id, {
    String? status,
    String? priority,
  }) async {
    final resp = await _client.patch(
      _uri('/emergencies/$id/'),
      headers: _headers,
      body: jsonEncode({
        'status': ?status,
        'priority': ?priority,
      }),
    );
    if (resp.statusCode != 200) _throw(resp);
    return EmergencyReport.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ---- Alerts ----
  Future<List<OfficialAlert>> getAlerts() async {
    final resp = await _client.get(_uri('/alerts/'), headers: _headers);
    if (resp.statusCode != 200) _throw(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>;
    return results
        .map((e) => OfficialAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<OfficialAlert> createAlert({
    required String title,
    required String message,
    String severity = 'WARNING',
    String targetArea = '',
  }) async {
    final resp = await _client.post(
      _uri('/alerts/'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'message': message,
        'severity': severity,
        'target_area': targetArea,
      }),
    );
    if (resp.statusCode != 201) _throw(resp);
    return OfficialAlert.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }
}
