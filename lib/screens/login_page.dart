import 'package:flutter/material.dart';
import 'package:esp/screens/mode_selection_page.dart';

class LoginPage extends StatelessWidget {
  LoginPage({super.key});

  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // HARD-CODED CREDENTIALS
  final String allowedUser = "ir@gmail.com";
  final String allowedPass = "1234";

  void _handleLogin(BuildContext context) {
    final String user = usernameController.text.trim();
    final String pass = passwordController.text.trim();

    if (user == allowedUser && pass == allowedPass) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ModeSelectionPage()),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Login Failed"),
          content: const Text("Incorrect username or password!"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // default resizeToAvoidBottomInset is true – needed for keyboard
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // This makes space when keyboard opens
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // ---------- TOP GREEN HEADER ----------
                      SizedBox(
                        height: 230,
                        child: Stack(
                          children: [
                            // Dark green main shape
                            Container(
                              height: 230,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2E7D32), // dark green
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(80),
                                ),
                              ),
                            ),

                            // Light green corner
                            Positioned(
                              top: 0,
                              left: 0,
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFC8E6C9), // light green
                                  borderRadius: BorderRadius.only(
                                    bottomRight: Radius.circular(80),
                                  ),
                                ),
                              ),
                            ),

                            // Mid green side blob
                            Positioned(
                              right: -40,
                              top: 60,
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF66BB6A), // medium green
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(120),
                                    bottomLeft: Radius.circular(120),
                                  ),
                                ),
                              ),
                            ),

                            // Back arrow (optional)
                            Positioned(
                              left: 8,
                              top: 12,
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios,
                                    color: Colors.white),
                                onPressed: () {
                                  Navigator.maybePop(context);
                                },
                              ),
                            ),

                            // Welcome text
                            const Positioned(
                              left: 24,
                              bottom: 40,
                              child: Text(
                                "Welcome\nBack",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ---------- FORM AREA ----------
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Email / Username
                              const Text(
                                "Email",
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              TextField(
                                controller: usernameController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  hintText: "Enter Email / Username",
                                  border: UnderlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Password
                              const Text(
                                "Password",
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              TextField(
                                controller: passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: "Enter Password",
                                  border: UnderlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 32),

                              // Sign in + round arrow button
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Sign in",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _handleLogin(context),
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF2E7D32),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.arrow_forward,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "Default login",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ),

                              const Spacer(),
                              // No Sign up / Forgot Password links anymore
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
