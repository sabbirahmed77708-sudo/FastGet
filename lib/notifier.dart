import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'download_manager.dart';
import 'l10n.dart';
import 'models.dart';
import 'notify_settings.dart';

/// Talks to the Android foreground service ([DownloadService.kt]).
///
/// Every running download gets its own notification with percent, MB, speed and
/// its own Pause / Resume button. With several downloads a summary notification
/// (Pause all / Resume all) groups them. The service also keeps the process
/// alive, so downloads continue when the app is in the background or closed.
class DownloadNotifier {
  DownloadNotifier._();
  static final DownloadNotifier instance = DownloadNotifier._();

  static const MethodChannel _ch = MethodChannel('drom/notify');
  final DownloadManager _dm = DownloadManager.instance;

  bool _serviceOn = false;
  bool _askedPermission = false;

  /// Downloads paused with a notification button. Their notification stays so
  /// that Resume is still there.
  final Set<String> _held = {};

  bool _cooldown = false;
  bool _pending = false;
  final Map<String, DlStatus> _last = {};

  void start() {
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'onAction') return;
      _handleAction(call.arguments as String? ?? '');
      _pending = false;
      _cooldown = false;
      _onChange();
    });
    for (final it in _dm.items) {
      _last[it.id] = it.status;
    }
    _dm.addListener(_onChange);
    NotifySettings.instance.addListener(() {
      _pending = false;
      _cooldown = false;
      _onChange();
    });
  }

  DownloadItem? _find(String id) {
    for (final it in _dm.items) {
      if (it.id == id) return it;
    }
    return null;
  }

  void _handleAction(String a) {
    if (a == 'pauseAll') {
      for (final it in _dm.items) {
        if (it.status == DlStatus.downloading) _held.add(it.id);
      }
      _dm.pauseAll();
    } else if (a == 'resumeAll') {
      final ids = _held.toList();
      _held.clear();
      for (final id in ids) {
        final it = _find(id);
        if (it != null && it.status == DlStatus.paused) _dm.start(it);
      }
    } else if (a.startsWith('pause:')) {
      final it = _find(a.substring(6));
      if (it != null && it.status == DlStatus.downloading) {
        _held.add(it.id);
        _dm.pause(it);
      }
    } else if (a.startsWith('resume:')) {
      final id = a.substring(7);
      _held.remove(id);
      final it = _find(id);
      if (it != null && it.status == DlStatus.paused) _dm.start(it);
    }
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

    // forget held downloads that are no longer paused
    _held.removeWhere((id) {
      final it = _find(id);
      return it == null || it.status != DlStatus.paused;
    });

    final active =
        items.where((e) => e.status == DlStatus.downloading).toList();
    final waiting = items
        .where((e) => e.status == DlStatus.paused && _dm.isWaitingForWifi(e))
        .toList();
    final held = items
        .where((e) =>
            e.status == DlStatus.paused &&
            _held.contains(e.id) &&
            !waiting.contains(e))
        .toList();

    final list = [...active, ...waiting, ...held];
    if (list.isEmpty) {
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

    final payload = _payload(list, active.isEmpty);
    final ok = await _ch.invokeMethod<bool>('update', payload);
    _serviceOn = ok ?? false;
  }

  int _progressId(DownloadItem it) => 20000000 + (it.id.hashCode & 0xffffff);
  int _doneId(DownloadItem it) => 10000 + (it.id.hashCode & 0xffffff);

  String _sizeOf(DownloadItem it) => it.total > 0
      ? '${formatBytes(it.downloaded)} / ${formatBytes(it.total)}'
      : formatBytes(it.downloaded);

  String _pctOf(DownloadItem it) =>
      it.total > 0 ? '${(it.progress * 100).floor()}% · ' : '';

  NotifySettings get _ns => NotifySettings.instance;
  int get _visibility => _ns.lockScreen ? 1 : 0; // PUBLIC : PRIVATE

  String _etaOf(DownloadItem it) {
    if (!_ns.showEta || it.speed <= 0 || it.total <= 0) return '';
    return ' · ${formatEta(it)} ${tr('left')}';
  }

  Map<String, dynamic> _itemMap(DownloadItem it) {
    final running = it.status == DlStatus.downloading;
    final waiting = !running && _dm.isWaitingForWifi(it);
    final state = waiting ? tr('Waiting for Wi-Fi') : tr('Paused');
    final details = _ns.progressDetails;
    final String status;
    if (running) {
      status = details
          ? '${_ns.showSpeed ? '${formatBytes(it.speed)}/s' : tr('Downloading')}${_etaOf(it)}'
          : tr('Downloading');
    } else {
      status = state;
    }
    final pct = it.total > 0 ? (it.progress * 100).floor() : null;
    return {
      'key': it.id,
      'nid': _progressId(it),
      'title': it.fileName,
      'text': details ? '${_pctOf(it)}${_sizeOf(it)} · $status' : status,
      'progress': pct ?? 0,
      'max': 100,
      'indeterminate': pct == null && running,
      'paused': !running,
      'actionLabel': running ? tr('Pause') : tr('Resume'),
      'showButtons': _ns.showButtons,
      'showProgress': details,
      'visibility': _visibility,
    };
  }

  Map<String, dynamic> _payload(List<DownloadItem> list, bool allPaused) {
    final items = [for (final it in list) _itemMap(it)];

    // one download: the main notification IS that download
    if (list.length == 1 && _ns.perDownload) {
      return {
        ...items.first,
        'actionKey': list.first.id,
        'items': items,
      };
    }

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
    final pct = totalKnown > 0 ? (doneKnown * 100 / totalKnown).floor() : null;
    final size = totalKnown > 0 && !unknownTotal
        ? '${formatBytes(doneKnown)} / ${formatBytes(totalKnown)}'
        : formatBytes(doneAll);
    final details = _ns.progressDetails;
    final status = allPaused
        ? tr('Paused')
        : (details && _ns.showSpeed
            ? '${formatBytes(speed)}/s'
            : tr('Downloading'));

    return {
      'title': bn ? '${list.length} টি ডাউনলোড' : '${list.length} downloads',
      'text': details
          ? '${pct != null ? '$pct% · ' : ''}$size · $status'
          : status,
      'progress': pct ?? 0,
      'max': 100,
      'indeterminate': pct == null && !allPaused,
      'paused': allPaused,
      'actionLabel': allPaused ? tr('Resume all') : tr('Pause all'),
      'showButtons': _ns.showButtons,
      'showProgress': details,
      'visibility': _visibility,
      // separate notifications only when the user wants them
      'items': _ns.perDownload ? items : <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _doneMap(DownloadItem it, bool failed) => {
        'id': _doneId(it),
        'title': failed ? tr('Download failed') : tr('Download complete'),
        'text': failed
            ? '${it.fileName} · ${tr(it.error ?? 'Failed')}'
            : it.fileName,
        'failed': failed,
        'sound': _ns.sound,
        'vibrate': _ns.vibrate,
        'popup': _ns.popup,
        'visibility': _visibility,
        if (!failed) 'openKey': it.id,
      };

  void _done(DownloadItem it, {required bool failed}) {
    if (failed ? !_ns.notifyFailed : !_ns.notifyComplete) return;
    _ch.invokeMethod('done', _doneMap(it, failed)).catchError((_) {});
  }

  // ---- used by the notification settings screen

  Future<bool> permissionGranted() async {
    try {
      return await _ch.invokeMethod<bool>('enabled') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openSystemSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<void> sendTest() async {
    try {
      var granted = await permissionGranted();
      if (!granted) {
        await Permission.notification.request();
        granted = await permissionGranted();
      }
      if (!granted) return;
      await _ch.invokeMethod('done', {
        'id': 9999,
        'title': tr('Download complete'),
        'text': tr('This is a test notification'),
        'failed': false,
        'sound': _ns.sound,
        'vibrate': _ns.vibrate,
        'popup': _ns.popup,
        'visibility': _visibility,
      });
    } catch (_) {}
  }
}
