import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../download_manager.dart';
import '../models.dart';
import 'browser_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final dm = DownloadManager.instance;

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

  Future<void> _addDialog({String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    if (initial == null) {
      final clip = await Clipboard.getData('text/plain');
      final t = clip?.text?.trim() ?? '';
      if (t.startsWith('http://') || t.startsWith('https://')) ctrl.text = t;
    }
    if (!mounted) return;
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('নতুন ডাউনলোড'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: 'ফাইলের লিংক পেস্ট করুন',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('বাতিল')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('ডাউনলোড')),
        ],
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openBrowser() async {
    final url = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BrowserScreen()),
    );
    if (url != null) await _add(url);
  }

  @override
  Widget build(BuildContext context) {
    final items = dm.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FastGet'),
        actions: [
          IconButton(
            tooltip: 'ব্রাউজার',
            icon: const Icon(Icons.public),
            onPressed: _openBrowser,
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'কোনো ডাউনলোড নেই।\nনিচের + বাটনে চেপে লিংক দিন,\nঅথবা উপরের ব্রাউজার থেকে ফাইল খুঁজুন।',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90, top: 8),
              itemCount: items.length,
              itemBuilder: (_, i) => _tile(items[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(),
        icon: const Icon(Icons.add),
        label: const Text('লিংক'),
      ),
    );
  }

  Widget _tile(DownloadItem d) {
    final cs = Theme.of(context).colorScheme;
    final done = d.status == DlStatus.completed;
    final running = d.status == DlStatus.downloading;

    String sub;
    switch (d.status) {
      case DlStatus.completed:
        sub = 'সম্পন্ন • ${formatBytes(d.total > 0 ? d.total : d.downloaded)}';
        break;
      case DlStatus.failed:
        sub = 'ব্যর্থ: ${d.error ?? ''}';
        break;
      case DlStatus.paused:
        sub =
            'পজড • ${formatBytes(d.downloaded)}${d.total > 0 ? ' / ${formatBytes(d.total)}' : ''}';
        break;
      default:
        sub =
            '${formatBytes(d.downloaded)}${d.total > 0 ? ' / ${formatBytes(d.total)}' : ''}'
            ' • ${formatBytes(d.speed)}/s • ${formatEta(d)}';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(d.fileName), color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(d.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (done)
                  IconButton(
                    icon: const Icon(Icons.open_in_new),
                    tooltip: 'খুলুন',
                    onPressed: () => OpenFilex.open(d.savePath),
                  )
                else if (running)
                  IconButton(
                    icon: const Icon(Icons.pause_circle_outline),
                    tooltip: 'পজ',
                    onPressed: () => dm.pause(d),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'রিজিউম',
                    onPressed: () => dm.start(d),
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'copy') {
                      await Clipboard.setData(ClipboardData(text: d.url));
                    } else if (v == 'remove') {
                      await dm.remove(d);
                    } else if (v == 'delete') {
                      await dm.remove(d, deleteFile: true);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy', child: Text('লিংক কপি')),
                    PopupMenuItem(
                        value: 'remove', child: Text('তালিকা থেকে সরান')),
                    PopupMenuItem(
                        value: 'delete', child: Text('ফাইলসহ মুছুন')),
                  ],
                ),
              ],
            ),
            if (!done) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(
                  value: d.total > 0 ? d.progress : (running ? null : 0),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(sub,
                style: TextStyle(
                    fontSize: 12,
                    color: d.status == DlStatus.failed
                        ? cs.error
                        : cs.onSurfaceVariant)),
            if (!d.rangeSupported && !done && d.total > 0)
              Text('এই সার্ভারে দ্রুত/রিজিউম সাপোর্ট নেই',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String name) {
    final e = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (['mp4', 'mkv', 'webm', 'avi', 'mov', '3gp'].contains(e)) {
      return Icons.movie_outlined;
    }
    if (['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'].contains(e)) {
      return Icons.music_note_outlined;
    }
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(e)) {
      return Icons.image_outlined;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(e)) {
      return Icons.folder_zip_outlined;
    }
    if (e == 'apk') return Icons.android;
    if (e == 'pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }
}
