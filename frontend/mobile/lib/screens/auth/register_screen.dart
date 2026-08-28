import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_state.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context
          .read<AuthState>()
          .register(_username.text.trim(), _password.text, email: _email.text.trim());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                  labelText: 'Username', prefixIcon: Icon(Icons.person)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email (optional)', prefixIcon: Icon(Icons.email)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Password', prefixIcon: Icon(Icons.lock)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline)),
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
                  : const Text('REGISTER'),
            ),
          ],
        ),
      ),
    );
  }
}
