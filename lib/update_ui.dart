import 'package:flutter/material.dart';

import 'l10n.dart';
import 'models.dart';
import 'updater.dart';

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
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  up.totalBytes > 0
                      ? '${tr('Downloading update')} $pct% · ${formatBytes(up.received)} / ${formatBytes(up.totalBytes)}'
                      : '${tr('Downloading update')} ${formatBytes(up.received)}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
              TextButton(
                  onPressed: up.cancelUpdate, child: const T('Cancel')),
            ]),
          ],
        );
      case UpdatePhase.ready:
        return FilledButton.icon(
          onPressed: up.install,
          icon: const Icon(Icons.install_mobile_rounded),
          label: const T('Install update'),
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
                      '${info.name}${info.size > 0 ? ' · ${formatBytes(info.size)}' : ''}',
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
  if (up.phase != UpdatePhase.idle) return;
  up.promptedBuild = info.build;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_rounded, size: 32),
      title: const T('Update available'),
      content: Text(
        '${info.name}${info.size > 0 ? ' · ${formatBytes(info.size)}' : ''}\n\n'
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
