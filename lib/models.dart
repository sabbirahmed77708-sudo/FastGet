enum DlStatus { queued, downloading, paused, completed, failed }

class DownloadItem {
  final String id;
  final String url;
  String fileName;
  String dirPath;
  int total; // -1 = অজানা
  int downloaded;
  bool rangeSupported;
  DlStatus status;
  String? error;

  // রানটাইম (সেভ হয় না)
  double speed = 0; // bytes/sec

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.dirPath,
    this.total = -1,
    this.downloaded = 0,
    this.rangeSupported = false,
    this.status = DlStatus.queued,
    this.error,
  });

  String get savePath => '$dirPath/$fileName';

  double get progress =>
      total > 0 ? (downloaded / total).clamp(0.0, 1.0).toDouble() : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'dirPath': dirPath,
        'total': total,
        'downloaded': downloaded,
        'rangeSupported': rangeSupported,
        'status': status.name,
        'error': error,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) {
    var st = DlStatus.values.firstWhere(
      (e) => e.name == j['status'],
      orElse: () => DlStatus.paused,
    );
    // অ্যাপ বন্ধ হওয়ার সময় যেটা চলছিল সেটা এখন পজড
    if (st == DlStatus.downloading || st == DlStatus.queued) {
      st = DlStatus.paused;
    }
    return DownloadItem(
      id: j['id'] as String,
      url: j['url'] as String,
      fileName: j['fileName'] as String,
      dirPath: j['dirPath'] as String,
      total: (j['total'] as num?)?.toInt() ?? -1,
      downloaded: (j['downloaded'] as num?)?.toInt() ?? 0,
      rangeSupported: j['rangeSupported'] as bool? ?? false,
      status: st,
      error: j['error'] as String?,
    );
  }
}

String formatBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  double v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${u[i]}';
}

String formatEta(DownloadItem d) {
  if (d.total <= 0 || d.speed <= 0) return '--';
  final s = ((d.total - d.downloaded) / d.speed).round();
  if (s < 60) return '$sসে';
  if (s < 3600) return '${s ~/ 60}মি ${s % 60}সে';
  return '${s ~/ 3600}ঘ ${(s % 3600) ~/ 60}মি';
}
