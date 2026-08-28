import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/emergency_report.dart';
import '../../services/auth_state.dart';
import '../../theme.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<EmergencyReport>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EmergencyReport>> _load() async {
    return context.read<AuthState>().api.getReports();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
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
                  const Text('Could not load reports'),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            );
          }
          final reports = snap.data ?? [];
          if (reports.isEmpty) {
            return const Center(
                child: Text('No reports yet. Tap "Get Help" when needed.'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: reports.length,
              itemBuilder: (context, i) => _ReportTile(report: reports[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});
  final EmergencyReport report;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('RQ-${report.id}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: priorityColor(report.priority).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(report.priority,
                      style: TextStyle(
                          color: priorityColor(report.priority),
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(report.description),
            const SizedBox(height: 8),
            Text('Status: ${report.status}',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
