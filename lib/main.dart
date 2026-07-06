import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/services/history_service.dart';
import 'core/services/open_intent.dart';
import 'core/services/share_intake.dart';
import 'features/home/home_screen.dart';
import 'features/share/share_intake_screen.dart';
import 'features/viewer/viewer_screen.dart';
import 'ui/motion.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HistoryService.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(const FileMillApp());
}

class FileMillApp extends StatefulWidget {
  const FileMillApp({super.key});

  @override
  State<FileMillApp> createState() => _FileMillAppState();
}

class _FileMillAppState extends State<FileMillApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    ShareIntake.init((files) {
      _navigatorKey.currentState?.push(
        Motion.fadeThrough(ShareIntakeScreen(shared: files)),
      );
    });
    OpenIntent.init((path, name) {
      _navigatorKey.currentState?.push(
        Motion.fadeThrough(ViewerScreen(path: path, name: name)),
      );
    });
  }

  @override
  void dispose() {
    ShareIntake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FileMill',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
