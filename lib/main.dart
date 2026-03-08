import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_colors.dart';
import 'features/shell/presentation/shell_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AristokratApp()));
}

class AristokratApp extends StatelessWidget {
  const AristokratApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Aristokrat Mebel',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: AppColors.primary,
          scaffoldBackgroundColor: AppColors.background,
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            centerTitle: true,
            elevation: 0,
          ),
          // BU YERDA XATO BOR EDI: BottomAppBarThemeData bo'lishi kerak
          bottomAppBarTheme: const BottomAppBarThemeData(
            color: AppColors.bottomNavBg,
            elevation: 10,
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            secondary: AppColors.accent,
          ),
          useMaterial3: true,
        ),
        home: const ShellPage(),
      ),
    );
  }
}
