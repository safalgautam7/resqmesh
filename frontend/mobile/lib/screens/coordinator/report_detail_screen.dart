import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/emergency_report.dart';
import '../../services/api_service.dart';
import '../../services/auth_state.dart';
import '../../theme.dart';

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({required this.report, super.key});
  final EmergencyReport report;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  static const _statuses = [
    'SUBMITTED',
    'REVIEWING',
    'VERIFIED',
    'IN_PROGRESS',
    'RESOLVED',
    'CLOSED'
  ];
  static const _priorities = [
    'UNASSIGNED',
    'LOW',
    'MEDIUM',
    'HIGH',
    'CRITICAL'
  ];

  late EmergencyReport _report;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  Future<void> _apply({String? status, String? priority}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await context.read<AuthState>().api.updateReportOperational(
            _report.id,
            status: status,
            priority: priority,
          );
      setState(() => _report = updated);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Update failed. Is the server reachable?');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Report RQ-${_report.id}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('ORIGINAL CITIZEN REPORT',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(_report.description, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 16),
            _keyValue('Incident type', _report.incidentType),
            _keyValue('Reporter', _report.reporterName),
            _keyValue('People affected',
                _report.peopleAffected?.toString() ?? 'Unknown'),
            _keyValue(
                'Location',
                (_report.latitude != null && _report.longitude != null)
                    ? '${_report.latitude}, ${_report.longitude}'
                    : 'Not provided'),
            _keyValue('Status', _report.status),
            _keyValue('Priority', _report.priority),
            _keyValue('Created',
                _report.createdAt.toLocal().toString().substring(0, 16)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            const Text('Change Status', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statuses.map((s) {
                return FilterChip(
                  label: Text(s),
                  selected: _report.status == s,
                  onSelected: _saving
                      ? null
                      : (_) => _apply(status: s),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text('Change Priority', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _priorities.map((p) {
                return FilterChip(
                  label: Text(p,
                      style: TextStyle(color: priorityColor(p), fontWeight: FontWeight.bold)),
                  selected: _report.priority == p,
                  onSelected: _saving ? null : (_) => _apply(priority: p),
                );
              }).toList(),
            ),
            if (_saving) const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }

  Widget _keyValue(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(k.toUpperCase(),
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}
