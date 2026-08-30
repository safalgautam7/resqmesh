import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../models/emergency_report.dart';
import '../../services/api_service.dart';
import '../../services/auth_state.dart';
import '../../services/relay/relay_envelope.dart';
import '../../services/relay/relay_manager.dart';

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
  final _people = TextEditingController();
  bool _loading = false;
  String? _error;

  // Automatic GPS location (no manual typing — nobody types coordinates in an
  // emergency).
  bool _locating = false;
  bool _locationReady = false;
  bool _locationDenied = false;
  double? _lat;
  double? _lng;
  double? _accuracy;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  @override
  void dispose() {
    _description.dispose();
    _people.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    setState(() {
      _locating = true;
      _locationDenied = false;
    });
    try {
      var serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locating = false;
            _locationDenied = true;
          });
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locating = false;
            _locationDenied = true;
          });
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // Fast first fix: a rough position is better than none in an emergency.
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _accuracy = pos.accuracy;
          _locationReady = true;
          _locating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locating = false;
          _locationDenied = true;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Please describe what happened.');
      return;
    }
    final lat = _lat;
    final lng = _lng;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      // The server is unreachable (offline / no signal). Buffer the report in
      // the on-device outbox; it will be carried through the BLE mesh and
      // delivered to the backend by the nearest online device.
      final auth = context.read<AuthState>();
      final user = auth.currentUser.username;
      final envelope = RelayEnvelope.report(
        origin: user,
        description: _description.text.trim(),
        incidentType: _incidentType,
        latitude: lat,
        longitude: lng,
        peopleAffected: int.tryParse(_people.text),
      );
      context.read<RelayManager>().enqueueOutbox(envelope);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No connection — report saved offline. It will sync automatically when a device network link is found.')),
      );
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
            _buildLocationPanel(),
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

  /// Automatic location — captured from GPS on form open; no manual typing.
  Widget _buildLocationPanel() {
    if (_locating) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Getting your location…'),
          subtitle: Text('Using GPS so responders can find you.'),
        ),
      );
    }
    if (_locationDenied) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.location_off, color: Colors.red),
          title: const Text('Location unavailable'),
          subtitle: const Text('Your report will be sent without coordinates.'),
          trailing: TextButton(onPressed: _captureLocation, child: const Text('Retry')),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: Icon(
          _locationReady ? Icons.my_location : Icons.location_off,
          color: _locationReady ? Colors.teal : Colors.grey,
        ),
        title: Text(
          _locationReady
              ? '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}'
              : 'No location',
        ),
        subtitle: Text(
          _locationReady
              ? (_accuracy != null
                  ? 'GPS location (±${_accuracy!.toStringAsFixed(0)} m) — sent automatically'
                  : 'GPS location — sent automatically')
              : 'Turn on device location for GPS',
        ),
        trailing: _locationReady
            ? TextButton(onPressed: _captureLocation, child: const Text('Refresh'))
            : null,
      ),
    );
  }
}
