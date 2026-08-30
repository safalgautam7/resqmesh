import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/relay/relay_envelope.dart';
import '../../services/relay/relay_manager.dart';
import '../../services/relay/relay_store.dart';

/// Shows every emergency report that arrived over the offline mesh (BLE) and
/// is currently being carried on this device, waiting to reach the backend.
///
/// A rescuer can review the full content of each carried report right on the
/// device — no server, no AI required — so a message is never invisible just
/// because the backend is unreachable. Full priority/AI processing still
/// happens server-side once these are delivered.
class CarriedMessagesScreen extends StatefulWidget {
  const CarriedMessagesScreen({super.key});

  @override
  State<CarriedMessagesScreen> createState() => _CarriedMessagesScreenState();
}

class _CarriedMessagesScreenState extends State<CarriedMessagesScreen> {
  List<RelayEnvelope> _inbox = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
    // Keep the list in sync as new mesh messages land / are delivered.
    context.read<RelayManager>().addListener(_refresh);
  }

  @override
  void dispose() {
    context.read<RelayManager>().removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _inbox = RelayStore.instance.inboxMessages()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carried messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Sync now (deliver to server)',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final n = await context.read<RelayManager>().flush();
              if (mounted) {
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    content: Text(n > 0
                        ? 'Delivered $n message(s) to the server.'
                        : 'Nothing new to deliver.'),
                  ));
              }
              _refresh();
            },
          ),
        ],
      ),
      body: _inbox.isEmpty
          ? const Center(child: Text('No carried messages right now.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _inbox.length,
              itemBuilder: (context, i) => _CarriedCard(envelope: _inbox[i]),
            ),
    );
  }
}

class _CarriedCard extends StatelessWidget {
  const _CarriedCard({required this.envelope});

  final RelayEnvelope envelope;

  String get _type {
    final report = envelope.payload['report'];
    if (report is Map) {
      final t = report['incident_type'];
      if (t is String && t.isNotEmpty) return t;
    }
    return 'Report';
  }

  String get _location {
    final report = envelope.payload['report'];
    if (report is Map) {
      final lat = report['latitude'];
      final lon = report['longitude'];
      if (lat is num && lon is num) {
        return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
      }
    }
    return 'No coordinates';
  }

  String get _people {
    final report = envelope.payload['report'];
    if (report is Map) {
      final p = report['people_affected'];
      if (p is int && p > 0) return '$p person(s) affected';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sd_card_alert,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _type,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'From ${envelope.origin}',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              envelope.summary,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: theme.hintColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _location,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ),
              ],
            ),
            if (_people.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _people,
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Received ${_timeAgo(envelope.createdAt)}',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  static String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
