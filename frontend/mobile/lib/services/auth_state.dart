import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'api_service.dart';

class AuthState extends ChangeNotifier {
  AuthState({required this.api});
  final ApiService api;

  bool _isAuthenticated = false;
  bool _ready = false;
  User? _user;

  bool get isAuthenticated => _isAuthenticated;
  bool get ready => _ready;
  User? get user => _user;

  User get currentUser {
    final u = _user;
    if (u == null) throw StateError('Not authenticated');
    return u;
  }

  /// Called once at startup: reload a persisted token, then validate it via
  /// `/me`. Sets [ready] so the UI can render either the app or the login
  /// screen after the restore attempt.
  Future<void> restoreSession() async {
    try {
      await api.init();
      if (api.hasToken) {
        try {
          _user = await api.me();
          _isAuthenticated = true;
        } catch (_) {
          await api.setToken(null); // stale/expired token — start fresh
        }
      }
    } finally {
      _ready = true;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    final tokens = await api.login(username, password);
    await api.setToken(tokens.access);
    _user = await api.me();
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> register(String username, String password, {String? email}) async {
    await api.register(username, password, email: email);
    // Auto-login after registration
    await login(username, password);
  }

  Future<void> logout() async {
    await api.setToken(null);
    _isAuthenticated = false;
    _user = null;
    notifyListeners();
  }
}
