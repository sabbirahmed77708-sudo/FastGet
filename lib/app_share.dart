import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'l10n.dart';
import 'updater.dart';

const MethodChannel _appChannel = MethodChannel('drom/app');

/// Shares the installed SDM app (the APK file itself) with anyone, through
/// WhatsApp, Bluetooth, Messenger or any other app on the phone.
Future<void> shareApp() async {
  final text = tr('Get SDM - a fast download manager with a built-in browser.');
  try {
    final src = await _appChannel.invokeMethod<String>('apkPath');
    if (src != null && src.isNotEmpty) {
      final dir = await getTemporaryDirectory();
      final copy = await File(src).copy('${dir.path}/SDM.apk');
      await Share.shareXFiles(
        [
          XFile(copy.path,
              mimeType: 'application/vnd.android.package-archive',
              name: 'SDM.apk'),
        ],
        text: text,
        subject: 'SDM',
      );
      return;
    }
  } catch (_) {
    // fall back to sharing a link
  }
  await Share.share('$text https://github.com/$kRepo/releases/latest');
}
