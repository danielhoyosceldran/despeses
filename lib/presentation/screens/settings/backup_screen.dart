import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/app_providers.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';

/// Backup/restore (plan §5.4, v1 scope): copy the local `.sqlite` file and
/// share it, or overwrite the live database from a previously shared file.
/// Restoring always overwrites — there is no merge.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final backup = await ref.read(backupServiceProvider).createBackup();
      if (!mounted) return;
      await Share.shareXFiles([XFile(backup.path)]);
    } catch (e) {
      if (mounted) showAppToast(context, 'Backup failed: $e', variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore backup',
      message: 'This overwrites all current data with the selected backup. This cannot be undone. Continue?',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      // The live connection must be closed before the file underneath it is
      // replaced, or the restored file gets corrupted by in-flight writes.
      await ref.read(databaseProvider).close();
      await ref.read(backupServiceProvider).restoreBackup(File(path));
      ref.invalidate(databaseProvider);
      ref.invalidate(referenceDataCacheProvider);
      if (mounted) {
        showAppToast(context, 'Backup restored. Restart the app to see all changes.', variant: ToastVariant.success);
      }
    } catch (e) {
      if (mounted) showAppToast(context, 'Restore failed: $e', variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.upload300),
              title: const Text('Export backup'),
              subtitle: const Text('Copies the local database and opens the share sheet'),
              trailing: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()) : null,
              onTap: _busy ? null : _export,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(LucideIcons.download300),
              title: const Text('Restore backup'),
              subtitle: const Text('Pick a .sqlite file — this overwrites all current data'),
              onTap: _busy ? null : _import,
            ),
          ],
        ),
      ),
    );
  }
}
