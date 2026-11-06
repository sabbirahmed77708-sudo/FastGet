// Used by CI: rebuilds the new APK from the old one + a patch with the SAME
// Dart code the app uses, and checks the SHA-256.
//   dart run tool/verify_patch.dart OLD_FILE PATCH_FILE EXPECTED_SHA256
import 'dart:io';

import 'package:fastget/patcher.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('usage: verify_patch OLD PATCH SHA256');
    exit(2);
  }
  final out = '${args[1]}.rebuilt';
  final sw = Stopwatch()..start();
  try {
    final got = await applyDromPatch(args[0], args[1], out);
    stdout.writeln('rebuilt in ${sw.elapsedMilliseconds} ms, sha256 $got');
    if (got != args[2].trim().toLowerCase()) {
      stderr.writeln('SHA-256 MISMATCH, expected ${args[2]}');
      exit(1);
    }
    stdout.writeln('patch OK');
  } finally {
    final f = File(out);
    if (f.existsSync()) f.deleteSync();
  }
}
