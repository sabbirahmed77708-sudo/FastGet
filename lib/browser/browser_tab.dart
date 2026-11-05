import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// A resource the page requested (shown in "View Page Resources").
class ResourceEntry {
  final String url;
  final String type;
  const ResourceEntry(this.url, this.type);
}

/// One browser tab. Owns its own WebView controller, so every tab keeps an
/// independent navigation history. Extends [ChangeNotifier] so the toolbar and
/// the tabs drawer can follow the tab live.
class BrowserTab extends ChangeNotifier {
  BrowserTab({
    required this.id,
    String? url,
    this.windowId,
    String title = '',
    bool showHome = true,
  })  : pendingUrl = url,
        _url = url ?? '',
        _title = title,
        _showHome = showHome && windowId == null;

  final String id;

  /// Set when the tab was opened by a page (target=_blank / window.open).
  int? windowId;

  /// URL the WebView is created with. `null` = no WebView yet (home page).
  String? pendingUrl;

  /// True once a WebView should exist for this tab.
  bool wantsWebView = false;

  InAppWebViewController? controller;
  FindInteractionController? findController;

  String _url;
  String _title;
  Uint8List? favicon;
  int progress = 0;
  bool isLoading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  String? error;
  bool _showHome;

  // find in page
  int findActive = 0;
  int findTotal = 0;

  final List<ResourceEntry> resources = [];
  final List<String> mediaUrls = [];

  String get url => _url;
  String get title => _title;
  bool get showHome => _showHome;
  bool get hasWebView => wantsWebView || pendingUrl != null || windowId != null;
  bool get isSecure => _url.startsWith('https://');
  bool get isHttp => _url.startsWith('http://');

  String get host {
    final u = Uri.tryParse(_url);
    final h = u?.host ?? '';
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  String get displayTitle {
    if (_showHome && !hasWebView) return 'New tab';
    if (_title.trim().isNotEmpty) return _title.trim();
    if (host.isNotEmpty) return host;
    return isLoading ? 'Loading…' : 'New tab';
  }

  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  void setUrl(String u) {
    if (u == _url) return;
    final oldHost = host;
    _url = u;
    if (host != oldHost) favicon = null;
    notifyListeners();
  }

  void setTitle(String t) {
    _title = t;
    notifyListeners();
  }

  void setShowHome(bool v) {
    _showHome = v;
    notifyListeners();
  }

  void addResource(String url, String type) {
    if (resources.length >= 600) resources.removeAt(0);
    resources.add(ResourceEntry(url, type));
    // no notify: resources are read on demand
  }

  /// Called when the owning screen goes away; WebViews are destroyed with it.
  void detach() {
    controller = null;
    findController = null;
    windowId = null; // a popup WebView cannot be re-created from its window id
    if (_url.isNotEmpty) {
      pendingUrl = _url;
      wantsWebView = true;
    }
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': _url,
        'title': _title,
        'showHome': _showHome,
      };
}
