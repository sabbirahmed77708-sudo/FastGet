import 'package:flutter/material.dart';

import 'download_manager.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadManager.instance.init();
  runApp(const FastGetApp());
}

class FastGetApp extends StatelessWidget {
  const FastGetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FastGet',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
