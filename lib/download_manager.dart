import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const int kSegments = 4;
const String _ua =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0 Mobile Safari/537.36';

class _Run {
  final CancelToken token = CancelToken();
  Timer? ticker;
  List<int> segBytes = [];
}

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'User-Agent': _ua},
    followRedirects: true,
    maxRedirects: 8,
  ));

  final List<DownloadItem> items = [];
  final Map<String, _Run> _runs = {};
  SharedPreferences? _prefs;
  String? _dir;

  // ---------------------------------------------------------------- init

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('items');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        items.addAll(
            list.map((e) => DownloadItem.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setString(
        'items', jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// Download folder: Downloads/FastGet (falls back to the app's own folder without permission)
  Future<String> downloadDir() async {
    if (_dir != null) return _dir!;
    String? path;
    if (Platform.isAndroid) {
      var st = await Permission.manageExternalStorage.status;
      if (!st.isGranted) st = await Permission.manageExternalStorage.request();
      if (!st.isGranted) {
        final s2 = await Permission.storage.request();
        if (s2.isGranted) st = s2;
      }
      if (st.isGranted) {
        final d = Directory('/storage/emulated/0/Download/FastGet');
        try {
          await d.create(recursive: true);
          path = d.path;
        } catch (_) {}
      }
    }
    if (path == null) {
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/FastGet');
      await d.create(recursive: true);
      path = d.path;
    }
    return _dir = path;
  }

  // ----------------------------------------------------------------- add

  Future<DownloadItem> addUrl(String rawUrl) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw 'Enter a valid http/https link';
    }
    final dir = await downloadDir();
    final probe = await _probe(url);
    final name = _uniqueName(dir, probe.fileName ?? _nameFromUrl(uri));
    final item = DownloadItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: url,
      fileName: name,
      dirPath: dir,
      total: probe.total,
      rangeSupported: probe.range,
    );
    items.insert(0, item);
    await _save();
    notifyListeners();
    start(item);
    return item;
  }

  // ------------------------------------------------------------- control

  void start(DownloadItem item) {
    if (_runs.containsKey(item.id)) return;
    if (item.status == DlStatus.completed) return;
    item.status = DlStatus.downloading;
    item.error = null;
    final run = _Run();
    _runs[item.id] = run;
    notifyListeners();
    _execute(item, run);
  }

  void pause(DownloadItem item) {
    final run = _runs[item.id];
    item.status = DlStatus.paused;
    item.speed = 0;
    run?.token.cancel('paused');
    notifyListeners();
    _save();
  }

  Future<void> remove(DownloadItem item, {bool deleteFile = false}) async {
    final run = _runs[item.id];
    run?.token.cancel('removed');
    items.remove(item);
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 300));
    await _deleteParts(item);
    if (deleteFile) {
      try {
        final f = File(item.savePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _save();
  }

  // ------------------------------------------------------------- engine

  Future<void> _execute(DownloadItem item, _Run run) async {
    try {
      // Re-probe if metadata is unknown
      if (item.total <= 0) {
        final p = await _probe(item.url);
        item.total = p.total;
        item.rangeSupported = p.range;
      }

      run.ticker = _startTicker(item, run);

      if (item.rangeSupported && item.total > 0) {
        await _multiSegment(item, run);
      } else {
        await _singleStream(item, run);
      }

      run.ticker?.cancel();
      item.downloaded = item.total > 0 ? item.total : item.downloaded;
      item.status = DlStatus.completed;
      item.speed = 0;
    } on DioException catch (e) {
      run.ticker?.cancel();
      item.speed = 0;
      if (CancelToken.isCancel(e)) {
        // pause()/remove() already set the status
      } else {
        item.status = DlStatus.failed;
        item.error = _dioMessage(e);
      }
    } catch (e) {
      run.ticker?.cancel();
      item.speed = 0;
      if (run.token.isCancelled) {
        // fine
      } else {
        item.status = DlStatus.failed;
        item.error = e.toString();
      }
    } finally {
      _runs.remove(item.id);
      notifyListeners();
      await _save();
    }
  }

  Timer _startTicker(DownloadItem item, _Run run) {
    var last = item.downloaded;
    var lastTime = DateTime.now();
    var save = 0;
    return Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now();
      final dt = now.difference(lastTime).inMilliseconds / 1000.0;
      if (dt <= 0) return;
      final cur = item.downloaded;
      final inst = (cur - last) / dt;
      item.speed = item.speed == 0 ? inst : item.speed * 0.6 + inst * 0.4;
      last = cur;
      lastTime = now;
      notifyListeners();
      if (++save % 10 == 0) _save();
    });
  }

  Future<void> _multiSegment(DownloadItem item, _Run run) async {
    final total = item.total;
    final base = total ~/ kSegments;
    final starts = <int>[];
    final ends = <int>[];
    for (var i = 0; i < kSegments; i++) {
      starts.add(i * base);
      ends.add(i == kSegments - 1 ? total - 1 : (i + 1) * base - 1);
    }

    run.segBytes = List.filled(kSegments, 0);
    for (var i = 0; i < kSegments; i++) {
      final f = File(_partPath(item, i));
      if (await f.exists()) {
        var len = await f.length();
        final segLen = ends[i] - starts[i] + 1;
        if (len > segLen) {
          final raf = await f.open(mode: FileMode.append);
          await raf.truncate(segLen);
          await raf.close();
          len = segLen;
        }
        run.segBytes[i] = len;
      }
    }
    _syncDownloaded(item, run);

    await Future.wait([
      for (var i = 0; i < kSegments; i++)
        _downloadSegment(item, run, i, starts[i], ends[i]),
    ]);

    await _merge(item);
  }

  Future<void> _downloadSegment(
      DownloadItem item, _Run run, int index, int start, int end) async {
    final already = run.segBytes[index];
    final from = start + already;
    if (from > end) return; // this segment is already complete

    final resp = await _dio.get<ResponseBody>(
      item.url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=$from-$end'},
        receiveTimeout: const Duration(seconds: 60),
      ),
      cancelToken: run.token,
    );
    if (resp.statusCode != 206) {
      throw 'Server did not honour Range request (${resp.statusCode})';
    }

    final sink = File(_partPath(item, index)).openWrite(mode: FileMode.append);
    try {
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        run.segBytes[index] += chunk.length;
        _syncDownloaded(item, run);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  void _syncDownloaded(DownloadItem item, _Run run) {
    var sum = 0;
    for (final b in run.segBytes) {
      sum += b;
    }
    item.downloaded = sum;
  }

  Future<void> _singleStream(DownloadItem item, _Run run) async {
    final part = File(_partPath(item, 0));
    if (await part.exists()) await part.delete(); // cannot resume a single stream
    item.downloaded = 0;

    final resp = await _dio.get<ResponseBody>(
      item.url,
      options: Options(responseType: ResponseType.stream),
      cancelToken: run.token,
    );
    final sink = part.openWrite();
    try {
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        item.downloaded += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final out = File(item.savePath);
    if (await out.exists()) await out.delete();
    await part.rename(item.savePath);
  }

  Future<void> _merge(DownloadItem item) async {
    final out = File(item.savePath);
    if (await out.exists()) await out.delete();
    final sink = out.openWrite();
    try {
      for (var i = 0; i < kSegments; i++) {
        final p = File(_partPath(item, i));
        if (await p.exists()) {
          await sink.addStream(p.openRead());
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await _deleteParts(item);
  }

  Future<void> _deleteParts(DownloadItem item) async {
    for (var i = 0; i < kSegments; i++) {
      try {
        final f = File(_partPath(item, i));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  String _partPath(DownloadItem item, int i) =>
      '${item.dirPath}/.${item.fileName}.part$i';

  // ------------------------------------------------------------- helpers

  Future<({int total, bool range, String? fileName})> _probe(String url) async {
    final token = CancelToken();
    try {
      final resp = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=0-0'},
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: token,
      );
      final h = resp.headers;
      var total = -1;
      var range = false;
      if (resp.statusCode == 206) {
        range = true;
        final cr = h.value('content-range'); // bytes 0-0/12345
        final slash = cr?.lastIndexOf('/') ?? -1;
        if (cr != null && slash >= 0) {
          total = int.tryParse(cr.substring(slash + 1)) ?? -1;
        }
      } else {
        total = int.tryParse(h.value('content-length') ?? '') ?? -1;
      }
      final name = _nameFromDisposition(h.value('content-disposition'));
      token.cancel('probe done');
      return (total: total, range: range && total > 0, fileName: name);
    } on DioException catch (e) {
      throw _dioMessage(e);
    }
  }

  String? _nameFromDisposition(String? cd) {
    if (cd == null) return null;
    final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)",
            caseSensitive: false)
        .firstMatch(cd);
    if (star != null) {
      try {
        return _sanitize(Uri.decodeComponent(star.group(1)!.trim()));
      } catch (_) {}
    }
    final plain =
        RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false)
            .firstMatch(cd);
    if (plain != null) return _sanitize(plain.group(1)!.trim());
    return null;
  }

  String _nameFromUrl(Uri uri) {
    var n = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    try {
      n = Uri.decodeComponent(n);
    } catch (_) {}
    n = _sanitize(n);
    return n.isEmpty ? 'download_${DateTime.now().millisecondsSinceEpoch}' : n;
  }

  String _sanitize(String n) =>
      n.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();

  String _uniqueName(String dir, String name) {
    final taken = items.map((e) => e.fileName).toSet();
    bool exists(String n) => taken.contains(n) || File('$dir/$n').existsSync();
    if (!exists(name)) return name;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (exists('$stem ($i)$ext')) {
      i++;
    }
    return '$stem ($i)$ext';
  }

  String _dioMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection timed out';
      case DioExceptionType.connectionError:
        return 'No internet connection or server unreachable';
      case DioExceptionType.badResponse:
        return 'Server error (${e.response?.statusCode})';
      default:
        return e.message ?? 'Unknown error';
    }
  }
}
