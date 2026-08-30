import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_config.dart';
import '../models/emergency_report.dart';
import '../models/official_alert.dart';
import '../models/user.dart';
import 'relay/relay_envelope.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// True when the failure came from the network layer rather than the API
/// (i.e. the backend is unreachable) — used to render a friendly "offline"
/// state instead of a raw error. The `http` package surfaces connection
/// failures as `ClientException` on both Android and web.
bool isNetworkError(Object? error) {
  return error is http.ClientException || error is TimeoutException;
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

  static const _tokenKey = 'resqmesh_access_token';

  /// Upper bound for any single request. Without this, a call to a dead
  /// backend on the emulator can hang for the OS-level TCP timeout (tens of
  /// seconds or more), which makes the app feel stuck and delays recovery
  /// once the server comes back. Timing out fast keeps the UI responsive and
  /// lets the caller show the friendly offline state instead of a spinner.
  static const _timeout = Duration(seconds: 8);

  /// Run [fn] (a single network call) under [_timeout]. A timeout surfaces as
  /// a [TimeoutException], which [isNetworkError] recognises as "offline".
  Future<T> _guard<T>(Future<T> Function() fn) async {
    return fn().timeout(_timeout);
  }

  /// Restore a previously-persisted access token (survives app reloads —
  /// web page refresh, emulator restarts, etc.).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_tokenKey);
  }

  bool get hasToken => _accessToken != null;

  /// Set (and persist) the access token so a session survives reloads.
  Future<void> setToken(String? token) async {
    _accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

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
    final resp = await _guard(() => _client.post(
          _uri('/auth/login/'),
          headers: _headers,
          body: jsonEncode({'username': username, 'password': password}),
        ));
    if (resp.statusCode != 200) _throw(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return AuthData(access: data['access'] as String, refresh: data['refresh'] as String);
  }

  Future<User> register(String username, String password, {String? email}) async {
    final resp = await _guard(() => _client.post(
          _uri('/auth/register/'),
          headers: _headers,
          body: jsonEncode({
            'username': username,
            'password': password,
            if (email != null && email.isNotEmpty) 'email': email,
          }),
        ));
    if (resp.statusCode != 201) _throw(resp);
    return User.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<User> me() async {
    final resp = await _guard(() => _client.get(_uri('/auth/me/'), headers: _headers));
    if (resp.statusCode != 200) _throw(resp);
    return User.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ---- Reports ----
  Future<List<EmergencyReport>> getReports() async {
    final resp = await _guard(() => _client.get(_uri('/emergencies/'), headers: _headers));
    if (resp.statusCode != 200) _throw(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>;
    return results
        .map((e) => EmergencyReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EmergencyReport> getReportDetail(int id) async {
    final resp = await _guard(() => _client.get(_uri('/emergencies/$id/'), headers: _headers));
    if (resp.statusCode != 200) _throw(resp);
    return EmergencyReport.fromJsonDetail(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<EmergencyReport> createReport(EmergencyReport report) async {
    final resp = await _guard(() => _client.post(
          _uri('/emergencies/'),
          headers: _headers,
          body: jsonEncode(report.toCreatePayload()),
        ));
    if (resp.statusCode != 201) _throw(resp);
    return EmergencyReport.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<EmergencyReport> updateReportOperational(
    int id, {
    String? status,
    String? priority,
  }) async {
    final resp = await _guard(() => _client.patch(
          _uri('/emergencies/$id/'),
          headers: _headers,
          body: jsonEncode({
            'status': ?status,
            'priority': ?priority,
          }),
        ));
    if (resp.statusCode != 200) _throw(resp);
    return EmergencyReport.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Delete a report. The backend guards deletion: coordinators may only
  /// delete RESOLVED/CLOSED reports; a citizen may delete their own report
  /// while it is still SUBMITTED.
  Future<void> deleteReport(int id) async {
    final resp = await _guard(() => _client.delete(_uri('/emergencies/$id/'), headers: _headers));
    if (resp.statusCode != 204) _throw(resp);
  }

  // ---- Alerts ----
  Future<List<OfficialAlert>> getAlerts() async {
    final resp = await _guard(() => _client.get(_uri('/alerts/'), headers: _headers));
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
    final resp = await _guard(() => _client.post(
          _uri('/alerts/'),
          headers: _headers,
          body: jsonEncode({
            'title': title,
            'message': message,
            'severity': severity,
            'target_area': targetArea,
          }),
        ));
    if (resp.statusCode != 201) _throw(resp);
    return OfficialAlert.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ---- Relay (mesh recovery) ----
  /// Hand a carried relay envelope to the backend. Accepts both the initial
  /// delivery (201) and a dedup duplicate (200).
  Future<bool> deliverRelayMessage(RelayEnvelope env) async {
    final resp = await _guard(() => _client.post(
          _uri('/relay/messages/'),
          headers: _headers,
          body: jsonEncode({
            'message_id': env.id,
            'source': env.origin,
            'hops': env.hops,
            'max_hops': env.maxHops,
            'payload': env.payload,
          }),
        ));
    return resp.statusCode == 201 || resp.statusCode == 200;
  }
}
