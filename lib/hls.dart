/// Minimal HLS (.m3u8) playlist parsing: quality variants for the browser's
/// media list and the segment list for the downloader.

class HlsVariant {
  final Uri url;
  final int height;
  final int bandwidth;
  final bool separateAudio;
  const HlsVariant(this.url, this.height, this.bandwidth, this.separateAudio);
}

class HlsAudio {
  final Uri url;
  final String name;
  final int bandwidth;
  const HlsAudio(this.url, this.name, this.bandwidth);
}

class HlsMaster {
  final List<HlsVariant> variants;
  final List<HlsAudio> audios;
  const HlsMaster(this.variants, this.audios);
}

class HlsMedia {
  final List<Uri> segments;
  final Uri? init; // EXT-X-MAP (fMP4)
  final bool encrypted;
  final bool live;
  final double seconds;
  const HlsMedia(
      this.segments, this.init, this.encrypted, this.live, this.seconds);
}

bool isMasterPlaylist(String text) => text.contains('#EXT-X-STREAM-INF');

Map<String, String> _attrs(String line) {
  final i = line.indexOf(':');
  final s = i >= 0 ? line.substring(i + 1) : line;
  final out = <String, String>{};
  for (final m in RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)').allMatches(s)) {
    var v = m.group(2) ?? '';
    if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
      v = v.substring(1, v.length - 1);
    }
    out[m.group(1)!] = v;
  }
  return out;
}

HlsMaster parseMaster(String text, Uri base) {
  final lines = text.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();
  final variants = <HlsVariant>[];
  final audios = <HlsAudio>[];
  final audioGroups = <String>{};
  for (final l in lines) {
    if (l.startsWith('#EXT-X-MEDIA:')) {
      final a = _attrs(l);
      if (a['TYPE'] == 'AUDIO' && (a['URI'] ?? '').isNotEmpty) {
        audioGroups.add(a['GROUP-ID'] ?? '');
        audios.add(HlsAudio(base.resolve(a['URI']!),
            a['NAME'] ?? a['LANGUAGE'] ?? 'Audio', 0));
      }
    }
  }
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF:')) continue;
    final a = _attrs(lines[i]);
    var j = i + 1;
    while (j < lines.length && (lines[j].isEmpty || lines[j].startsWith('#'))) {
      j++;
    }
    if (j >= lines.length) break;
    final res = a['RESOLUTION'] ?? '';
    final h = int.tryParse(res.contains('x') ? res.split('x').last : '') ?? 0;
    final bw = int.tryParse(a['AVERAGE-BANDWIDTH'] ?? a['BANDWIDTH'] ?? '') ?? 0;
    final sep = (a['AUDIO'] != null) && audioGroups.contains(a['AUDIO']);
    variants.add(HlsVariant(base.resolve(lines[j]), h, bw, sep));
  }
  variants.sort((a, b) {
    final c = b.height.compareTo(a.height);
    return c != 0 ? c : b.bandwidth.compareTo(a.bandwidth);
  });
  return HlsMaster(variants, audios);
}

HlsMedia parseMedia(String text, Uri base) {
  final segs = <Uri>[];
  Uri? init;
  var enc = false;
  var ended = false;
  var secs = 0.0;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#')) {
      if (l.startsWith('#EXT-X-KEY:')) {
        final m = _attrs(l)['METHOD'] ?? 'NONE';
        if (m != 'NONE') enc = true;
      } else if (l.startsWith('#EXT-X-MAP:')) {
        final u = _attrs(l)['URI'];
        if (u != null && u.isNotEmpty) init = base.resolve(u);
      } else if (l.startsWith('#EXT-X-ENDLIST')) {
        ended = true;
      } else if (l.startsWith('#EXTINF:')) {
        secs += double.tryParse(
                l.substring(8).split(',').first.trim()) ??
            0;
      }
      continue;
    }
    segs.add(base.resolve(l));
  }
  return HlsMedia(segs, init, enc, !ended, secs);
}
