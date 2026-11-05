import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../download_manager.dart';
import '../models.dart';
import '../theme.dart';
import '../l10n.dart';

/// A download the browser wants to hand over to DROM.
class DownloadRequest {
  final String url;
  final String? fileName;
  final String? mimeType;
  final int? size;
  final String? userAgent;
  final String? referer;
  const DownloadRequest({
    required this.url,
    this.fileName,
    this.mimeType,
    this.size,
    this.userAgent,
    this.referer,
  });
}

String _guessName(String url) {
  final u = Uri.tryParse(url);
  var n = (u != null && u.pathSegments.isNotEmpty) ? u.pathSegments.last : '';
  try {
    n = Uri.decodeComponent(n);
  } catch (_) {}
  return n.isEmpty ? 'download' : n;
}

String _typeLabel(String name, String? mime) {
  final e = name.contains('.') ? name.split('.').last.toUpperCase() : '';
  if (e.isNotEmpty && e.length <= 5) return '$e file';
  if (mime != null && mime.isNotEmpty && mime != 'application/octet-stream') {
    return mime;
  }
  return 'File';
}

/// Shows the DROM confirmation sheet. Returns true when the download started.
Future<bool> showDownloadPrompt(
    BuildContext context, DownloadRequest req) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PromptSheet(req: req),
  );
  return result == true;
}

class _PromptSheet extends StatefulWidget {
  final DownloadRequest req;
  const _PromptSheet({required this.req});

  @override
  State<_PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<_PromptSheet> {
  late Future<ProbeResult> _probe;
  bool _busy = false;
  String? _error;

  Future<Map<String, String>> _headers() async {
    final h = <String, String>{};
    final r = widget.req;
    if (r.userAgent != null && r.userAgent!.isNotEmpty) {
      h['User-Agent'] = r.userAgent!;
    }
    if (r.referer != null && r.referer!.startsWith('http')) {
      h['Referer'] = r.referer!;
    }
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri(r.url));
      if (cookies.isNotEmpty) {
        h['Cookie'] = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
    } catch (_) {}
    return h;
  }

  @override
  void initState() {
    super.initState();
    _probe = _load();
  }

  Future<ProbeResult> _load() async {
    final headers = await _headers();
    return DownloadManager.instance.inspect(widget.req.url, headers: headers);
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final headers = await _headers();
      await DownloadManager.instance.addUrl(
        widget.req.url,
        headers: headers,
        suggestedName: widget.req.fileName,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.req;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 16),
        child: FutureBuilder<ProbeResult>(
          future: _probe,
          builder: (context, snap) {
            final loading = snap.connectionState != ConnectionState.done;
            final info = snap.data;
            final name = (r.fileName != null && r.fileName!.isNotEmpty)
                ? r.fileName!
                : (info?.fileName ?? _guessName(r.url));
            final size = (r.size != null && r.size! > 0)
                ? r.size!
                : (info?.total ?? -1);
            final mime = r.mimeType ?? info?.contentType;
            final kind = FileKind.of(name);
            final ct = (info?.contentType ?? '').toLowerCase();
            final isPage = ct.startsWith('text/html') &&
                !name.toLowerCase().endsWith('.html') &&
                !name.toLowerCase().endsWith('.htm');
            final probeError = snap.hasError ? snap.error.toString() : null;
            final blocked = isPage || probeError != null;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.bolt_rounded, color: cs.primary),
                  const SizedBox(width: 6),
                  const T('DROM Download',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: kind.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(kind.icon, color: kind.color, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(
                          '${_typeLabel(name, mime)} · '
                          '${size > 0 ? formatBytes(size) : (loading ? tr('checking…') : tr('size unknown'))}',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(Uri.tryParse(r.url)?.host ?? r.url,
                    style: TextStyle(color: cs.outline, fontSize: 12)),
                if (info != null && !info.range && !blocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: T('This server does not support fast multi-part download or resume.',
                        style: TextStyle(color: cs.outline, fontSize: 12)),
                  ),
                if (isPage)
                  _note(cs,
                      'This link returns a web page, not a downloadable file.'),
                if (probeError != null) _note(cs, probeError),
                if (_error != null) _note(cs, _error!),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const T('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: (_busy || loading || blocked) ? null : _start,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded),
                      label: const T('Download'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _note(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
            const SizedBox(width: 6),
            Expanded(
                child: Text(tr(text),
                    style: TextStyle(color: cs.error, fontSize: 13))),
          ],
        ),
      );
}
