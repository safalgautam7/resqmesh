import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/citizen/citizen_home_screen.dart';
import 'screens/coordinator/coordinator_home_screen.dart';
import 'services/api_service.dart';
import 'services/auth_state.dart';
import 'theme.dart';

void main() => runApp(const ResqMeshApp());

class ResqMeshApp extends StatelessWidget {
  const ResqMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    return ChangeNotifierProvider(
      create: (_) => AuthState(api: api),
      child: MaterialApp(
        title: 'ResQMesh',
        debugShowCheckedModeBanner: false,
        theme: buildResqTheme(),
        home: const RootGate(),
        routes: {
          '/register': (_) => const RegisterScreen(),
          '/citizen-home': (_) => const CitizenHomeScreen(),
          '/coordinator-home': (_) => const CoordinatorHomeScreen(),
        },
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }
    if (auth.currentUser.isCoordinator) {
      return const CoordinatorHomeScreen();
    }
    return const CitizenHomeScreen();
  }
}
