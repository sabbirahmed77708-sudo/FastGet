import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'browser_controller.dart';
import 'browser_tab.dart';
import 'download_prompt.dart';
import '../l10n.dart';

/// Lists the resources the current page requested.
Future<void> showResourcesSheet(
  BuildContext context,
  BrowserTab tab,
  void Function(DownloadRequest) onDownload,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _UrlListSheet(
      title: 'Page resources',
      emptyText: 'No resources were recorded for this page yet.',
      entries: [for (final r in tab.resources.reversed) (r.url, r.type)],
      onDownload: (u) {
        Navigator.pop(ctx);
        onDownload(DownloadRequest(url: u, referer: tab.url));
      },
    ),
  );
}

/// Lists direct audio/video files found on the page ("Capture Audio/Video").
Future<void> showMediaSheet(
  BuildContext context,
  BrowserTab tab,
  void Function(DownloadRequest) onDownload,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _UrlListSheet(
      title: 'Audio / video on this page',
      emptyText: 'No direct media files found on this page.',
      entries: [for (final u in tab.mediaUrls) (u, 'media')],
      onDownload: (u) {
        Navigator.pop(ctx);
        onDownload(DownloadRequest(url: u, referer: tab.url));
      },
    ),
  );
}

class _UrlListSheet extends StatefulWidget {
  final String title;
  final String emptyText;
  final List<(String, String)> entries;
  final void Function(String url) onDownload;

  const _UrlListSheet({
    required this.title,
    required this.emptyText,
    required this.entries,
    required this.onDownload,
  });

  @override
  State<_UrlListSheet> createState() => _UrlListSheetState();
}

class _UrlListSheetState extends State<_UrlListSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = widget.entries
        .where((e) => _q.isEmpty || e.$1.toLowerCase().contains(_q))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              Expanded(
                child: Text('${tr(widget.title)} (${widget.entries.length})',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          if (widget.entries.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v.toLowerCase()),
                decoration: InputDecoration(
                  hintText: tr('Filter'),
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(tr(widget.emptyText),
                        style: TextStyle(color: cs.outline)))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final (url, type) = list[i];
                      return ListTile(
                        dense: true,
                        title: Text(url,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(type),
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: T('Link copied')));
                        },
                        trailing: IconButton(
                          tooltip: tr('Download with DROM'),
                          icon: const Icon(Icons.download_rounded),
                          onPressed: () => widget.onDownload(url),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Browsing history + bookmarks.
class HistoryScreen extends StatelessWidget {
  final BrowserController browser;
  const HistoryScreen({super.key, required this.browser});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const T('History'),
          actions: [
            IconButton(
              tooltip: tr('Clear history'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const T('Clear history?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const T('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const T('Clear')),
                    ],
                  ),
                );
                if (ok == true) await browser.clearHistory();
              },
            ),
          ],
          bottom: TabBar(tabs: [Tab(text: tr('History')), Tab(text: tr('Bookmarks'))]),
        ),
        body: ListenableBuilder(
          listenable: browser,
          builder: (context, _) => TabBarView(children: [
            _list(
              context,
              [for (final h in browser.history) (h.title, h.url)],
              'No history yet',
            ),
            _list(
              context,
              [for (final b in browser.bookmarks) (b.name, b.url)],
              'No bookmarks yet',
              onDelete: (url) => browser.removeBookmark(
                  browser.bookmarks.firstWhere((b) => b.url == url)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<(String, String)> items, String empty,
      {void Function(String url)? onDelete}) {
    if (items.isEmpty) {
      return Center(
          child: Text(tr(empty),
              style: TextStyle(color: Theme.of(context).colorScheme.outline)));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final (title, url) = items[i];
        return ListTile(
          title: Text(title.isEmpty ? url : title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: onDelete == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.bookmark_remove_outlined),
                  onPressed: () => onDelete(url),
                ),
          onTap: () {
            browser.navigate(url);
            Navigator.pop(context);
          },
        );
      },
    );
  }
}

/// Browser settings.
class BrowserSettingsScreen extends StatelessWidget {
  final BrowserController browser;
  const BrowserSettingsScreen({super.key, required this.browser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const T('Settings')),
      body: ListenableBuilder(
        listenable: browser,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const T('Block ads'),
              subtitle: const T('Blocks common ad and tracker domains'),
              value: browser.blockAds,
              onChanged: browser.setBlockAds,
            ),
            SwitchListTile(
              title: const T('Desktop mode'),
              subtitle: const T('Request the desktop version of sites'),
              value: browser.desktopMode,
              onChanged: browser.setDesktopMode,
            ),
            SwitchListTile(
              title: const T('Capture audio / video'),
              subtitle:
                  const T('Lists direct media files found on a page'),
              value: browser.captureMedia,
              onChanged: browser.setCaptureMedia,
            ),
            const Divider(),
            ListTile(
              title: const T('Theme'),
              trailing: DropdownButton<ThemeMode>(
                value: browser.themeMode,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                      value: ThemeMode.system, child: T('System')),
                  DropdownMenuItem(value: ThemeMode.light, child: T('Light')),
                  DropdownMenuItem(value: ThemeMode.dark, child: T('Dark')),
                ],
                onChanged: (m) {
                  if (m != null) browser.setThemeMode(m);
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: const T('Clear browsing data'),
              subtitle: const T('History, cache, cookies and site data'),
              onTap: () => confirmClearData(context, browser),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> confirmClearData(
    BuildContext context, BrowserController browser) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const T('Clear browsing data?'),
      content: Text(
          tr('This removes history, cache, cookies and saved site data. ') +
              tr('You will be signed out of websites.')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const T('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const T('Clear')),
      ],
    ),
  );
  if (ok == true) {
    await browser.clearBrowsingData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('Browsing data cleared')));
    }
  }
}
