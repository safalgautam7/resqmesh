import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_state.dart';
import '../../widgets/relay_status_card.dart';
import 'report_form_screen.dart';

class CitizenHomeTab extends StatelessWidget {
  const CitizenHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ResQMesh'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Hello, ${user?.username ?? ''}',
                  style: const TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 16),
              const RelayStatusCard(),
              const SizedBox(height: 16),
              // Primary emergency action
              Material(
                color: const Color(0xFFB71C1C),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReportFormScreen()),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(Icons.emergency, color: Colors.white, size: 64),
                        SizedBox(height: 8),
                        Text('GET HELP',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('Report an emergency',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const ListTile(
                leading: Icon(Icons.help_outline),
                title: Text('Emergency Information'),
                subtitle: Text('Safety guidance coming soon'),
                enabled: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
