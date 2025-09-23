import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/contacts_backup_controller.dart';
import '../models/contacts_backup_state.dart';
import '../utils/formatters.dart';

class ContactsBackupScreen extends StatefulWidget {
  const ContactsBackupScreen({super.key});

  @override
  State<ContactsBackupScreen> createState() => _ContactsBackupScreenState();
}

class _ContactsBackupScreenState extends State<ContactsBackupScreen>
    with WidgetsBindingObserver {
  final _controller = ContactsBackupController();
  late final StreamSubscription<String> _messageSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageSub = _controller.messages.listen(_showMessage);
    _controller.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Permission may have been changed in Settings while we were away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.refresh();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts Backup')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final state = _controller.state;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _PrivacyNotice(),
                const SizedBox(height: 16),
                _StatusCard(state: state),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _controller.isExporting
                      ? null
                      : _controller.backUpNow,
                  icon: _controller.isExporting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  label: Text(
                    _controller.isExporting
                        ? 'Saving contacts…'
                        : 'Save Contacts to Device',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                if (_controller.permanentlyDenied) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _controller.openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open Settings to allow contacts'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('What happens', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Your contacts are exported to a .vcf file stored on this device. '
              'You can find it in the recordings list and share it yourself.\n\n'
              'Only names, phone numbers, email addresses and organization are '
              'included. Nothing is read or saved until you tap the button, '
              'and the app asks for contacts permission at that moment.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final ContactsBackupState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latestAt = state.latestAt;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latest local backup', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              latestAt == null ? 'None yet' : formatDateTime(latestAt),
              style: theme.textTheme.titleLarge,
            ),
            if (latestAt != null) ...[
              const Divider(height: 24),
              Text(
                '${state.contactCount ?? 0} contacts saved locally',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

