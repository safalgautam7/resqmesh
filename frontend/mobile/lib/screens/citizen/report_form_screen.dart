import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/emergency_report.dart';
import '../../services/api_service.dart';
import '../../services/auth_state.dart';

class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  static const _types = [
    ('MEDICAL', 'Medical', Icons.medical_services),
    ('BUILDING_COLLAPSE', 'Building Collapse', Icons.apartment),
    ('FIRE', 'Fire', Icons.local_fire_department),
    ('FLOOD', 'Flood', Icons.waves),
    ('LANDSLIDE', 'Landslide', Icons.terrain),
    ('TRAPPED', 'Trapped', Icons.no_meals),
    ('OTHER', 'Other', Icons.help),
  ];

  String _incidentType = 'OTHER';
  final _description = TextEditingController();
  bool _addLocation = false;
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _people = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _lat.dispose();
    _lng.dispose();
    _people.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Please describe what happened.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      double? lat;
      double? lng;
      if (_addLocation) {
        lat = double.tryParse(_lat.text);
        lng = double.tryParse(_lng.text);
        if (lat == null || lng == null) {
          setState(() {
            _loading = false;
            _error = 'Please enter valid coordinates or turn off location.';
          });
          return;
        }
      }
      final report = EmergencyReport(
        id: 0,
        reporter: 0,
        reporterName: '',
        description: _description.text.trim(),
        incidentType: _incidentType,
        latitude: lat,
        longitude: lng,
        peopleAffected: int.tryParse(_people.text),
        status: 'SUBMITTED',
        priority: 'UNASSIGNED',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final saved =
          await context.read<AuthState>().api.createReport(report);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Report submitted. Your ID: RQ-${saved.id}. Help is on the way.')),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not submit. Is your connection available?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Emergency')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('What happened?', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _types.map((t) {
                final selected = t.$1 == _incidentType;
                return ChoiceChip(
                  avatar: Icon(t.$3, size: 20),
                  label: Text(t.$2),
                  selected: selected,
                  onSelected: (_) => setState(() => _incidentType = t.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text('Describe what happened:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g. We are trapped in a building near KU. One person is injured.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _people,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of people (optional)',
                prefixIcon: Icon(Icons.group),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Add my location'),
              subtitle: const Text('Helps responders find you (optional)'),
              value: _addLocation,
              onChanged: (v) => setState(() => _addLocation = v),
            ),
            if (_addLocation) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Longitude'),
                    ),
                  ),
                ],
              ),
            ],
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
                  : const Text('SEND EMERGENCY REPORT'),
            ),
          ],
        ),
      ),
    );
  }
}
