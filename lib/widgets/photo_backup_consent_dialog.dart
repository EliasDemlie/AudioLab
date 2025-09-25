import 'package:flutter/material.dart';

/// Explains Automatic Photo Backup. Resolves to true only if the user agrees.
Future<bool?> showPhotoBackupConsent(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Back up your photos?'),
    content: const SingleChildScrollView(
      child: Text(
        'Android will ask whether this app may access your photos. The app '
        'only sees images, never videos. On Android 14 and newer you can '
        'choose to share just selected photos.\n\n'
        'All photos the app can access, existing and new, are uploaded as '
        'full-size originals to the Telegram chat configured for this app. '
        'This can be many photos and a lot of data. Anyone who can see '
        'that chat can see them. Your gallery is never changed.\n\n'
        'You can pause or turn this off any time from the photo icon.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Not now'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Turn on'),
      ),
    ],
  ),
);
