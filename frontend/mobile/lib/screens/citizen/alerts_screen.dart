import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/official_alert.dart';
import '../../services/auth_state.dart';
import '../../theme.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late Future<List<OfficialAlert>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<OfficialAlert>> _load() =>
      context.read<AuthState>().api.getAlerts();

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Official Alerts')),
      body: FutureBuilder<List<OfficialAlert>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load alerts\n${snap.error}'));
          }
          final alerts = snap.data ?? [];
          if (alerts.isEmpty) {
            return const Center(child: Text('No active alerts right now.'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: alerts.length,
              itemBuilder: (context, i) => _AlertCard(alert: alerts[i]),
            ),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final OfficialAlert alert;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: severityColor(alert.severity), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign,
                    color: severityColor(alert.severity)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(alert.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Text(alert.severity,
                    style: TextStyle(
                        color: severityColor(alert.severity),
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(alert.message, style: const TextStyle(fontSize: 16)),
            if (alert.targetArea.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Affected area: ${alert.targetArea}',
                  style: const TextStyle(color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
