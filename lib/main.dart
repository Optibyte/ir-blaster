import 'package:flutter/material.dart';
import 'package:esp/screens/login_page.dart';
import 'package:esp/screens/mode_selection_page.dart';
import 'package:esp/auth/auth_service.dart';

void main() {
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> getInitialScreen() async {
    final AuthService authService = AuthService();
    final isLoggedIn = await authService.isLoggedIn();

    if (isLoggedIn) {
      debugPrint('✅ User already logged in. Going to Mode Selection.');
      return const ModeSelectionPage();
    } else {
      debugPrint('⚠️ User not logged in. Going to Login.');
      return LoginPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IR-Blaster App',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: const Color(0xFFF0F8FF),
      ),
      home: FutureBuilder<Widget>(
        future: getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else {
            return snapshot.data ?? LoginPage();
          }
        },
      ),
      routes: {
        '/login': (context) => LoginPage(),
        //'/register': (context) => RegisterPage(),
        '/mode_selection': (context) => const ModeSelectionPage(),
        // '/home': (context) => const HomePage(),
      },
    );
  }
}
