import 'package:flutter/material.dart';
import 'bluetooth_scanner_page.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/screens/ac_app/sigin.dart';

class ModeSelectionPage extends StatefulWidget {
  const ModeSelectionPage({super.key});

  @override
  State<ModeSelectionPage> createState() => _ModeSelectionPageState();
}

class _ModeSelectionPageState extends State<ModeSelectionPage> {
  String? _userEmail;
  String _userName = 'Sustainabyte User';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final email = await AuthService.getEmail();
      final userData = await AuthService.getUserData();
      if (mounted) {
        setState(() {
          _userEmail = email;
          _userName = userData?['name'] ?? 'Sustainabyte User';
        });
      }
    } catch (e) {
      debugPrint('Error loading user data in mode selection page: $e');
    }
  }

  Future<void> _handleForgotPassword() async {
    final TextEditingController emailController = TextEditingController();
    
    // Pre-fill with current user email if available
    final currentEmail = await AuthService.getEmail();
    if (currentEmail != null) {
      emailController.text = currentEmail;
    }
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D44),
        title: const Text('Reset Password', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email to receive a password reset link.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              if (emailController.text.trim().isNotEmpty) {
                try {
                  // await AuthService.sendPasswordResetEmail(emailController.text.trim());
                  // Mock HVAC AuthService doesn't support this yet
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password reset email sent!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Send', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D44),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      await AuthService.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SignInPage()),
          (route) => false,
        );
      }
    }
  }

  Widget _buildHomeContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2D2D44) : const Color(0xFFF3F7FA);
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    final textSecondaryColor = isDark ? Colors.white70 : const Color(0xFF5A6E85);
    final iconColor = isDark ? Colors.white70 : const Color(0xFF1B172E);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [
                  Color.fromARGB(255, 123, 159, 71), // primary green
                  Color.fromARGB(255, 123, 159, 71), // primary green
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                const Icon(
                  Icons.ac_unit,
                  size: 42,
                  color: Colors.white,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Sustainabyte",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Optibyte IR",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            "",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            " ",
            style: TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),

          const SizedBox(height: 18),

          // CONFIGURATION MODE CARD
          Card(
            color: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                // Go to Bluetooth scanner, which then leads to ConfigurationPage
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BluetoothScannerPage(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 123, 159, 71),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: const Icon(
                        Icons.settings_remote,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Configuration Mode",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "• Connect to device via Bluetooth\n",
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: textSecondaryColor),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // CLOUD CONTROL INFO CARD (no MQTT config here, only information)
          Card(
            color: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cloud_queue,
                    color: iconColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Cloud Control (MQTT) is available after:\n"
                      "1. Bluetooth configuration is completed.\n"
                      "2. WiFi is connected in Configuration Page.\n"
                      "3. MQTT is set in the separate MQTT page.",
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2D2D44) : const Color(0xFFF3F7FA);
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    final textSecondaryColor = isDark ? Colors.white70 : const Color(0xFF5A6E85);
    final iconColor = isDark ? Colors.white70 : const Color(0xFF1B172E);
    final dividerColor = isDark ? Colors.white24 : Colors.black12;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: cardColor,
            child: Icon(
              Icons.person,
              size: 40,
              color: textSecondaryColor,
            ),
          ),
          const SizedBox(height: 10),
          if (_userEmail != null)
            Text(
              _userEmail!,
              style: TextStyle(
                fontSize: 14,
                color: textSecondaryColor,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            _userName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Optibyte Smart AC Control",
            style: TextStyle(
              fontSize: 12,
              color: textSecondaryColor,
            ),
          ),
          const SizedBox(height: 20),

          ListTile(
            leading: Icon(Icons.info_outline, color: iconColor),
            title: Text("App Version", style: TextStyle(color: textColor)),
            subtitle: Text("Optibyte IR Control v1.0.0", style: TextStyle(color: textSecondaryColor)),
            onTap: () {},
          ),
          Divider(height: 1, color: dividerColor),
          ListTile(
            leading: Icon(Icons.business, color: iconColor),
            title: Text("Company", style: TextStyle(color: textColor)),
            subtitle: Text("Sustainabyte Technologies Pvt Ltd", style: TextStyle(color: textSecondaryColor)),
            onTap: () {},
          ),
          Divider(height: 1, color: dividerColor),
          ListTile(
            leading: Icon(Icons.mail_outline, color: iconColor),
            title: Text("Support", style: TextStyle(color: textColor)),
            subtitle: Text("support@sustainabyte.com", style: TextStyle(color: textSecondaryColor)),
            onTap: () {},
          ),
          Divider(height: 1, color: dividerColor),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _handleLogout,
                    icon: const Icon(Icons.logout, size: 20),
                    label: const Text("Logout"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _handleForgotPassword,
                    icon: const Icon(Icons.lock_reset, size: 20),
                    label: const Text("Forgot Password"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          "Mode Selection",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: _buildHomeContent(),
    );
  }
}
