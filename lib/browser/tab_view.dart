import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_controller.dart';
import 'browser_tab.dart';
import 'download_prompt.dart';
import 'home_page.dart';

/// Renders one tab: its WebView (kept alive underneath), the homepage overlay
/// and the error page.
class TabView extends StatelessWidget {
  final BrowserTab tab;
  final BrowserController browser;
  final void Function(DownloadRequest) onDownload;

  const TabView({
    super.key,
    required this.tab,
    required this.browser,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tab,
      builder: (context, _) {
        return Stack(
          children: [
            if (tab.hasWebView)
              Positioned.fill(
                child: _WebHost(
                  key: ValueKey('host_${tab.id}'),
                  tab: tab,
                  browser: browser,
                  onDownload: onDownload,
                ),
              ),
            if (tab.error != null && !tab.showHome)
              Positioned.fill(child: _ErrorView(tab: tab, browser: browser)),
            if (tab.showHome) Positioned.fill(child: HomePage(browser: browser)),
          ],
        );
      },
    );
  }
}

/// Creates the InAppWebView exactly once per tab, so rebuilding the UI (drawer,
/// menu, toolbar) never recreates the WebView or loses the page.
class _WebHost extends StatefulWidget {
  final BrowserTab tab;
  final BrowserController browser;
  final void Function(DownloadRequest) onDownload;

  const _WebHost({
    super.key,
    required this.tab,
    required this.browser,
    required this.onDownload,
  });

  @override
  State<_WebHost> createState() => _WebHostState();
}

class _WebHostState extends State<_WebHost> {
  late final Widget _web;

  BrowserTab get tab => widget.tab;
  BrowserController get browser => widget.browser;

  static const _fileExt = {
    'zip', 'rar', '7z', 'tar', 'gz', 'iso', 'apk', 'pdf', 'exe', 'msi', 'dmg',
    'torrent', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'epub', 'mp3',
    'm4a', 'aac', 'wav', 'flac', 'ogg', 'mp4', 'mkv', 'webm', 'avi', 'mov',
    '3gp',
  };

  bool _looksLikeFile(Uri u) {
    if (u.pathSegments.isEmpty) return false;
    final last = u.pathSegments.last;
    if (!last.contains('.')) return false;
    return _fileExt.contains(last.split('.').last.toLowerCase());
  }

  @override
  void initState() {
    super.initState();

    tab.findController = FindInteractionController(
      onFindResultReceived:
          (controller, activeMatchOrdinal, numberOfMatches, isDoneCounting) {
        tab.update(() {
          tab.findActive = activeMatchOrdinal;
          tab.findTotal = numberOfMatches;
        });
      },
    );

    final usePopupWindow = tab.windowId != null;

    _web = InAppWebView(
      key: ValueKey('wv_${tab.id}'),
      windowId: tab.windowId,
      initialUrlRequest: (!usePopupWindow && tab.pendingUrl != null)
          ? URLRequest(url: WebUri(tab.pendingUrl!))
          : null,
      initialSettings: browser.webSettings(),
      findInteractionController: tab.findController,
      onWebViewCreated: (c) => tab.controller = c,
      onLoadStart: (c, url) {
        if (url != null) tab.setUrl(url.toString());
        tab.update(() {
          tab.isLoading = true;
          tab.progress = 5;
          tab.error = null;
          tab.resources.clear();
          tab.mediaUrls.clear();
        });
      },
      onProgressChanged: (c, p) {
        tab.update(() {
          tab.progress = p;
          tab.isLoading = p < 100;
        });
      },
      onUpdateVisitedHistory: (c, url, isReload) {
        if (url != null) tab.setUrl(url.toString());
        browser.refreshNavState(tab);
      },
      onTitleChanged: (c, title) {
        if (title != null) tab.setTitle(title);
      },
      onReceivedIcon: (c, Uint8List icon) {
        tab.update(() => tab.favicon = icon);
      },
      onLoadStop: (c, url) async {
        if (url != null) tab.setUrl(url.toString());
        final title = await c.getTitle();
        if (title != null && title.isNotEmpty) tab.setTitle(title);
        tab.update(() {
          tab.isLoading = false;
          tab.progress = 100;
        });
        await browser.refreshNavState(tab);
        browser.addHistory(tab);
        browser.saveTabs();
        if (browser.captureMedia) _scanMedia(c);
      },
      onReceivedError: (c, request, error) {
        if (!(request.isForMainFrame ?? false)) return;
        final d = error.description;
        if (d.contains('ERR_ABORTED')) return; // e.g. a download took over
        tab.update(() {
          tab.error = d.isEmpty ? 'The page could not be loaded' : d;
          tab.isLoading = false;
        });
      },
      onDownloadStartRequest: (c, req) {
        widget.onDownload(DownloadRequest(
          url: req.url.toString(),
          fileName: req.suggestedFilename,
          mimeType: req.mimeType,
          size: req.contentLength > 0 ? req.contentLength : null,
          userAgent: req.userAgent,
          referer: tab.url,
        ));
      },
      shouldOverrideUrlLoading: (c, action) async {
        final u = action.request.url;
        if (u == null) return NavigationActionPolicy.ALLOW;
        final scheme = u.scheme;
        if (scheme == 'http' || scheme == 'https') {
          final uri = Uri.tryParse(u.toString());
          if ((action.isForMainFrame) && uri != null && _looksLikeFile(uri)) {
            widget.onDownload(DownloadRequest(
              url: u.toString(),
              userAgent: null,
              referer: tab.url,
            ));
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        }
        const ok = {'about', 'data', 'blob', 'javascript', 'file'};
        return ok.contains(scheme)
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onCreateWindow: (c, action) async {
        browser.newTab(windowId: action.windowId);
        return true;
      },
      onCloseWindow: (c) => browser.closeTabById(tab.id),
      onLoadResource: (c, r) {
        final url = r.url?.toString();
        if (url == null) return;
        tab.addResource(url, r.initiatorType ?? 'resource');
        if (browser.captureMedia && browser.isCapturableMedia(url)) {
          browser.addMedia(tab, url);
        }
      },
    );
  }

  Future<void> _scanMedia(InAppWebViewController c) async {
    try {
      final res = await c.evaluateJavascript(source: '''
(function(){
  var out=[];
  document.querySelectorAll('video,audio,source').forEach(function(e){
    var s=e.currentSrc||e.src; if(s) out.push(s);
  });
  return out;
})()
''');
      if (res is List) {
        for (final s in res) {
          if (s is String &&
              browser.isCapturableMedia(s, fromMediaElement: true)) {
            browser.addMedia(tab, s);
          }
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    tab.controller = null;
    try {
      tab.findController?.dispose();
    } catch (_) {}
    tab.findController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _web;
}

class _ErrorView extends StatelessWidget {
  final BrowserTab tab;
  final BrowserController browser;
  const _ErrorView({required this.tab, required this.browser});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: cs.outline),
          const SizedBox(height: 16),
          const Text("Can't open this page",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(tab.error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(tab.url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, fontSize: 12)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              tab.update(() => tab.error = null);
              tab.controller?.reload();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
