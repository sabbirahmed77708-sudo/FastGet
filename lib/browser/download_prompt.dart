import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../download_manager.dart';
import '../folder_picker.dart';
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

bool _looksLikeFileName(String n) =>
    RegExp(r'\.[A-Za-z0-9]{1,5}$').hasMatch(n);

String _typeLabel(String name, String? mime) {
  final e = name.contains('.') ? name.split('.').last.toUpperCase() : '';
  if (e.isNotEmpty && e.length <= 5) return '$e file';
  if (mime != null && mime.isNotEmpty && mime != 'application/octet-stream') {
    return mime;
  }
  return 'File';
}

/// Quick save locations shown as chips in the popup.
const List<(String, String)> _quickFolders = [
  ('DROM folder', '$kStorageRoot/Download/FastGet'),
  ('Downloads', '$kStorageRoot/Download'),
  ('Movies', '$kStorageRoot/Movies'),
  ('Music', '$kStorageRoot/Music'),
  ('Documents', '$kStorageRoot/Documents'),
];

/// Shows the DROM download popup as a box in the middle of the screen. It
/// floats up with a soft bounce, lists every detail of the file, lets the
/// person rename it and pick where it is saved.
/// Returns true when the download started.
Future<bool> showDownloadPrompt(
    BuildContext context, DownloadRequest req) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, __, ___) => _PromptSheet(req: req),
    // one calm motion: slide up + fade, no overshoot, drawn as a cached layer
    transitionBuilder: (context, anim, _, child) {
      final c = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: c,
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero)
                  .animate(c),
          child: RepaintBoundary(child: child),
        ),
      );
    },
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
  late final Future<ProbeResult> _probe;
  late final TextEditingController _nameCtrl;
  bool _nameEdited = false;
  bool _editing = false;
  String? _dir;
  bool _busy = false;
  bool _copied = false;
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
    final r = widget.req;
    // Same name no matter how the link arrived (browser, paste, share):
    // the file name in the link wins over the browser's own guess
    // (e.g. "main.mkv"); the server's real name replaces both once checked.
    final fromUrl = _guessName(r.url);
    final given = r.fileName ?? '';
    _nameCtrl = TextEditingController(
        text: _looksLikeFileName(fromUrl)
            ? fromUrl
            : (given.isNotEmpty ? given : fromUrl));
    // network + folder lookup start after the popup has settled, so nothing
    // rebuilds while it is moving
    final settled = Future.delayed(const Duration(milliseconds: 400));
    _probe = settled.then((_) => _load());
    settled.then((_) => _initDir());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDir() async {
    final d = await DownloadManager.instance.preferredDir();
    if (mounted) setState(() => _dir = d);
  }

  Future<ProbeResult> _load() async {
    final headers = await _headers();
    final info =
        await DownloadManager.instance.inspect(widget.req.url, headers: headers);
    // the server's real file name wins, unless the person already typed one
    final real = info.fileName;
    if (!_nameEdited && real != null && real.isNotEmpty && mounted) {
      _nameCtrl.text = real;
    }
    return info;
  }

  Future<void> _chooseFolder() async {
    final p = await pickFolder(context, start: _dir);
    if (p != null && mounted) setState(() => _dir = p);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.req.url));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _start() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a file name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final headers = await _headers();
      final dm = DownloadManager.instance;
      await dm.addUrl(
        widget.req.url,
        headers: headers,
        suggestedName: name,
        dirPath: _dir,
      );
      if (_dir != null) await dm.setPreferredDir(_dir!);
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
    return FutureBuilder<ProbeResult>(
      future: _probe,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final info = snap.data;
        final name = _nameCtrl.text;
        final size =
            (r.size != null && r.size! > 0) ? r.size! : (info?.total ?? -1);
        final mime = r.mimeType ?? info?.contentType;
        final kind = FileKind.of(name);
        final ct = (info?.contentType ?? '').toLowerCase();
        final isPage = ct.startsWith('text/html') &&
            !name.toLowerCase().endsWith('.html') &&
            !name.toLowerCase().endsWith('.htm');
        final probeError = snap.hasError ? snap.error.toString() : null;
        final blocked = isPage || probeError != null;
        final host = Uri.tryParse(r.url)?.host ?? r.url;

        final rows = <Widget>[
          _row(cs, Icons.public_rounded, 'Source', host),
          _row(
            cs,
            Icons.bolt_rounded,
            'Download mode',
            info == null
                ? tr('checking…')
                : (info.hls
                    ? tr('Video stream · saved in pieces, resumable')
                    : info.range
                    ? tr('Fast multi-part · resumable')
                    : tr('Single stream · no resume')),
          ),
          _row(
            cs,
            Icons.link_rounded,
            'Link',
            r.url,
            maxLines: 3,
            onTap: _copyLink,
            trailing: Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
              color: _copied ? const Color(0xFF16A34A) : cs.outline,
            ),
          ),
        ];

        return Center(
          child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            elevation: 8,
            backgroundColor: Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Appear(
                      key: const ValueKey('head'),
                      index: 0,
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child:
                              Icon(Icons.download_rounded, color: cs.primary),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: T('Download file',
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          tooltip: tr('Cancel'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context, false),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    _Appear(
                      key: const ValueKey('file'),
                      index: 1,
                      child: _fileCard(cs, kind, name, mime, size, loading),
                    ),
                    const SizedBox(height: 12),
                    _Appear(
                      key: const ValueKey('details'),
                      index: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0)
                              Divider(
                                  height: 1,
                                  indent: 14,
                                  endIndent: 14,
                                  color: cs.outlineVariant),
                            rows[i],
                          ],
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Appear(
                      key: const ValueKey('save'),
                      index: 3,
                      child: _saveSection(cs),
                    ),
                    if (isPage)
                      _note(cs,
                          'This link returns a web page, not a downloadable file.'),
                    if (probeError != null) _note(cs, probeError),
                    if (_error != null) _note(cs, _error!),
                    const SizedBox(height: 18),
                    _Appear(
                      key: const ValueKey('buttons'),
                      index: 4,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.pop(context, false),
                              child: const T('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: (_busy ||
                                      loading ||
                                      blocked ||
                                      _dir == null)
                                  ? null
                                  : _start,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.download_rounded),
                              label: Text(size > 0
                                  ? '${tr('Download')} · ${formatBytes(size)}'
                                  : tr('Download')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The file: icon, the FULL file name (wraps, never cut), type and size.
  Widget _fileCard(ColorScheme cs, FileKind kind, String name, String? mime,
      int size, bool loading) {
    Widget chip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: kind.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: kind.color),
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kind.color)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.07),
        border: Border.all(color: kind.color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: kind.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(kind.icon, color: kind.color, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_editing)
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    minLines: 1,
                    maxLines: null,
                    onChanged: (_) => setState(() => _nameEdited = true),
                    decoration: InputDecoration(
                      labelText: tr('File name'),
                      isDense: true,
                    ),
                  )
                else
                  SelectableText(
                    name,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    chip(Icons.description_outlined, _typeLabel(name, mime)),
                    chip(
                        Icons.straighten_rounded,
                        size > 0
                            ? formatBytes(size)
                            : (loading
                                ? tr('checking…')
                                : tr('size unknown'))),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr(_editing ? 'Done' : 'Rename'),
            visualDensity: VisualDensity.compact,
            icon: Icon(_editing ? Icons.check_rounded : Icons.edit_rounded,
                size: 20),
            onPressed: _busy ? null : () => setState(() => _editing = !_editing),
          ),
        ],
      ),
    );
  }

  Widget _saveSection(ColorScheme cs) {
    final dir = _dir;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const T('Save to',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _busy ? null : _chooseFolder,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded, color: Color(0xFFF59E0B)),
                const SizedBox(width: 10),
                Expanded(
                  child: dir == null
                      ? const Text('…')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(folderName(dir),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5)),
                            Text(prettyPath(dir),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurfaceVariant)),
                          ],
                        ),
                ),
                TextButton(
                  onPressed: _busy ? null : _chooseFolder,
                  child: const T('Change'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final q in _quickFolders)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tr(q.$1)),
                    selected: _dir == q.$2,
                    showCheckmark: false,
                    onSelected:
                        _busy ? null : (_) => setState(() => _dir = q.$2),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.folder_open_rounded, size: 18),
                label: const T('Choose folder'),
                onPressed: _busy ? null : _chooseFolder,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(ColorScheme cs, IconData icon, String label, String value,
      {Widget? trailing, VoidCallback? onTap, int maxLines = 2}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Text(tr(label),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
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

/// Fades and slides a section up a little, one after another, once the popup
/// has floated in.
class _Appear extends StatefulWidget {
  final int index;
  final Widget child;
  const _Appear({super.key, required this.index, required this.child});

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> {
  @override
  Widget build(BuildContext context) => widget.child;
}
