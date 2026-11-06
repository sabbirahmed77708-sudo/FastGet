import 'package:flutter/material.dart';

import 'browser/browser_controller.dart';
import 'download_manager.dart';
import 'l10n.dart';
import 'link_intake.dart';
import 'notifier.dart';
import 'notify_settings.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadManager.instance.init();
  await L10n.instance.init();
  await BrowserController.instance.init();
  await NotifySettings.instance.init();
  DownloadNotifier.instance.start();
  runApp(const FastGetApp());
  LinkIntake.instance.start();
  // quiet check; a new version shows up in the menu and in About
  UpdateChecker.instance.check(silent: true);
}

class FastGetApp extends StatelessWidget {
  const FastGetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([BrowserController.instance, L10n.instance]),
      builder: (context, _) => MaterialApp(
        navigatorKey: rootNavigatorKey,
        // Rebuild every screen when the language changes.
        builder: (context, child) => KeyedSubtree(
          key: ValueKey(L10n.instance.code),
          child: child ?? const SizedBox.shrink(),
        ),
        title: 'SDM',
        debugShowCheckedModeBanner: false,
        themeMode: BrowserController.instance.themeMode,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}
