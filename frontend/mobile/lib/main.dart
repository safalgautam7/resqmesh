import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/citizen/citizen_home_screen.dart';
import 'screens/coordinator/coordinator_home_screen.dart';
import 'services/api_service.dart';
import 'services/auth_state.dart';
import 'services/relay/relay_manager.dart';
import 'theme.dart';
import 'widgets/mesh_notification_listener.dart';

void main() => runApp(const ResqMeshApp());

class ResqMeshApp extends StatefulWidget {
  const ResqMeshApp({super.key});

  @override
  State<ResqMeshApp> createState() => _ResqMeshAppState();
}

class _ResqMeshAppState extends State<ResqMeshApp> {
  late final ApiService _api = ApiService();
  late final AuthState _auth = AuthState(api: _api);
  late final RelayManager _relay = RelayManager(api: _api);

  @override
  void initState() {
    super.initState();
    _auth.addListener(_syncRelay);
    unawaited(_auth.restoreSession());
  }

  @override
  void dispose() {
    _auth.removeListener(_syncRelay);
    _relay.stop();
    super.dispose();
  }

  void _syncRelay() {
    if (_auth.isAuthenticated) {
      _relay.start();
    } else {
      _relay.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _auth,
      child: ChangeNotifierProvider.value(
        value: _relay,
        child: MaterialApp(
          title: 'ResQMesh',
          debugShowCheckedModeBanner: false,
          theme: buildResqTheme(),
          builder: (context, child) =>
              MeshNotificationListener(child: child ?? const SizedBox()),
          home: const RootGate(),
          routes: {
            '/register': (_) => const RegisterScreen(),
            '/citizen-home': (_) => const CitizenHomeScreen(),
            '/coordinator-home': (_) => const CoordinatorHomeScreen(),
          },
        ),
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    // Keep the restore/validation attempt out of the login gate so a reload
    // doesn't flash a login screen before a saved session is restored.
    if (!auth.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }
    if (auth.currentUser.isCoordinator) {
      return const CoordinatorHomeScreen();
    }
    return const CitizenHomeScreen();
  }
}