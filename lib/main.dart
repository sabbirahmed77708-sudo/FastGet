import 'package:flutter/material.dart';

import 'browser/browser_controller.dart';
import 'download_manager.dart';
import 'link_intake.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadManager.instance.init();
  await BrowserController.instance.init();
  runApp(const FastGetApp());
  LinkIntake.instance.start();
}

class FastGetApp extends StatelessWidget {
  const FastGetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BrowserController.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: rootNavigatorKey,
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
