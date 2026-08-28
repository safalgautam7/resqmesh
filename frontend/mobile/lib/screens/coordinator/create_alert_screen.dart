import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_state.dart';

class CreateAlertScreen extends StatefulWidget {
  const CreateAlertScreen({super.key});

  @override
  State<CreateAlertScreen> createState() => _CreateAlertScreenState();
}

class _CreateAlertScreenState extends State<CreateAlertScreen> {
  static const _severities = ['INFO', 'WARNING', 'HIGH', 'CRITICAL'];

  final _title = TextEditingController();
  final _message = TextEditingController();
  final _area = TextEditingController();
  String _severity = 'WARNING';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _message.text.trim().isEmpty) {
      setState(() => _error = 'Title and message are required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().api.createAlert(
            title: _title.text.trim(),
            message: _message.text.trim(),
            severity: _severity,
            targetArea: _area.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Official alert published.')));
      Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not publish alert.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Official Alert')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Title', prefixIcon: Icon(Icons.title)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Alert message',
                hintText: 'e.g. Flood warning: move to higher ground.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _area,
              decoration: const InputDecoration(
                  labelText: 'Target area (optional)',
                  prefixIcon: Icon(Icons.place)),
            ),
            const SizedBox(height: 16),
            const Text('Severity:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _severities.map((s) {
                return ChoiceChip(
                  label: Text(s),
                  selected: _severity == s,
                  onSelected: (_) => setState(() => _severity = s),
                );
              }).toList(),
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
                  : const Text('PUBLISH OFFICIAL ALERT'),
            ),
          ],
        ),
      ),
    );
  }
}
