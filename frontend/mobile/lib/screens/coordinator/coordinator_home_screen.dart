import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/emergency_report.dart';
import '../../services/auth_state.dart';
import '../../theme.dart';
import 'create_alert_screen.dart';
import 'report_detail_screen.dart';

class CoordinatorHomeScreen extends StatefulWidget {
  const CoordinatorHomeScreen({super.key});

  @override
  State<CoordinatorHomeScreen> createState() => _CoordinatorHomeScreenState();
}

class _CoordinatorHomeScreenState extends State<CoordinatorHomeScreen> {
  late Future<List<EmergencyReport>> _future;
  String? _statusFilter;
  String? _priorityFilter;

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

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EmergencyReport>> _load() =>
      context.read<AuthState>().api.getReports();

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _openDetail(EmergencyReport report) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReportDetailScreen(report: report)),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ResQMesh Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: 'Create official alert',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateAlertScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: FutureBuilder<List<EmergencyReport>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load reports: ${snap.error}'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                      onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            );
          }
          var reports = snap.data ?? [];
          if (_statusFilter != null) {
            reports = reports
                .where((r) => r.status == _statusFilter)
                .toList();
          }
          if (_priorityFilter != null) {
            reports =
                reports.where((r) => r.priority == _priorityFilter).toList();
          }
          final all = snap.data ?? [];
          return Column(
            children: [
              _SummaryBar(reports: all),
              _FilterBar(
                statusFilter: _statusFilter,
                priorityFilter: _priorityFilter,
                statuses: _statuses,
                priorities: _priorities,
                onStatus: (v) => setState(() =>
                    _statusFilter = (_statusFilter == v) ? null : v),
                onPriority: (v) => setState(() =>
                    _priorityFilter = (_priorityFilter == v) ? null : v),
                onClear: () => setState(() {
                  _statusFilter = null;
                  _priorityFilter = null;
                }),
              ),
              Expanded(
                child: reports.isEmpty
                    ? const Center(child: Text('No reports match.'))
                    : RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: reports.length,
                          itemBuilder: (context, i) => _CoordReportCard(
                            report: reports[i],
                            onTap: () => _openDetail(reports[i]),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.reports});
  final List<EmergencyReport> reports;

  @override
  Widget build(BuildContext context) {
    int count(String p) => reports.where((r) => r.priority == p).length;
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat('CRITICAL', count('CRITICAL'), Colors.red),
          _Stat('HIGH', count('HIGH'), Colors.orange),
          _Stat('MEDIUM', count('MEDIUM'), Colors.amber),
          _Stat('LOW', count('LOW'), Colors.green),
          _Stat('UNASSIGNED', count('UNASSIGNED'), Colors.grey),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.statusFilter,
    required this.priorityFilter,
    required this.statuses,
    required this.priorities,
    required this.onStatus,
    required this.onPriority,
    required this.onClear,
  });
  final String? statusFilter;
  final String? priorityFilter;
  final List<String> statuses;
  final List<String> priorities;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onPriority;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFilter = statusFilter != null || priorityFilter != null;
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: statuses
                  .map((s) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(s),
                          selected: statusFilter == s,
                          onSelected: (_) => onStatus(s),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...priorities.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(p),
                        selected: priorityFilter == p,
                        onSelected: (_) => onPriority(p),
                      ),
                    )),
                if (hasFilter)
                  TextButton(onPressed: onClear, child: const Text('Clear')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordReportCard extends StatelessWidget {
  const _CoordReportCard({required this.report, required this.onTap});
  final EmergencyReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: priorityColor(report.priority).withValues(alpha: 0.2),
          child: Icon(Icons.emergency,
              color: priorityColor(report.priority)),
        ),
        title: Text(report.description,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${report.incidentType} · ${report.reporterName} · ${report.createdAt.toLocal().toString().substring(0, 16)}'),
            Text('Status: ${report.status} · Priority: ${report.priority}',
                style: TextStyle(
                    color: priorityColor(report.priority),
                    fontWeight: FontWeight.w500)),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
