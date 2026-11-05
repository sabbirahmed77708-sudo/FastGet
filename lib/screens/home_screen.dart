import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../download_manager.dart';
import '../models.dart';
import '../theme.dart';
import '../browser/browser_controller.dart';
import '../browser/browser_screen.dart';
import 'app_settings_screen.dart';
import '../l10n.dart';

enum _Filter { all, active, completed }

class HomeScreen extends StatefulWidget {
  /// true when opened from the browser's "Downloads" menu entry.
  final bool embedded;
  const HomeScreen({super.key, this.embedded = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final dm = DownloadManager.instance;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    dm.addListener(_rebuild);
  }

  @override
  void dispose() {
    dm.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ actions

  Future<void> _showAddSheet() async {
    final ctrl = TextEditingController();
    final clip = await Clipboard.getData('text/plain');
    final t = clip?.text?.trim() ?? '';
    if (t.startsWith('http://') || t.startsWith('https://')) ctrl.text = t;
    if (!mounted) return;

    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const T('New download',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            T('Paste a direct link to a file',
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: tr('https://example.com/file.zip'),
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  tooltip: tr('Paste'),
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final c = await Clipboard.getData('text/plain');
                    if (c?.text != null) ctrl.text = c!.text!.trim();
                  },
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                icon: const Icon(Icons.download_rounded),
                label: const T('Start download'),
              ),
            ),
          ],
        ),
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    await _add(url);
  }

  Future<void> _add(String url) async {
    try {
      await dm.addUrl(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(tr(e.toString())),
        ),
      );
    }
  }

  Future<void> _openBrowser() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const BrowserScreen()),
    );
  }

  Future<void> _confirmRemove(DownloadItem d) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const T('Redownload'),
              onTap: () => Navigator.pop(ctx, 'redo'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const T('Copy link'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_remove_rounded),
              title: const T('Remove from list'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error),
              title: T('Delete file too',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: d.url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: T('Link copied')));
      }
    } else if (choice == 'redo') {
      await _redownload(d);
    } else if (choice == 'remove') {
      await dm.remove(d);
    } else if (choice == 'delete') {
      await dm.remove(d, deleteFile: true);
    }
  }

  Future<void> _redownload(DownloadItem d) async {
    if (d.downloaded > 0 || d.status == DlStatus.completed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const T('Redownload this file?'),
          content: const T(
              'The partial or finished file will be deleted and downloaded again.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const T('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const T('Redownload')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await dm.redownload(d);
  }

  // ------------------------------------------------------------ app menu

  Widget _appMenu() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    PopupMenuItem<String> entry(String value, IconData icon, String label,
        {IconData? trailing, String? note}) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(tr(label))),
            if (note != null)
              Text(note,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline)),
            if (trailing != null) Icon(trailing, size: 22),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: tr('More'),
      icon: const Icon(Icons.more_vert_rounded),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: _onMenu,
      itemBuilder: (_) => [
        entry('wifi', Icons.wifi_rounded, 'Wi-Fi only',
            trailing: dm.wifiOnly
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded),
        entry('theme', dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            dark ? 'Light mode' : 'Night mode'),
        entry('lang', Icons.language_rounded, 'Language',
            note: L10n.instance.isBn ? 'বাংলা' : 'English'),
        const PopupMenuDivider(),
        entry('settings', Icons.settings_outlined, 'Settings'),
        entry('about', Icons.info_outline_rounded, 'About'),
        entry('exit', Icons.exit_to_app_rounded, 'Exit'),
      ],
    );
  }

  Future<void> _onMenu(String v) async {
    switch (v) {
      case 'wifi':
        await dm.setWifiOnly(!dm.wifiOnly);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content:
              Text(tr(dm.wifiOnly ? 'Wi-Fi only is on' : 'Wi-Fi only is off')),
        ));
        break;
      case 'theme':
        final dark = Theme.of(context).brightness == Brightness.dark;
        await BrowserController.instance
            .setThemeMode(dark ? ThemeMode.light : ThemeMode.dark);
        break;
      case 'lang':
        await showLanguageDialog(context);
        break;
      case 'settings':
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
        );
        break;
      case 'about':
        showAboutDrox(context);
        break;
      case 'exit':
        await SystemNavigator.pop();
        break;
    }
  }

  // -------------------------------------------------------------- build

  List<DownloadItem> get _visible {
    switch (_filter) {
      case _Filter.active:
        return dm.items
            .where((e) => e.status != DlStatus.completed)
            .toList();
      case _Filter.completed:
        return dm.items
            .where((e) => e.status == DlStatus.completed)
            .toList();
      case _Filter.all:
        return dm.items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.embedded ? tr('Downloads') : 'DROX'),
        actions: [
          if (!widget.embedded) ...[
            IconButton.filledTonal(
              tooltip: tr('Browser'),
              icon: const Icon(Icons.public_rounded),
              onPressed: _openBrowser,
            ),
            _appMenu(),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _summary(),
          _filters(),
          Expanded(
            child: items.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _tile(items[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const T('Add link',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _summary() {
    final cs = Theme.of(context).colorScheme;
    final active =
        dm.items.where((e) => e.status == DlStatus.downloading).toList();
    final speed = active.fold<double>(0, (a, b) => a + b.speed);
    final done =
        dm.items.where((e) => e.status == DlStatus.completed).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [cs.primary, Color.lerp(cs.primary, Colors.indigo, 0.55)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T('Current speed',
                    style: TextStyle(
                        color: cs.onPrimary.withValues(alpha: 0.8),
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text('${formatBytes(speed)}/s',
                    style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
              ],
            ),
          ),
          _stat(cs, '${active.length}', 'Active'),
          const SizedBox(width: 20),
          _stat(cs, '$done', 'Done'),
        ],
      ),
    );
  }

  Widget _stat(ColorScheme cs, String value, String label) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: cs.onPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          Text(tr(label),
              style: TextStyle(
                  color: cs.onPrimary.withValues(alpha: 0.8), fontSize: 12)),
        ],
      );

  Widget _filters() {
    Widget chip(String label, _Filter f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(tr(label)),
            selected: _filter == f,
            showCheckmark: false,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            onSelected: (_) => setState(() => _filter = f),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          chip('All', _Filter.all),
          chip('Active', _Filter.active),
          chip('Completed', _Filter.completed),
        ],
      ),
    );
  }

  Widget _empty() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_download_outlined,
                  size: 44, color: cs.primary),
            ),
            const SizedBox(height: 18),
            const T('No downloads here',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              tr('Tap "Add link" to paste a file URL,\nor use the browser to find files.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(DownloadItem d) {
    final cs = Theme.of(context).colorScheme;
    final kind = FileKind.of(d.fileName);
    final done = d.status == DlStatus.completed;
    final running = d.status == DlStatus.downloading;
    final failed = d.status == DlStatus.failed;

    final sizeText = d.total > 0
        ? trOf(formatBytes(d.downloaded), formatBytes(d.total))
        : formatBytes(d.downloaded);

    String status;
    Color statusColor = cs.onSurfaceVariant;
    if (done) {
      status =
          '${tr('Completed')} · ${formatBytes(d.total > 0 ? d.total : d.downloaded)}';
      statusColor = const Color(0xFF16A34A);
    } else if (failed) {
      status = tr(d.error ?? 'Failed');
      statusColor = cs.error;
    } else if (d.status == DlStatus.paused) {
      status = dm.isWaitingForWifi(d)
          ? '${tr('Waiting for Wi-Fi')} · $sizeText'
          : '${tr('Paused')} · $sizeText';
    } else {
      status = '$sizeText · ${formatBytes(d.speed)}/s · ${formatEta(d)}';
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: done ? () => OpenFilex.open(d.savePath) : null,
        onLongPress: () => _confirmRemove(d),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: kind.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(kind.icon, color: kind.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 3),
                        Text(status,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12.5, color: statusColor)),
                      ],
                    ),
                  ),
                  if (done)
                    IconButton(
                      tooltip: tr('Open'),
                      icon: const Icon(Icons.open_in_new_rounded),
                      onPressed: () => OpenFilex.open(d.savePath),
                    )
                  else if (running)
                    IconButton.filledTonal(
                      tooltip: tr('Pause'),
                      icon: const Icon(Icons.pause_rounded),
                      onPressed: () => dm.pause(d),
                    )
                  else
                    IconButton.filledTonal(
                      tooltip: failed ? tr('Retry') : tr('Resume'),
                      icon: Icon(failed
                          ? Icons.refresh_rounded
                          : Icons.play_arrow_rounded),
                      onPressed: () => dm.start(d),
                    ),
                  IconButton(
                    tooltip: tr('More'),
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _confirmRemove(d),
                  ),
                ],
              ),
              if (!done) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: d.total > 0 ? d.progress : (running ? null : 0),
                      color: failed ? cs.error : kind.color,
                      backgroundColor: kind.color.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                if (d.total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${(d.progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant)),
                        if (!d.rangeSupported)
                          T('Single stream · no resume',
                              style: TextStyle(
                                  fontSize: 11, color: cs.outline)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
