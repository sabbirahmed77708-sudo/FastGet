import 'package:flutter/material.dart';

import 'l10n.dart';
import 'models.dart';
import 'updater.dart';

/// " · 2.4 MB · only the changed part" or " · 55 MB" (leading separator).
String updateSizeLabel(UpdateInfo i) {
  if (i.hasPatch) {
    return ' · ${formatBytes(i.patchSize)} · ${tr('only the changed part')}';
  }
  return i.size > 0 ? ' · ${formatBytes(i.size)}' : '';
}

String _left(int sec) {
  if (sec < 0) return '--';
  if (sec < 60) return '${sec}s';
  if (sec < 3600) return '${sec ~/ 60}m ${sec % 60}s';
  return '${sec ~/ 3600}h ${(sec % 3600) ~/ 60}m';
}

/// The update button with progress: Update now -> progress -> Install.
class UpdateActionButton extends StatelessWidget {
  const UpdateActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    final up = UpdateChecker.instance;
    final cs = Theme.of(context).colorScheme;
    switch (up.phase) {
      case UpdatePhase.downloading:
        final pct = (up.progress * 100).floor();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: up.totalBytes > 0 ? up.progress : null,
                minHeight: 7,
              ),
            ),
            const SizedBox(height: 8),
            // MB on the left, percent on the right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  up.totalBytes > 0
                      ? '${formatBytes(up.received)} / ${formatBytes(up.totalBytes)}'
                      : formatBytes(up.received),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                if (up.totalBytes > 0)
                  Text('$pct%',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: cs.primary)),
              ],
            ),
            const SizedBox(height: 2),
            Row(children: [
              Expanded(
                child: Text(
                  up.speed > 0
                      ? '${tr(up.usingPatch ? 'Downloading update (changed part only)' : 'Downloading update')} · ${formatBytes(up.speed)}/s · ${_left(up.etaSeconds)} ${tr('left')}'
                      : tr(up.usingPatch
                          ? 'Downloading update (changed part only)'
                          : 'Downloading update'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
              TextButton(
                  onPressed: up.cancelUpdate, child: const T('Cancel')),
            ]),
          ],
        );
      case UpdatePhase.patching:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: const LinearProgressIndicator(minHeight: 7),
            ),
            const SizedBox(height: 8),
            T('Applying update…',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        );
      case UpdatePhase.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: Color(0xFF16A34A)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr(up.autoDownloaded
                      ? 'Downloaded in the background · ready to install'
                      : 'Downloaded · ready to install'),
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: up.install,
              icon: const Icon(Icons.install_mobile_rounded),
              label: const T('Install update'),
            ),
          ],
        );
      case UpdatePhase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(up.updateError ?? 'Update failed'),
                style: TextStyle(color: cs.error, fontSize: 13)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: up.startUpdate,
              icon: const Icon(Icons.refresh_rounded),
              label: const T('Try again'),
            ),
          ],
        );
      case UpdatePhase.idle:
        return FilledButton.icon(
          onPressed: up.startUpdate,
          icon: const Icon(Icons.system_update_rounded),
          label: const T('Update now'),
        );
    }
  }
}

/// Banner on the home screen while a new version is available.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final up = UpdateChecker.instance;
    final info = up.available;
    if (info == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.system_update_rounded, color: cs.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    T('New version available',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer)),
                    Text(
                      '${info.name}${updateSizeLabel(info)}',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onPrimaryContainer.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 10),
            const UpdateActionButton(),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style pop-up: shown once per version when the app finds an update.
Future<void> maybePromptUpdate(BuildContext context) async {
  final up = UpdateChecker.instance;
  final info = up.available;
  if (info == null || up.promptedBuild == info.build) return;

  // downloaded by itself in the background: only the install tap is left
  if (up.phase == UpdatePhase.ready && up.autoDownloaded) {
    up.promptedBuild = info.build;
    final install = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.install_mobile_rounded, size: 32),
        title: const T('Update ready'),
        content: Text(
          '${info.name}${updateSizeLabel(info)}\n\n'
          '${tr('The new version is downloaded. Install it now?')}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const T('Later')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const T('Install now')),
        ],
      ),
    );
    if (install == true) up.install();
    return;
  }

  if (up.busy) return;
  up.promptedBuild = info.build;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_rounded, size: 32),
      title: const T('Update available'),
      content: Text(
        '${info.name}${updateSizeLabel(info)}\n\n'
        '${tr('Download and install the new version now?')}',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const T('Later')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const T('Update now')),
      ],
    ),
  );
  if (yes == true) up.startUpdate();
}

/// Shown once, right after the app starts on a freshly installed version:
/// what came with the update (like the "What's new" page on a phone).
Future<void> maybeShowWhatsNew(BuildContext context) async {
  final info = await UpdateChecker.instance.takeWhatsNew();
  if (info == null || !context.mounted) return;
  final lines = info.notes
      .split('\n')
      .map((e) => e.trim().replaceFirst(RegExp(r'^[-*•]\s*'), ''))
      .where((e) => e.isNotEmpty)
      .toList();
  final cs = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.celebration_rounded, size: 32),
      title: const T('DROM is updated'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.name.isNotEmpty)
                Text(info.name,
                    style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const T("What's new",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              if (lines.isEmpty)
                const T('Improvements and bug fixes.')
              else
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 8),
                          child: Icon(Icons.circle, size: 6, color: cs.primary),
                        ),
                        Expanded(child: Text(l, style: const TextStyle(height: 1.35))),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const T('Got it')),
      ],
    ),
  );
}
