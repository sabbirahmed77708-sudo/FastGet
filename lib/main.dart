import 'package:flutter/material.dart';

import 'browser/browser_controller.dart';
import 'download_manager.dart';
import 'l10n.dart';
import 'link_intake.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadManager.instance.init();
  await L10n.instance.init();
  await BrowserController.instance.init();
  runApp(const FastGetApp());
  LinkIntake.instance.start();
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
        title: 'DROX',
        debugShowCheckedModeBanner: false,
        themeMode: BrowserController.instance.themeMode,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}
