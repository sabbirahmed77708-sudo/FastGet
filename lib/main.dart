import 'package:flutter/material.dart';

import 'download_manager.dart';
import 'screens/home_screen.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E88E5),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E88E5),
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}
