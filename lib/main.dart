import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FiscalizadoresApp());
}

class FiscalizadoresApp extends StatelessWidget {
  const FiscalizadoresApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fiscalizadores SAT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: AppColors.azulModerno,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.azulModerno,
          primary: AppColors.azulModerno,
        ),
        scaffoldBackgroundColor: AppColors.grisClaro,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.azulModerno,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
