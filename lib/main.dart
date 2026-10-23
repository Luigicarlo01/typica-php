import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/pwa_platform.dart';
import 'utils/app_colors.dart';

/// Entrypoint. Sobe a arvore imediatamente; o boot pesado roda na SplashScreen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PwaPlatform.initialize();
  runApp(const MyApp());
}

/// Widget raiz. Define o tema global do app.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Typica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: AppColors.green,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.green,
          selectionColor: Color(0x3302890A),
          selectionHandleColor: AppColors.green,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.green, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          floatingLabelStyle: TextStyle(color: Colors.green),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
