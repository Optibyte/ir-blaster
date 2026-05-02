import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'package:esp/core/theme/app_theme.dart';
import 'package:esp/core/theme/theme_provider.dart';
import 'package:esp/core/constants/colors.dart';
import 'package:esp/core/services/auth_service.dart' as ac_auth;
import 'package:esp/screens/ac_app/sigin.dart';
import 'package:esp/screens/main_navigation_page.dart';
import 'package:esp/screens/ac_app/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('⚠️ Firebase Init Error: $e');
  }

  // Initialize Dotenv
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('⚠️ Error loading .env: $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Optibyte - IR Blaster',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late Future<Map<String, dynamic>?> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = _checkAuth();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ACSplashScreen();
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Connection Error',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please check your internet connection',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _authFuture = _checkAuth();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.button),
                    child: Text('Retry',
                        style: GoogleFonts.poppins(color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        }

        // Authenticated
        if (snapshot.data != null) {
          return const MainNavigationPage();
        }

        // Not authenticated
        return const SignInPage();
      },
    );
  }

  Future<Map<String, dynamic>?> _checkAuth() async {
    final startTime = DateTime.now();

    Map<String, dynamic>? result;
    final cachedUser = await ac_auth.AuthService.getUserData();
    if (cachedUser != null) {
      // ignore: unawaited_futures
      ac_auth.AuthService.verify();
      result = cachedUser;
    } else if (await ac_auth.AuthService.hasStoredSession()) {
      result = await ac_auth.AuthService.verify();
    }

    // Ensure splash screen is visible for at least 2.5 seconds
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    if (elapsed < 2500) {
      await Future.delayed(Duration(milliseconds: 2500 - elapsed));
    }

    return result;
  }
}
