import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/emergency_report.dart';
import '../../services/api_service.dart';
import '../../services/auth_state.dart';
import '../../theme.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key, this.isActive = true});

  /// When true the tab is visible; the report list reloads each time it
  /// transitions to visible so newly-delivered offline reports appear.
  final bool isActive;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<EmergencyReport>> _future;

  /// True while a delete request is in flight; shows a blocking "Deleting…"
  /// overlay over the list. Kept as plain state (NOT a route) so we never race
  /// the Navigator/overlay when the request completes.
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant MyReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when the tab becomes visible (and we were previously hidden).
    if (widget.isActive && !oldWidget.isActive) {
      _reload();
    }
  }

  Future<List<EmergencyReport>> _load() async {
    return context.read<AuthState>().api.getReports();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _delete(EmergencyReport report) async {
    final api = context.read<AuthState>().api;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text(
            'RQ-${report.id} will be removed permanently from the system. '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await api.deleteReport(report.id);
      if (!mounted) return;
      _deleting = false;
      _reload();
      messenger.showSnackBar(
        SnackBar(content: Text('RQ-${report.id} deleted.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _deleting = false;
      // The report is already gone on the server (e.g. deleted earlier) —
      // treat that as success and just refresh rather than alarming the user.
      if (e.statusCode == 404) {
        _reload();
        messenger.showSnackBar(
            const SnackBar(content: Text('Report already deleted.')));
        return;
      }
      messenger.showSnackBar(
          SnackBar(content: Text('Cannot delete: ${e.message}')));
    } catch (_) {
      // A network-layer error here is ambiguous: the request may have reached
      // the server and committed the deletion before the response was lost
      // (the delete clears the report even though we couldn't read the result).
      // Refresh so the list reflects whatever actually happened, and let the
      // user know rather than wrongly claiming "no connection".
      if (!mounted) return;
      _deleting = false;
      _reload();
      messenger.showSnackBar(
        const SnackBar(content: Text('Delete sent — list refreshed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: Stack(
        children: [
          FutureBuilder<List<EmergencyReport>>(
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
                  Icon(isNetworkError(snap.error)
                      ? Icons.cloud_off
                      : Icons.error_outline),
                  const SizedBox(height: 12),
                  const Text('No connection to the server'),
                  const SizedBox(height: 4),
                  const Text(
                    'You can still submit reports — they are stored on this '
                    'device and sync automatically via the mesh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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
              itemBuilder: (context, i) => _ReportTile(
                report: reports[i],
                onDelete: () => _delete(reports[i]),
              ),
            ),
          );
        },
          ),
          if (_deleting)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.all(32),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                          const SizedBox(width: 16),
                          Flexible(
                            child: Text(
                              'Deleting…\nIt may take a moment for this change '
                              'to reflect in your list.',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report, required this.onDelete});
  final EmergencyReport report;
  final VoidCallback onDelete;

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
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete report',
                  color: Colors.red,
                  onPressed: onDelete,
                ),
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
