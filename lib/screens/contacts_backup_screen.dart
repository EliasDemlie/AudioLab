import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/contacts_backup_controller.dart';
import '../models/contacts_backup_state.dart';
import '../models/upload_status.dart';
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
                _StatusCard(state: state, onRetry: _controller.retryUpload),
                const SizedBox(height: 24),
                if (!state.configured)
                  const _Hint(
                    icon: Icons.info_outline,
                    text:
                        'Telegram backup is not configured in this build, '
                        'so contacts can\'t be backed up.',
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: _controller.isExporting || state.isBusy
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
                          ? 'Exporting contacts…'
                          : 'Back Up Contacts Now',
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
              'Your contacts are exported to a .vcf file and uploaded to the '
              'Telegram chat configured for this app. Anyone who can see that '
              'chat can see your contacts.\n\n'
              'Only names, phone numbers, email addresses and organization are '
              'included. Nothing is read or uploaded until you tap the button, '
              'and the app asks for contacts permission at that moment.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.onRetry});

  final ContactsBackupState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final latest = state.latest;
    final lastSuccess = state.lastSuccessAt;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last successful backup', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              lastSuccess == null ? 'Never' : formatDateTime(lastSuccess),
              style: theme.textTheme.titleLarge,
            ),
            if (latest != null) ...[
              const Divider(height: 24),
              Text('Latest backup', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              switch (latest.state) {
                UploadState.pending => _Hint(
                  icon: Icons.cloud_queue,
                  text: latest.error == null
                      ? 'Waiting for a connection to upload'
                      : 'Will retry: ${latest.error}',
                ),
                UploadState.uploading => Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: latest.progress > 0 ? latest.progress : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${(latest.progress * 100).round()}%'),
                  ],
                ),
                UploadState.uploaded => _Hint(
                  icon: Icons.cloud_done,
                  color: colors.primary,
                  text:
                      'Uploaded to Telegram'
                      '${state.contactCount == null ? '' : ' · ${state.contactCount} contacts'}',
                ),
                UploadState.failed => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Hint(
                      icon: Icons.cloud_off,
                      color: colors.error,
                      text: latest.error ?? 'Upload failed',
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry upload'),
                    ),
                  ],
                ),
              },
            ],
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
