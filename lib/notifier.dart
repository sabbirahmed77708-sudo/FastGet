import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'download_manager.dart';
import 'l10n.dart';
import 'models.dart';

/// Talks to the Android foreground service ([DownloadService.kt]).
///
/// While something is downloading it keeps one notification up to date with
/// percent, MB and speed, with a Pause all / Resume all button. The service
/// also keeps the process alive, so downloads continue when the app is in the
/// background or has been closed.
class DownloadNotifier {
  DownloadNotifier._();
  static final DownloadNotifier instance = DownloadNotifier._();

  static const MethodChannel _ch = MethodChannel('drom/notify');
  final DownloadManager _dm = DownloadManager.instance;

  bool _serviceOn = false;
  bool _askedPermission = false;

  /// Paused with the notification button: keep the notification so that
  /// "Resume all" stays available.
  bool _hold = false;

  bool _cooldown = false;
  bool _pending = false;
  final Map<String, DlStatus> _last = {};

  void start() {
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'onAction') return;
      final a = call.arguments as String?;
      if (a == 'pauseAll') {
        _hold = true;
        _dm.pauseAll();
      } else if (a == 'resumeAll') {
        _hold = false;
        _dm.resumeAll();
      }
      _pending = false;
      _cooldown = false;
      _onChange();
    });
    for (final it in _dm.items) {
      _last[it.id] = it.status;
    }
    _dm.addListener(_onChange);
  }

  // Update right away, then at most about once a second.
  void _onChange() {
    if (_cooldown) {
      _pending = true;
      return;
    }
    _cooldown = true;
    _pending = false;
    _push();
    Timer(const Duration(milliseconds: 900), () {
      _cooldown = false;
      if (_pending) _onChange();
    });
  }

  Future<void> _push() async {
    try {
      await _pushInner();
    } on MissingPluginException {
      // not running on Android
    } catch (_) {}
  }

  Future<void> _pushInner() async {
    final items = _dm.items;

    // finished / failed downloads get their own notification
    for (final it in items.toList()) {
      final prev = _last[it.id] ?? DlStatus.queued;
      if (prev != it.status) {
        if (it.status == DlStatus.completed) {
          _done(it, failed: false);
        } else if (it.status == DlStatus.failed) {
          _done(it, failed: true);
        }
      }
      _last[it.id] = it.status;
    }
    final ids = items.map((e) => e.id).toSet();
    _last.removeWhere((k, _) => !ids.contains(k));

    final active =
        items.where((e) => e.status == DlStatus.downloading).toList();
    final waiting = items
        .where((e) => e.status == DlStatus.paused && _dm.isWaitingForWifi(e))
        .toList();
    final paused = items.where((e) => e.status == DlStatus.paused).toList();

    final showActive = active.isNotEmpty;
    if (showActive) _hold = false;
    if (_hold && paused.isEmpty) _hold = false;
    final showPaused = !showActive && (waiting.isNotEmpty || _hold);

    if (!showActive && !showPaused) {
      if (_serviceOn) {
        _serviceOn = false;
        await _ch.invokeMethod('stop');
      }
      return;
    }

    if (!_askedPermission) {
      _askedPermission = true;
      try {
        await Permission.notification.request();
      } catch (_) {}
    }

    final list = showActive ? active : (waiting.isNotEmpty ? waiting : paused);
    final payload = _payload(list, paused: !showActive, waiting: waiting.isNotEmpty);
    final ok = await _ch.invokeMethod<bool>('update', payload);
    _serviceOn = ok ?? false;
  }

  Map<String, dynamic> _payload(List<DownloadItem> list,
      {required bool paused, required bool waiting}) {
    final bn = L10n.instance.isBn;
    var doneKnown = 0;
    var totalKnown = 0;
    var doneAll = 0;
    var speed = 0.0;
    var unknownTotal = false;
    for (final it in list) {
      doneAll += it.downloaded;
      speed += it.speed;
      if (it.total > 0) {
        doneKnown += it.downloaded;
        totalKnown += it.total;
      } else {
        unknownTotal = true;
      }
    }

    String sizeOf(DownloadItem it) => it.total > 0
        ? '${formatBytes(it.downloaded)} / ${formatBytes(it.total)}'
        : formatBytes(it.downloaded);
    String pctOf(DownloadItem it) =>
        it.total > 0 ? '${(it.progress * 100).floor()}% · ' : '';

    final overallPct =
        totalKnown > 0 ? (doneKnown * 100 / totalKnown).floor() : null;
    final overallSize = totalKnown > 0 && !unknownTotal
        ? '${formatBytes(doneKnown)} / ${formatBytes(totalKnown)}'
        : formatBytes(doneAll);

    final status = paused
        ? (waiting ? tr('Waiting for Wi-Fi') : tr('Paused'))
        : '${formatBytes(speed)}/s';

    final String title;
    final String text;
    if (list.length == 1) {
      final it = list.first;
      title = it.fileName;
      text = '${pctOf(it)}${sizeOf(it)} · $status';
    } else {
      title = bn ? '${list.length} টি ডাউনলোড' : '${list.length} downloads';
      text =
          '${overallPct != null ? '$overallPct% · ' : ''}$overallSize · $status';
    }

    final lines = <String>[];
    if (list.length > 1) {
      for (final it in list.take(5)) {
        lines.add('${it.fileName} — ${pctOf(it)}${sizeOf(it)}');
      }
      if (list.length > 5) {
        final more = list.length - 5;
        lines.add(bn ? '+ আরও $more টি' : '+ $more more');
      }
    }

    return {
      'title': title,
      'text': text,
      'lines': lines,
      'progress': overallPct ?? 0,
      'max': 100,
      'indeterminate': overallPct == null && !paused,
      'paused': paused,
      'actionLabel': paused ? tr('Resume all') : tr('Pause all'),
    };
  }

  void _done(DownloadItem it, {required bool failed}) {
    final id = 10000 + (it.id.hashCode & 0xffffff);
    final text = failed ? '${it.fileName} · ${tr(it.error ?? 'Failed')}' : it.fileName;
    _ch.invokeMethod('done', {
      'id': id,
      'title': failed ? tr('Download failed') : tr('Download complete'),
      'text': text,
      'failed': failed,
    }).catchError((_) {});
  }
}
