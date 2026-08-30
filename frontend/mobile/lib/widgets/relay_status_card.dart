import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/coordinator/carried_messages_screen.dart';
import '../services/relay/relay_manager.dart';

/// Shows the offline mesh state (outbox/inbox/peers) with a manual "Sync now"
/// flush button.
class RelayStatusCard extends StatelessWidget {
  const RelayStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final relay = context.watch<RelayManager>();
    final busy = relay.outboxPending > 0 || relay.inboxPending > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CarriedMessagesScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                busy ? Icons.bluetooth_connected : Icons.bluetooth,
                color: busy ? Colors.teal : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offline mesh',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      relay.status,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${relay.outboxPending} queued · '
                      '${relay.inboxPending} carried · tap to view',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.read<RelayManager>().flush(),
                child: const Text('Sync now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}