import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().login(_username.text.trim(), _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Is it running?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emergency, color: Color(0xFFB71C1C), size: 72),
                const SizedBox(height: 12),
                const Text('ResQMesh',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const Text('Emergency Communication',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 32),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(
                      labelText: 'Username', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('LOG IN'),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/register'),
                  child: const Text('Create an account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
