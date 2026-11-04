import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// সাধারণ বিল্ট-ইন ব্রাউজার। ফাইল-লিংকে (zip, mp4, mp3, apk ...) ক্লিক করলে
/// ডাউনলোড করার প্রস্তাব দেয় এবং বাছাই করা লিংক হোম স্ক্রিনে ফেরত পাঠায়।
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
              const Text('ফাইল পাওয়া গেছে',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(url, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('না')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.download),
                    label: const Text('ডাউনলোড'),
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
              hintText: 'সার্চ করুন বা লিংক দিন',
              border: InputBorder.none,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'এই লিংক ডাউনলোড করুন',
              icon: const Icon(Icons.download),
              onPressed: () {
                if (_current.isNotEmpty) _offer(_current);
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
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
