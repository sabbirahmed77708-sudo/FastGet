import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the download notifications show and how they behave.
/// Saved on the phone; [DownloadNotifier] reads these on every update.
class NotifySettings extends ChangeNotifier {
  NotifySettings._();
  static final NotifySettings instance = NotifySettings._();

  /// Show percent / size / speed in the progress notification (off: a plain
  /// "Downloading" line; Android still needs one notification while the
  /// background service runs).
  bool progressDetails = true;

  /// A separate notification for every download (off: one combined one).
  bool perDownload = true;
  bool showSpeed = true;
  bool showEta = true;
  bool showButtons = true;

  bool notifyComplete = true;
  bool notifyFailed = true;
  bool sound = true;
  bool vibrate = true;
  bool popup = true;

  /// Show notification content on the lock screen.
  bool lockScreen = true;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    progressDetails = p.getBool('n_details') ?? true;
    perDownload = p.getBool('n_per') ?? true;
    showSpeed = p.getBool('n_speed') ?? true;
    showEta = p.getBool('n_eta') ?? true;
    showButtons = p.getBool('n_buttons') ?? true;
    notifyComplete = p.getBool('n_complete') ?? true;
    notifyFailed = p.getBool('n_failed') ?? true;
    sound = p.getBool('n_sound') ?? true;
    vibrate = p.getBool('n_vibrate') ?? true;
    popup = p.getBool('n_popup') ?? true;
    lockScreen = p.getBool('n_lock') ?? true;
  }

  Future<void> _set(String key, bool v) async {
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, v);
    } catch (_) {}
  }

  void setProgressDetails(bool v) {
    progressDetails = v;
    _set('n_details', v);
  }

  void setPerDownload(bool v) {
    perDownload = v;
    _set('n_per', v);
  }

  void setShowSpeed(bool v) {
    showSpeed = v;
    _set('n_speed', v);
  }

  void setShowEta(bool v) {
    showEta = v;
    _set('n_eta', v);
  }

  void setShowButtons(bool v) {
    showButtons = v;
    _set('n_buttons', v);
  }

  void setNotifyComplete(bool v) {
    notifyComplete = v;
    _set('n_complete', v);
  }

  void setNotifyFailed(bool v) {
    notifyFailed = v;
    _set('n_failed', v);
  }

  void setSound(bool v) {
    sound = v;
    _set('n_sound', v);
  }

  void setVibrate(bool v) {
    vibrate = v;
    _set('n_vibrate', v);
  }

  void setPopup(bool v) {
    popup = v;
    _set('n_popup', v);
  }

  void setLockScreen(bool v) {
    lockScreen = v;
    _set('n_lock', v);
  }

  void reset() {
    progressDetails = perDownload = showSpeed = showEta = showButtons = true;
    notifyComplete = notifyFailed = sound = vibrate = popup = lockScreen = true;
    notifyListeners();
    SharedPreferences.getInstance().then((p) async {
      for (final k in const [
        'n_details', 'n_per', 'n_speed', 'n_eta', 'n_buttons', 'n_complete',
        'n_failed', 'n_sound', 'n_vibrate', 'n_popup', 'n_lock',
      ]) {
        await p.remove(k);
      }
    });
  }
}
