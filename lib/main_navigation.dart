import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/recorder_controller.dart';
import 'models/recording.dart';
import 'screens/recordings_tab.dart';
import 'screens/recorder_tab.dart';
import 'screens/recording_saved_screen.dart';

/// App shell. Tab changes only update the index; IndexedStack retains each tab.
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final _controller = RecorderController();
  late final StreamSubscription<String> _errorSub;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _errorSub = _controller.errors.listen(_showError);
    unawaited(_controller.init());
  }

  @override
  void dispose() {
    _errorSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index == _index) return;
    _controller.setRecorderTabVisible(index == 0);
    setState(() => _index = index);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stopAndSave() async {
    final recording = await _controller.stopAndWait();
    if (recording == null || !mounted) return;
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.primary,
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: colors.onPrimary),
              const SizedBox(width: 12),
              Text(
                'Recording saved',
                style: TextStyle(color: colors.onPrimary),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _openRecording(Recording recording) async {
    _controller.setRecorderTabVisible(false);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecordingSavedScreen(
            recording: recording,
            controller: _controller,
          ),
        ),
      );
    } finally {
      if (mounted) _controller.setRecorderTabVisible(_index == 0);
    }
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VoicePro'), centerTitle: false),
    body: SafeArea(
      child: IndexedStack(
        index: _index,
        children: [
          RecorderTab(controller: _controller, onStop: _stopAndSave),
          RecordingsTab(
            controller: _controller,
            onOpen: _openRecording,
            onDelete: _confirmDelete,
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: _goTo,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.mic_none_rounded),
          selectedIcon: Icon(Icons.mic_rounded),
          label: 'Record',
        ),
        NavigationDestination(
          icon: Icon(Icons.library_music_outlined),
          selectedIcon: Icon(Icons.library_music_rounded),
          label: 'Library',
        ),
      ],
    ),
  );
}
