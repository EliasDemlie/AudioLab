import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/recorder_controller.dart';
import 'models/recording.dart';
import 'screens/recordings_tab.dart';
import 'screens/recorder_tab.dart';
import 'screens/recording_saved_screen.dart';
import 'widgets/rename_recording_sheet.dart';
import 'widgets/save_recording_sheet.dart';

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
  bool _saveSheetOpen = false;
  bool _draftPromptScheduled = false;

  @override
  void initState() {
    super.initState();
    _errorSub = _controller.errors.listen(_showError);
    _controller.draftRecordingsListenable.addListener(_queueDraftPrompt);
    unawaited(_controller.init());
  }

  @override
  void dispose() {
    _errorSub.cancel();
    _controller.draftRecordingsListenable.removeListener(_queueDraftPrompt);
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index == _index) return;
    _controller.setRecorderTabVisible(index == 0);
    setState(() => _index = index);
  }

  void _selectDestination(int index) {
    _scaffoldKey.currentState?.closeEndDrawer();
    _goTo(index);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finishRecording() async {
    await _controller.stopAndWait();
    _queueDraftPrompt();
  }

  void _queueDraftPrompt() {
    if (!mounted ||
        _saveSheetOpen ||
        _draftPromptScheduled ||
        _controller.draftRecordingsListenable.value.isEmpty) {
      return;
    }
    _draftPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _draftPromptScheduled = false;
      if (!mounted ||
          _saveSheetOpen ||
          _controller.draftRecordingsListenable.value.isEmpty ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      unawaited(_openDraft(_controller.draftRecordingsListenable.value.first));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openDraft(Recording recording) async {
    _saveSheetOpen = true;
    _controller.setRecorderTabVisible(false);
    _scaffoldKey.currentState?.closeEndDrawer();
    try {
      final saved = await showModalBottomSheet<Recording>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        isDismissible: false,
        enableDrag: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (_) => SaveRecordingSheet(
          recording: recording,
          onSave: (title) => _controller.saveDraft(recording, title),
          onDiscard: () => _controller.discardDraft(recording),
        ),
      );
      if (saved != null && mounted) {
        _goTo(1);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Recording saved')));
      }
    } finally {
      _saveSheetOpen = false;
      if (mounted) {
        _controller.setRecorderTabVisible(_index == 0);
        _queueDraftPrompt();
      }
    }
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
      if (mounted) {
        _controller.setRecorderTabVisible(_index == 0);
        _queueDraftPrompt();
      }
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
    _queueDraftPrompt();
  }

  Future<void> _renameRecording(Recording recording) async {
    await showModalBottomSheet<void>(
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
    _queueDraftPrompt();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope<void>(
      canPop: _index == 0 || _drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) _goTo(0);
      },
      child: Scaffold(
        key: _scaffoldKey,
        onEndDrawerChanged: (open) => setState(() => _drawerOpen = open),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.mic_rounded, color: colors.primary, size: 22),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'VoicePro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'Open navigation menu',
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        endDrawer: Drawer(
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Divider(
                    height: 0,
                    color: colors.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                for (final (index, label, icon) in [
                  (0, 'Record', Icons.mic_none_rounded),
                  (1, 'Library', Icons.library_music_outlined),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: Icon(icon),
                      title: Text(label),
                      iconColor: colors.onSurfaceVariant,
                      titleTextStyle: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(
                            color: _index == index
                                ? colors.primary
                                : colors.onSurfaceVariant,
                            fontWeight: _index == index
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                      selected: _index == index,
                      selectedColor: colors.primary,
                      selectedTileColor: colors.primary.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () => _selectDestination(index),
                    ),
                  ),
                if (widget.onToggleTheme != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Divider(
                      height: 0,
                      color: colors.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                    title: Text(
                      dark ? 'Switch to light mode' : 'Switch to dark mode',
                    ),
                    iconColor: colors.onSurfaceVariant,
                    textColor: colors.onSurfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onTap: () {
                      _scaffoldKey.currentState?.closeEndDrawer();
                      widget.onToggleTheme?.call();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _index,
            children: [
              RecorderTab(controller: _controller, onStop: _finishRecording),
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
