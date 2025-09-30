import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recording.dart';
import '../utils/formatters.dart';

class SaveRecordingSheet extends StatefulWidget {
  const SaveRecordingSheet({
    super.key,
    required this.recording,
    required this.onSave,
    required this.onDiscard,
  });

  final Recording recording;
  final Future<Recording> Function(String title) onSave;
  final Future<void> Function() onDiscard;

  @override
  State<SaveRecordingSheet> createState() => _SaveRecordingSheetState();
}

class _SaveRecordingSheetState extends State<SaveRecordingSheet> {
  final _input = TextEditingController();
  bool _saving = false;
  bool _discarding = false;
  bool _confirmingDiscard = false;
  bool _allowPop = false;
  String? _error;

  bool get _busy => _saving || _discarding;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _confirmingDiscard) return;
    final title = _input.text.trim();
    final safeTitle = title
        .replaceAll(RegExp(r'[/\\\u0000-\u001F]'), ' ')
        .trim();
    if (safeTitle.isEmpty) {
      setState(() => _error = 'Enter a file name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final recording = await widget.onSave(title);
      if (mounted) _close(recording);
    } on PlatformException catch (error) {
      _showError(
        error.message,
        'Could not save this recording. Please try again.',
      );
    } on FileSystemException catch (error) {
      _showError(
        error.message,
        'Could not save this recording. Please try again.',
      );
    } catch (error) {
      debugPrint('Save recording failed: $error');
      _showError(null, 'Could not save this recording. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDiscard() async {
    if (_busy || _confirmingDiscard) return;
    _confirmingDiscard = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard recording?'),
        content: const Text('This recording has not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _confirmingDiscard = false;
    if (discard != true || !mounted) return;
    setState(() {
      _discarding = true;
      _error = null;
    });
    try {
      await widget.onDiscard();
      if (mounted) _close(null);
    } on PlatformException catch (error) {
      _showError(
        error.message,
        'Could not discard this recording. Please try again.',
      );
    } on FileSystemException catch (error) {
      _showError(
        error.message,
        'Could not discard this recording. Please try again.',
      );
    } catch (error) {
      debugPrint('Discard recording failed: $error');
      _showError(null, 'Could not discard this recording. Please try again.');
    } finally {
      if (mounted) setState(() => _discarding = false);
    }
  }

  void _showError(String? message, String fallback) {
    if (!mounted) return;
    setState(
      () => _error = message == null || message.isEmpty ? fallback : message,
    );
  }

  void _close(Recording? recording) {
    setState(() => _allowPop = true);
    Navigator.pop(context, recording);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope<Recording>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmDiscard());
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.audio_file_outlined,
                        color: colors.onPrimaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Save recording',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: _busy ? null : _confirmDiscard,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Enter a file name to save to your library.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (widget.recording.duration != null)
                      formatDuration(widget.recording.duration!),
                    formatBytes(widget.recording.sizeBytes),
                    widget.recording.format,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _input,
                  autofocus: true,
                  enabled: !_busy,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'File name',
                    suffixText: '.${widget.recording.format.toLowerCase()}',
                    errorText: _error,
                    errorMaxLines: 4,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  child: _saving
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onPrimary,
                          ),
                        )
                      : const Text('Save recording'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _confirmDiscard,
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: colors.error,
                  ),
                  child: _discarding
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Discard recording'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
