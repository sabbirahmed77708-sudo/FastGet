import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
