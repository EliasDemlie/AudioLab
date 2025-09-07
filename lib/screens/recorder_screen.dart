import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/recorder_controller.dart';
import '../models/recording.dart';
import '../widgets/record_controls.dart';
import 'contacts_backup_screen.dart';
import '../widgets/recording_status.dart';
import '../widgets/recordings_list.dart';

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  final _controller = RecorderController();
  late final StreamSubscription<String> _errorSub;

  @override
  void initState() {
    super.initState();
    _errorSub = _controller.errors.listen(_showError);
    _controller.init();
  }

  @override
  void dispose() {
    _errorSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(Recording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(recording.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _controller.delete(recording);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recorder'),
        actions: [
          IconButton(
            tooltip: 'Contacts backup',
            icon: const Icon(Icons.contacts_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ContactsBackupScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  children: [
                    RecordingStatus(
                      status: _controller.status,
                      elapsed: _controller.elapsed,
                      micSilenced: _controller.micSilenced,
                    ),
                    const SizedBox(height: 32),
                    RecordControls(
                      status: _controller.status,
                      isBusy: _controller.isBusy,
                      onStart: _controller.start,
                      onPause: _controller.pause,
                      onResume: _controller.resume,
                      onStop: _controller.stop,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recordings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              Expanded(
                child: RecordingsList(
                  recordings: _controller.recordings,
                  onShare: _controller.share,
                  onDelete: _confirmDelete,
                  onRetryUpload: _controller.retryUpload,
                  showBackup: _controller.backupConfigured,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
