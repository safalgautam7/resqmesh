import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'api_service.dart';

class AuthState extends ChangeNotifier {
  AuthState({required this.api});
  final ApiService api;

  bool _isAuthenticated = false;
  User? _user;

  bool get isAuthenticated => _isAuthenticated;
  User? get user => _user;

  User get currentUser {
    final u = _user;
    if (u == null) throw StateError('Not authenticated');
    return u;
  }

  Future<void> login(String username, String password) async {
    final tokens = await api.login(username, password);
    api.setToken(tokens.access);
    _user = await api.me();
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> register(String username, String password, {String? email}) async {
    await api.register(username, password, email: email);
    // Auto-login after registration
    await login(username, password);
  }

  Future<void> bootstrap() async {
    if (!_isAuthenticated) return;
    try {
      _user = await api.me();
      notifyListeners();
    } catch (_) {
      await logout();
    }
  }

  Future<void> logout() async {
    api.setToken(null);
    _isAuthenticated = false;
    _user = null;
    notifyListeners();
  }
}
