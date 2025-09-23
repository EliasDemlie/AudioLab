import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/recorder_controller.dart';
import 'models/recording.dart';
import 'screens/recordings_tab.dart';
import 'screens/recorder_tab.dart';
import 'screens/recording_saved_screen.dart';
import 'widgets/rename_recording_sheet.dart';

/// App shell. Menu destinations retain their state in the IndexedStack.
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key, this.onToggleTheme});

  final VoidCallback? onToggleTheme;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _controller = RecorderController();
  late final StreamSubscription<String> _errorSub;
  int _index = 0;
  bool _drawerOpen = false;

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

  void _selectDestination(int index) {
    _scaffoldKey.currentState?.closeDrawer();
    _goTo(index);
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

  Future<void> _renameRecording(Recording recording) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => RenameRecordingSheet(
          recording: recording,
          onRename: (title) async {
            await _controller.rename(recording, title);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope<void>(
      canPop: _index == 0 || _drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) _goTo(0);
      },
      child: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: (open) => setState(() => _drawerOpen = open),
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Open navigation menu',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
          title: Text(_index == 0 ? 'VoicePro' : 'Library'),
          centerTitle: false,
          actions: [
            if (widget.onToggleTheme != null)
              IconButton(
                tooltip: Theme.of(context).brightness == Brightness.dark
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
                onPressed: widget.onToggleTheme,
                icon: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: Drawer(
          width: MediaQuery.sizeOf(context).width < 360 ? 280 : 304,
          backgroundColor: colors.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 28, 12, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.mic_rounded, color: colors.primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VoicePro',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Voice recorder',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                for (final (index, label, icon) in [
                  (0, 'Record', Icons.mic_none_rounded),
                  (1, 'Library', Icons.library_music_outlined),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: Icon(icon),
                      title: Text(label),
                      selected: _index == index,
                      selectedColor: colors.primary,
                      selectedTileColor: colors.primary.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () => _selectDestination(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _index,
            children: [
              RecorderTab(controller: _controller, onStop: _stopAndSave),
              RecordingsTab(
                controller: _controller,
                onOpen: _openRecording,
                onRename: _renameRecording,
                onDelete: _confirmDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
