import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recording.dart';

class RenameRecordingSheet extends StatefulWidget {
  const RenameRecordingSheet({
    super.key,
    required this.recording,
    required this.onRename,
  });

  final Recording recording;
  final Future<void> Function(String title) onRename;

  @override
  State<RenameRecordingSheet> createState() => _RenameRecordingSheetState();
}

class _RenameRecordingSheetState extends State<RenameRecordingSheet> {
  late final TextEditingController _input = TextEditingController(
    text: widget.recording.title,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _input.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a file name.');
      return;
    }
    if (title == widget.recording.title) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onRename(title);
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (error) {
      _showError(error.message);
    } on FileSystemException catch (error) {
      _showError(error.message);
    } catch (error) {
      debugPrint('Rename failed: $error');
      _showError(null);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String? message) {
    if (!mounted) return;
    setState(() {
      _error = message == null || message.isEmpty
          ? 'Could not rename this recording. Please try again.'
          : message;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      8,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rename recording',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              autofocus: true,
              enabled: !_saving,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'File name',
                suffixText: '.${widget.recording.format.toLowerCase()}',
                errorText: _error,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Save name'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
