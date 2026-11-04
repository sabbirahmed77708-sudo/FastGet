import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Simple built-in browser. Tapping a file link (zip, mp4, mp3, apk ...) offers
/// to download it and returns the chosen URL to the home screen.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static const _fileExt = {
    'mp4', 'mkv', 'webm', 'avi', 'mov', '3gp', 'mp3', 'm4a', 'aac', 'wav',
    'flac', 'ogg', 'zip', 'rar', '7z', 'tar', 'gz', 'apk', 'pdf', 'iso',
    'exe', 'msi', 'dmg', 'torrent', 'jpg', 'jpeg', 'png', 'gif', 'webp',
    'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'epub',
  };

  late final WebViewController _c;
  final _urlCtrl = TextEditingController();
  int _progress = 0;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (u) => _setUrl(u),
        onUrlChange: (c) {
          if (c.url != null) _setUrl(c.url!);
        },
        onNavigationRequest: (req) {
          if (_looksLikeFile(req.url)) {
            _offer(req.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse('https://www.google.com'));
  }

  void _setUrl(String u) {
    _current = u;
    if (mounted) setState(() => _urlCtrl.text = u);
  }

  bool _looksLikeFile(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return false;
    final last = uri.pathSegments.last;
    if (!last.contains('.')) return false;
    return _fileExt.contains(last.split('.').last.toLowerCase());
  }

  Future<void> _offer(String url) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('File detected',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(url, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, url);
  }

  void _go(String text) {
    var t = text.trim();
    if (t.isEmpty) return;
    Uri uri;
    if (t.startsWith('http://') || t.startsWith('https://')) {
      uri = Uri.parse(t);
    } else if (t.contains('.') && !t.contains(' ')) {
      uri = Uri.parse('https://$t');
    } else {
      uri = Uri.https('www.google.com', '/search', {'q': t});
    }
    _c.loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _c.canGoBack()) {
          await _c.goBack();
        } else if (context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: _go,
            decoration: const InputDecoration(
              hintText: 'Search or enter address',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Download this link',
              icon: const Icon(Icons.download_rounded),
              onPressed: () {
                if (_current.isNotEmpty) _offer(_current);
              },
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _c.reload(),
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress / 100),
                )
              : null,
        ),
        body: WebViewWidget(controller: _c),
      ),
    );
  }
}
