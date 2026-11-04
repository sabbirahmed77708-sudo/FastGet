import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_tab.dart';

class Shortcut {
  final String name;
  final String url;
  const Shortcut(this.name, this.url);
  Map<String, dynamic> toJson() => {'name': name, 'url': url};
  factory Shortcut.fromJson(Map<String, dynamic> j) =>
      Shortcut(j['name'] as String, j['url'] as String);
}

class HistoryEntry {
  final String title;
  final String url;
  final int time; // millisecondsSinceEpoch
  const HistoryEntry(this.title, this.url, this.time);
  Map<String, dynamic> toJson() => {'t': title, 'u': url, 'm': time};
  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
      j['t'] as String, j['u'] as String, (j['m'] as num).toInt());
}

/// Domains / patterns blocked when "Block Ads" is on.
const List<String> _adPatterns = [
  r'.*doubleclick\.net.*',
  r'.*googlesyndication\.com.*',
  r'.*googleadservices\.com.*',
  r'.*adservice\.google\..*',
  r'.*google-analytics\.com.*',
  r'.*googletagmanager\.com.*',
  r'.*adnxs\.com.*',
  r'.*taboola\.com.*',
  r'.*outbrain\.com.*',
  r'.*popads\.net.*',
  r'.*popcash\.net.*',
  r'.*propellerads\.com.*',
  r'.*exoclick\.com.*',
  r'.*adsterra\.com.*',
  r'.*pubmatic\.com.*',
  r'.*criteo\.(com|net).*',
  r'.*amazon-adsystem\.com.*',
  r'.*/ads/.*\.js.*',
];

const List<Shortcut> _defaultShortcuts = [
  Shortcut('Google', 'https://www.google.com'),
  Shortcut('Wikipedia', 'https://www.wikipedia.org'),
  Shortcut('GitHub', 'https://github.com'),
  Shortcut('Reddit', 'https://www.reddit.com'),
];

/// Central state of the browser: tabs, settings, bookmarks and history.
class BrowserController extends ChangeNotifier {
  BrowserController._();
  static final BrowserController instance = BrowserController._();

  final List<BrowserTab> tabs = [];
  int active = 0;

  bool blockAds = false;
  bool captureMedia = false;
  bool desktopMode = false;
  ThemeMode themeMode = ThemeMode.system;

  List<Shortcut> shortcuts = [];
  List<Shortcut> bookmarks = [];
  List<HistoryEntry> history = [];

  SharedPreferences? _prefs;
  int _idSeed = 0;

  BrowserTab get current => tabs[active];

  // ---------------------------------------------------------------- init

  Future<void> init() async {
    final p = _prefs = await SharedPreferences.getInstance();
    blockAds = p.getBool('b_blockAds') ?? false;
    captureMedia = p.getBool('b_capture') ?? false;
    desktopMode = p.getBool('b_desktop') ?? false;
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == p.getString('b_theme'),
      orElse: () => ThemeMode.system,
    );

    shortcuts = _readList(p, 'b_shortcuts', Shortcut.fromJson);
    if (!p.containsKey('b_shortcuts')) shortcuts = [..._defaultShortcuts];
    bookmarks = _readList(p, 'b_bookmarks', Shortcut.fromJson);
    history = _readList(p, 'b_history', HistoryEntry.fromJson);

    // restore tabs
    try {
      final raw = p.getString('b_tabs');
      if (raw != null) {
        for (final e in jsonDecode(raw) as List) {
          final m = e as Map<String, dynamic>;
          final url = (m['url'] as String?) ?? '';
          tabs.add(BrowserTab(
            id: _nextId(),
            url: url.isEmpty ? null : url,
            title: (m['title'] as String?) ?? '',
            showHome: (m['showHome'] as bool?) ?? url.isEmpty,
          ));
        }
        active = (p.getInt('b_active') ?? 0).clamp(0, tabs.length - 1);
      }
    } catch (_) {
      tabs.clear();
    }
    if (tabs.isEmpty) {
      tabs.add(BrowserTab(id: _nextId()));
      active = 0;
    }
  }

  List<T> _readList<T>(SharedPreferences p, String key,
      T Function(Map<String, dynamic>) f) {
    try {
      final raw = p.getString(key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => f(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _nextId() => '${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}';

  // --------------------------------------------------------- persistence

  Future<void> save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setBool('b_blockAds', blockAds);
    await p.setBool('b_capture', captureMedia);
    await p.setBool('b_desktop', desktopMode);
    await p.setString('b_theme', themeMode.name);
    await p.setString(
        'b_shortcuts', jsonEncode(shortcuts.map((e) => e.toJson()).toList()));
    await p.setString(
        'b_bookmarks', jsonEncode(bookmarks.map((e) => e.toJson()).toList()));
    await p.setString('b_history',
        jsonEncode(history.take(500).map((e) => e.toJson()).toList()));
    await saveTabs();
  }

  Future<void> saveTabs() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString('b_tabs', jsonEncode(tabs.map((t) => t.toJson()).toList()));
    await p.setInt('b_active', active);
  }

  // ---------------------------------------------------------------- tabs

  BrowserTab newTab({String? url, int? windowId, bool activate = true}) {
    final t = BrowserTab(
      id: _nextId(),
      url: url,
      windowId: windowId,
      showHome: url == null && windowId == null,
    );
    if (url != null) t.wantsWebView = true;
    tabs.add(t);
    if (activate) active = tabs.length - 1;
    saveTabs();
    notifyListeners();
    return t;
  }

  void switchTo(int i) {
    if (i < 0 || i >= tabs.length || i == active) return;
    active = i;
    saveTabs();
    notifyListeners();
  }

  void closeTab(int i) {
    if (i < 0 || i >= tabs.length) return;
    final t = tabs.removeAt(i);
    if (tabs.isEmpty) {
      tabs.add(BrowserTab(id: _nextId()));
      active = 0;
    } else if (i < active) {
      active -= 1;
    } else if (active >= tabs.length) {
      active = tabs.length - 1;
    }
    // dispose after the frame so the WebView widget can be removed first
    WidgetsBinding.instance.addPostFrameCallback((_) => t.dispose());
    saveTabs();
    notifyListeners();
  }

  void closeTabById(String id) => closeTab(tabs.indexWhere((t) => t.id == id));

  /// The screen showing the WebViews is being destroyed.
  void detachAll() {
    for (final t in tabs) {
      t.detach();
    }
  }

  // ---------------------------------------------------------- navigation

  /// Turns whatever the user typed into a URL or a Google search.
  static String resolveInput(String input) {
    final t = input.trim();
    if (t.isEmpty) return t;
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return t;
    if (lower.startsWith('file://') || lower.startsWith('about:')) return t;
    final looksLikeHost = !t.contains(' ') &&
        (t.contains('.') || lower.startsWith('localhost')) &&
        !t.endsWith('.');
    if (looksLikeHost) return 'https://$t';
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(t)}';
  }

  Future<void> navigate(String input, {BrowserTab? tab}) async {
    final t = tab ?? current;
    final url = resolveInput(input);
    if (url.isEmpty) return;
    t.error = null;
    t.setShowHome(false);
    final c = t.controller;
    if (c == null) {
      // WebView not created yet: it will be built with this URL
      t.pendingUrl = url;
      t.wantsWebView = true;
      t.setUrl(url);
    } else {
      t.setUrl(url);
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
    notifyListeners();
    saveTabs();
  }

  Future<void> goBack() async {
    final t = current;
    if (t.showHome && t.controller != null) {
      t.setShowHome(false); // return to the page hidden behind the homepage
      return;
    }
    if (await t.controller?.canGoBack() ?? false) {
      await t.controller!.goBack();
    }
  }

  Future<void> goForward() async {
    final t = current;
    if (t.showHome) return;
    if (await t.controller?.canGoForward() ?? false) {
      await t.controller!.goForward();
    }
  }

  void goHome() {
    current.setShowHome(true);
    notifyListeners();
    saveTabs();
  }

  Future<void> reload() async {
    final t = current;
    if (t.showHome) return;
    t.error = null;
    if (t.isLoading) {
      await t.controller?.stopLoading();
    } else {
      await t.controller?.reload();
    }
  }

  Future<void> refreshNavState(BrowserTab t) async {
    final c = t.controller;
    if (c == null) return;
    final b = await c.canGoBack();
    final f = await c.canGoForward();
    if (b != t.canGoBack || f != t.canGoForward) {
      t.update(() {
        t.canGoBack = b;
        t.canGoForward = f;
      });
    }
  }

  // ------------------------------------------------------------ settings

  InAppWebViewSettings webSettings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        useOnDownloadStart: true,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: true,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
        safeBrowsingEnabled: true,
        thirdPartyCookiesEnabled: true,
        domStorageEnabled: true,
        preferredContentMode: desktopMode
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.RECOMMENDED,
        contentBlockers: blockAds
            ? [
                for (final p in _adPatterns)
                  ContentBlocker(
                    trigger: ContentBlockerTrigger(urlFilter: p),
                    action:
                        ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
                  ),
              ]
            : [],
      );

  Future<void> _applySettings({bool reloadPages = false}) async {
    final s = webSettings();
    for (final t in tabs) {
      final c = t.controller;
      if (c == null) continue;
      try {
        await c.setSettings(settings: s);
        if (reloadPages && !t.showHome) await c.reload();
      } catch (_) {}
    }
  }

  Future<void> setBlockAds(bool v) async {
    blockAds = v;
    notifyListeners();
    await _applySettings(reloadPages: true);
    await save();
  }

  Future<void> setDesktopMode(bool v) async {
    desktopMode = v;
    notifyListeners();
    await _applySettings(reloadPages: true);
    await save();
  }

  Future<void> setCaptureMedia(bool v) async {
    captureMedia = v;
    if (!v) {
      for (final t in tabs) {
        t.mediaUrls.clear();
      }
    }
    notifyListeners();
    await save();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await save();
  }

  // ----------------------------------------------------------- bookmarks

  bool isBookmarked(String url) => bookmarks.any((b) => b.url == url);

  Future<void> toggleBookmark(BrowserTab t) async {
    if (t.url.isEmpty) return;
    if (isBookmarked(t.url)) {
      bookmarks.removeWhere((b) => b.url == t.url);
    } else {
      bookmarks.insert(
          0, Shortcut(t.title.isNotEmpty ? t.title : t.host, t.url));
    }
    notifyListeners();
    await save();
  }

  Future<void> removeBookmark(Shortcut b) async {
    bookmarks.removeWhere((e) => e.url == b.url);
    notifyListeners();
    await save();
  }

  // ------------------------------------------------------------- history

  void addHistory(BrowserTab t) {
    final u = t.url;
    if (u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))) {
      return;
    }
    if (history.isNotEmpty && history.first.url == u) return;
    history.insert(
        0,
        HistoryEntry(t.title.isNotEmpty ? t.title : t.host, u,
            DateTime.now().millisecondsSinceEpoch));
    if (history.length > 500) history.removeRange(500, history.length);
    save();
  }

  Future<void> clearHistory() async {
    history.clear();
    notifyListeners();
    await save();
  }

  // ----------------------------------------------------------- shortcuts

  Future<void> addShortcut(String name, String url) async {
    final u = resolveInput(url);
    final n = name.trim().isEmpty ? (Uri.tryParse(u)?.host ?? u) : name.trim();
    shortcuts.add(Shortcut(n, u));
    notifyListeners();
    await save();
  }

  Future<void> removeShortcut(Shortcut s) async {
    shortcuts.remove(s);
    notifyListeners();
    await save();
  }

  // -------------------------------------------------------- clear data

  Future<void> clearBrowsingData(
      {bool history = true, bool cache = true, bool cookies = true}) async {
    if (cache) {
      for (final t in tabs) {
        try {
          await t.controller?.clearAllCache();
        } catch (_) {}
      }
    }
    if (cookies) {
      try {
        await CookieManager.instance().deleteAllCookies();
      } catch (_) {}
      try {
        await WebStorageManager.instance().deleteAllData();
      } catch (_) {}
    }
    if (history) this.history.clear();
    notifyListeners();
    await save();
  }

  // -------------------------------------------------------------- media

  static const _mediaExt = {
    'mp4', 'webm', 'mkv', 'mov', '3gp', 'mp3', 'm4a', 'aac', 'ogg', 'wav',
    'flac',
  };

  /// Direct media file URLs only. Streaming sites (YouTube etc.) are skipped.
  bool isCapturableMedia(String url, {bool fromMediaElement = false}) {
    final u = Uri.tryParse(url);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) {
      return false;
    }
    final h = u.host.toLowerCase();
    if (h.endsWith('googlevideo.com') ||
        h.endsWith('youtube.com') ||
        h.endsWith('youtu.be')) {
      return false;
    }
    final last = u.pathSegments.isNotEmpty ? u.pathSegments.last : '';
    final ext = last.contains('.') ? last.split('.').last.toLowerCase() : '';
    if (ext == 'm3u8' || ext == 'mpd') return false; // adaptive streams
    return _mediaExt.contains(ext) || fromMediaElement;
  }

  void addMedia(BrowserTab t, String url) {
    if (!captureMedia) return;
    if (t.mediaUrls.contains(url)) return;
    t.mediaUrls.add(url);
    t.update(() {});
  }
}
