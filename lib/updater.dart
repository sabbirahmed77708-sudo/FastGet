import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// GitHub repository that publishes DROM builds as Releases.
const String kRepo = 'sabbirahmed77708-sudo/FastGet';

class UpdateInfo {
  final int build;
  final String name;
  final String notes;
  final String apkUrl;
  final int size;
  const UpdateInfo({
    required this.build,
    required this.name,
    required this.notes,
    required this.apkUrl,
    required this.size,
  });
}

enum UpdatePhase { idle, downloading, ready, error }

/// Looks for a newer DROM build in the GitHub Releases of [kRepo].
///
/// The CI publishes every build as a release tagged `build-<number>`; the app
/// compares that number with its own build number.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  bool checking = false;
  bool checkedOnce = false; // a check finished without a network error
  String? error;
  UpdateInfo? available;

  String version = '';
  int build = 0;

  bool get hasUpdate => available != null;

  // ---- in-app update: download, then open the installer
  UpdatePhase phase = UpdatePhase.idle;
  int received = 0;
  int totalBytes = 0;
  String? updateError;
  String? _apkPath;
  CancelToken? _token;

  /// Build number the "update available" pop-up was already shown for.
  int promptedBuild = 0;

  double get progress =>
      totalBytes > 0 ? (received / totalBytes).clamp(0.0, 1.0).toDouble() : 0;

  /// Downloads the new APK inside DROM and opens the installer when done.
  Future<void> startUpdate() async {
    final info = available;
    if (info == null || phase == UpdatePhase.downloading) return;
    phase = UpdatePhase.downloading;
    received = 0;
    totalBytes = info.size;
    updateError = null;
    notifyListeners();
    final token = _token = CancelToken();
    try {
      final dir = await getTemporaryDirectory();
      // old update files are not needed any more
      for (final f in dir.listSync()) {
        if (f is File && f.path.contains('DROM-update-')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      final path = '${dir.path}/DROM-update-${info.build}.apk';
      final tmp = '$path.part';
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        followRedirects: true,
        maxRedirects: 8,
        headers: {'User-Agent': 'DROM-app'},
      ));
      var tick = DateTime.now();
      await dio.download(
        info.apkUrl,
        tmp,
        cancelToken: token,
        onReceiveProgress: (r, t) {
          received = r;
          if (t > 0) totalBytes = t;
          final now = DateTime.now();
          if (now.difference(tick).inMilliseconds > 150) {
            tick = now;
            notifyListeners();
          }
        },
      );
      final f = File(tmp);
      if (info.size > 0 && await f.length() != info.size) {
        await f.delete();
        throw 'Update download incomplete';
      }
      await f.rename(path);
      _apkPath = path;
      phase = UpdatePhase.ready;
      notifyListeners();
      await install();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        phase = UpdatePhase.idle;
      } else {
        phase = UpdatePhase.error;
        updateError = 'Update download failed. Check your internet and try again.';
      }
      notifyListeners();
    } catch (e) {
      phase = UpdatePhase.error;
      updateError = e.toString();
      notifyListeners();
    }
  }

  void cancelUpdate() {
    _token?.cancel('cancelled');
  }

  /// Opens Android's installer for the downloaded APK.
  Future<void> install() async {
    final path = _apkPath;
    if (path == null || !File(path).existsSync()) {
      phase = UpdatePhase.idle;
      notifyListeners();
      return;
    }
    try {
      if (!await Permission.requestInstallPackages.isGranted) {
        // opens "Install unknown apps" for DROM, once
        await Permission.requestInstallPackages.request();
      }
      final r = await OpenFilex.open(path,
          type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        phase = UpdatePhase.error;
        updateError = 'Could not open the installer. Allow "Install unknown apps" for DROM.';
        notifyListeners();
      }
    } catch (_) {
      phase = UpdatePhase.error;
      updateError = 'Could not open the installer.';
      notifyListeners();
    }
  }

  Future<void> loadVersion() async {
    if (version.isNotEmpty) return;
    try {
      final p = await PackageInfo.fromPlatform();
      version = p.version;
      build = int.tryParse(p.buildNumber) ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> check({bool silent = false}) async {
    if (checking) return;
    checking = true;
    if (!silent) error = null;
    notifyListeners();
    try {
      await loadVersion();
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'DROM-app',
        },
        validateStatus: (s) => s != null && (s < 400 || s == 404),
      ));
      final r = await dio.get<dynamic>(
          'https://api.github.com/repos/$kRepo/releases/latest');
      if (r.statusCode == 404 || r.data is! Map) {
        // no release published yet: nothing newer exists
        available = null;
        checkedOnce = true;
        error = null;
        return;
      }
      final data = Map<String, dynamic>.from(r.data as Map);
      final tag = (data['tag_name'] ?? '').toString();
      final m = RegExp(r'(\d+)\s*$').firstMatch(tag);
      final remote = m != null ? int.parse(m.group(1)!) : 0;

      String? apk;
      var size = 0;
      for (final a in (data['assets'] as List? ?? const [])) {
        final am = Map<String, dynamic>.from(a as Map);
        final n = (am['name'] ?? '').toString().toLowerCase();
        if (n.endsWith('.apk')) {
          apk = am['browser_download_url']?.toString();
          size = (am['size'] as num?)?.toInt() ?? 0;
          break;
        }
      }

      if (remote > build && apk != null) {
        available = UpdateInfo(
          build: remote,
          name: (data['name'] ?? tag).toString(),
          notes: (data['body'] ?? '').toString().trim(),
          apkUrl: apk,
          size: size,
        );
      } else {
        available = null;
      }
      checkedOnce = true;
      error = null;
    } on DioException {
      error = 'Could not check for updates';
    } catch (_) {
      error = 'Could not check for updates';
    } finally {
      checking = false;
      notifyListeners();
    }
  }
}
