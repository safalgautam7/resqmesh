import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/agent_analysis.dart';
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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final detail =
          await context.read<AuthState>().api.getReportDetail(_report.id);
      if (mounted) setState(() => _report = detail);
    } catch (_) {
      // Detail fetch is best-effort; the base report still renders.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator())),
            if (!_loading && _report.analysis != null)
              _buildAiPanel(_report.analysis!),
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

  Widget _buildAiPanel(AgentAnalysis analysis) {
    final suggested = analysis.suggestedPriority;
    return Card(
      color: const Color(0xFFF0F6FF),
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF1F6FB2)),
                const SizedBox(width: 6),
                const Text('AI SUGGESTION',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Text('provider: ${analysis.provider}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _kv('Suggested priority', suggested ?? '—')),
              Expanded(
                  child: _kv('Incident', analysis.incidentType)),
            ]),
            const SizedBox(height: 6),
            _kv('Uncertainty', '${analysis.uncertaintyScore} (${analysis.uncertaintyLevel})'),
            if (analysis.rationale.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Why: ${analysis.rationale}',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 10),
            if (suggested != null && suggested != _report.priority)
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () => _acceptSuggestion(suggested),
                icon: const Icon(Icons.check),
                label: const Text('Accept suggested priority'),
              )
            else
              const Text('Suggestion already applied.',
                  style: TextStyle(fontSize: 12, color: Colors.green)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k.toUpperCase(),
            style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        Text(v),
      ],
    );
  }

  Future<void> _acceptSuggestion(String priority) async {
    await _apply(priority: priority);
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
