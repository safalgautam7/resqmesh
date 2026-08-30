import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/relay/relay_envelope.dart';
import '../services/relay/relay_manager.dart';

/// Wraps the app so that any report received over the offline mesh (BLE)
/// triggers a visible "message received" alert — regardless of which screen
/// is currently shown. This matters for the real-world scenario where a phone
/// carries a report that arrived while the user wasn't looking.
class MeshNotificationListener extends StatefulWidget {
  const MeshNotificationListener({super.key, required this.child});

  final Widget child;

  @override
  State<MeshNotificationListener> createState() =>
      _MeshNotificationListenerState();
}

class _MeshNotificationListenerState extends State<MeshNotificationListener> {
  @override
  void initState() {
    super.initState();
    // Listen after the first frame so a ScaffoldMessenger is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  StreamSubscription<RelayEnvelope>? _sub;

  void _subscribe() {
    final relay = context.read<RelayManager>();
    _sub?.cancel();
    _sub = relay.received.listen((envelope) {
      if (!mounted) return;
      _showReceived(envelope);
    });
  }

  void _showReceived(RelayEnvelope envelope) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          content: Row(
            children: [
              const Icon(Icons.sd_card_alert, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Message received',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(
                      'From ${envelope.origin}: ${envelope.summary}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
