import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/hairline_list_tile.dart';

/// Set by [_BackupScreenState._import] right before the provider tree is torn
/// down and rebuilt (R18); the first screen back up (dashboard) shows it once
/// and clears it, since the [BackupScreen] instance that triggered the
/// restore is gone by the time the rebuild finishes.
class RestoreNotice {
  RestoreNotice._();
  static String? pendingMessage;
}

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
    final translations = ref.read(translationsProvider).asData?.value;
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      final backup = await ref.read(backupServiceProvider).createBackup(
            // Flush the WAL into the main file so the single-file backup is
            // complete; without this the last transactions could be missing.
            checkpoint: () => db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)'),
          );
      if (!mounted) return;
      await Share.shareXFiles([XFile(backup.path)]);
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          (translations?.t('backup.export_failed') ?? 'Backup failed: {{error}}').replaceAll('{{error}}', '$e'),
          variant: ToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final translations = ref.read(translationsProvider).asData?.value;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: translations?.t('backup.restore_title') ?? 'Restore backup',
      message: translations?.t('backup.restore_confirm_message') ??
          'This overwrites all current data with the selected backup. This cannot be undone. Continue?',
      confirmLabel: translations?.t('backup.restore') ?? 'Restore',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    final backupService = ref.read(backupServiceProvider);
    try {
      // Tear down the whole provider tree (closing the db via its onDispose,
      // with no live watchers left to throw) before touching the file, then
      // rebuild it fresh — see AppRestartScope in main.dart (R18).
      await AppRestartScope.restart(context, () => backupService.restoreBackup(File(path)));
      RestoreNotice.pendingMessage =
          translations?.t('backup.restored') ?? 'Backup restored.';
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          (translations?.t('backup.restore_failed') ?? 'Restore failed: {{error}}').replaceAll('{{error}}', '$e'),
          variant: ToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final translations = ref.watch(translationsProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  HairlineListTile(
                    icon: LucideIcons.upload300,
                    title: translations?.t('backup.export_title') ?? 'Export backup',
                    subtitle: translations?.t('backup.export_subtitle') ??
                        'Copies the local database and opens the share sheet',
                    trailing: _busy
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : null,
                    onTap: _busy ? null : _export,
                  ),
                  HairlineListTile(
                    icon: LucideIcons.download300,
                    title: translations?.t('backup.restore_title') ?? 'Restore backup',
                    subtitle: translations?.t('backup.restore_subtitle') ??
                        'Pick a .sqlite file — this overwrites all current data',
                    onTap: _busy ? null : _import,
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
