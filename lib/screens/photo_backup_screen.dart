import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/photo_backup_controller.dart';
import '../models/photo_backup_state.dart';
import '../utils/formatters.dart';
import '../widgets/photo_backup_consent_dialog.dart';

class PhotoBackupScreen extends StatefulWidget {
  const PhotoBackupScreen({super.key});

  @override
  State<PhotoBackupScreen> createState() => _PhotoBackupScreenState();
}

class _PhotoBackupScreenState extends State<PhotoBackupScreen>
    with WidgetsBindingObserver {
  final _controller = PhotoBackupController();
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

  /// Access may have been changed in Settings while we were away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.scanNow();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onToggle(bool on) async {
    if (!on) return _confirmDisable();
    final confirmed = await showPhotoBackupConsent(context);
    if (confirmed != true) return;
    await _controller.enable(includeExisting: true);
  }

  Future<void> _confirmDisable() async {
    final hasPending = _controller.state.queued > 0;
    final choice = await showDialog<_DisableChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off photo backup?'),
        content: Text(
          hasPending
              ? 'No new photos will be found or uploaded. '
                    '${_controller.state.queued} photos are still waiting. '
                    'Photos already uploaded stay in Telegram, and nothing is '
                    'deleted from your gallery.'
              : 'No new photos will be found or uploaded. Photos already '
                    'uploaded stay in Telegram, and nothing is deleted from '
                    'your gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (hasPending)
            TextButton(
              onPressed: () => Navigator.pop(context, _DisableChoice.clear),
              child: const Text('Turn off & clear waiting'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _DisableChoice.keep),
            child: Text(hasPending ? 'Turn off, keep waiting' : 'Turn off'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await _controller.disable(clearPending: choice == _DisableChoice.clear);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Automatic Photo Backup')),
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
                if (!state.configured)
                  const _Hint(
                    icon: Icons.info_outline,
                    text:
                        'Telegram backup is not configured in this build, so '
                        'photos can\'t be backed up.',
                  )
                else ...[
                  Card.outlined(
                    child: SwitchListTile(
                      title: const Text('Automatic Photo Backup'),
                      subtitle: Text(
                        state.enabled
                            ? (state.paused ? 'On · paused' : 'On')
                            : 'Off',
                      ),
                      value: state.enabled,
                      onChanged: _controller.isBusy ? null : _onToggle,
                    ),
                  ),
                  if (_controller.permanentlyDenied) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _controller.openAppSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open Settings to allow photos'),
                    ),
                  ],
                  if (state.enabled) ...[
                    const SizedBox(height: 16),
                    _AccessCard(state: state, controller: _controller),
                    const SizedBox(height: 16),
                    _StatusCard(state: state, controller: _controller),
                    const SizedBox(height: 16),
                    _SettingsCard(state: state, controller: _controller),
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

enum _DisableChoice { keep, clear }

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
              'When you turn this on, all photos you allow this app to access, '
              'existing and new, are queued and uploaded to the Telegram chat configured for this '
              'app. It is off by default and nothing is read until you turn it '
              'on and grant photo access.\n\n'
              'Uploads continue in the background when Android allows it, so '
              'they may be delayed by battery saver or restrictions. Photos '
              'are never deleted from your gallery. You can pause or turn it '
              'off at any time.',
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.state, required this.controller});

  final PhotoBackupState state;
  final PhotoBackupController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Widget content;
    if (state.access == PhotoAccess.full) {
      content = const _Hint(
        icon: Icons.photo_library_outlined,
        text: 'Photo access: all photos',
      );
    } else if (state.access == PhotoAccess.partial) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Hint(
            icon: Icons.photo_library_outlined,
            text:
                'Photo access: selected photos only. Only the photos you '
                'selected are uploaded.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (state.canManageSelection)
                OutlinedButton(
                  onPressed: controller.manageAccess,
                  child: const Text('Change selected photos'),
                ),
              OutlinedButton(
                onPressed: controller.openAppSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hint(
            icon: Icons.block,
            color: colors.error,
            text:
                'Photo access was removed, so nothing is being scanned or '
                'uploaded. Allow photo access in Settings to continue.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.openAppSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open Settings'),
          ),
        ],
      );
    }
    return Card.filled(
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.controller});

  final PhotoBackupState state;
  final PhotoBackupController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastScan = state.lastScanAt;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _CountRow('Uploaded', state.uploaded),
            _CountRow('Uploading', state.uploading),
            _CountRow('Waiting', state.pending),
            _CountRow('Failed', state.failed, isError: state.failed > 0),
            const SizedBox(height: 8),
            Text(
              lastScan == null
                  ? 'Not scanned yet'
                  : 'Last checked ${formatDateTime(lastScan)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => controller.setPaused(!state.paused),
                  icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(state.paused ? 'Resume' : 'Pause'),
                ),
                OutlinedButton.icon(
                  onPressed: state.isActive ? controller.scanNow : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check now'),
                ),
                if (state.failed > 0)
                  OutlinedButton.icon(
                    onPressed: controller.retryFailed,
                    icon: const Icon(Icons.replay),
                    label: const Text('Retry failed'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.state, required this.controller});

  final PhotoBackupState state;
  final PhotoBackupController controller;

  static const _sizeOptions = [5, 10, 20, 50];

  @override
  Widget build(BuildContext context) {
    final sizes = {..._sizeOptions, state.maxFileMb}.toList()..sort();
    return Card.outlined(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Upload on Wi-Fi only'),
            subtitle: const Text(
              'Photos wait until you\'re on an unmetered network',
            ),
            value: state.wifiOnly,
            onChanged: controller.setWifiOnly,
          ),
          ListTile(
            title: const Text('Maximum photo size'),
            subtitle: const Text('Larger photos are skipped'),
            trailing: DropdownButton<int>(
              value: state.maxFileMb,
              onChanged: (v) {
                if (v != null) controller.setMaxFileMb(v);
              },
              items: [
                for (final mb in sizes)
                  if (mb <= state.maxFileMbLimit)
                    DropdownMenuItem(value: mb, child: Text('$mb MB')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow(this.label, this.count, {this.isError = false});

  final String label;
  final int count;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Theme.of(context).colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: color)),
          ),
          Text('$count', style: TextStyle(color: color)),
        ],
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
