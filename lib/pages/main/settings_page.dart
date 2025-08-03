import 'dart:io'; // Import for Platform class
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart'; // Import for Cloud Functions
import 'package:package_info_plus/package_info_plus.dart'; // Import for package info
import 'package:wimbli/pages/auth/login_page.dart';
import 'package:wimbli/pages/main/about_app_page.dart';
import 'package:wimbli/pages/main/blocked_users_page.dart';
import 'package:wimbli/pages/main/change_password_page.dart';
import 'package:wimbli/pages/main/help_and_support_page.dart';
import 'package:wimbli/pages/main/notification_settings_page.dart';
import 'package:wimbli/pages/main/friend_requests_page.dart'; // NEW: Import FriendRequestsPage
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wimbli/pages/main/edit_profile_page.dart';

class SettingsPage extends StatefulWidget {
  final Future<void> Function()? onBeforeSignOut;

  const SettingsPage({super.key, this.onBeforeSignOut});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoggingOut = false;
  bool _isDeleting = false; // State for delete process
  String _appVersion = '1.0.0'; // State for app version

  String? _username;
  String? _profileImageUrl;
  bool _isLoadingUser = true;

  // --- App Store and Play Store Identifiers ---
  static const String _playStoreId = 'com.oscasavia.wimbli';
  static const String _appStoreId = '674773'; // Example App Store ID

  // --- Cloud Functions instance ---
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  void initState() {
    super.initState();
    _getAppInfo(); // Fetch app info on init
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingUser = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted && doc.exists) {
        setState(() {
          _username = doc.data()?['username'];
          _profileImageUrl = doc.data()?['profilePicture'];
          _isLoadingUser = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingUser = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  Future<void> _getAppInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  Future<void> _signOut(BuildContext context) async {
    // Set loading state if you have a visual indicator
    if (mounted) setState(() => _isLoggingOut = true);

    // 1. Sign the user out from Firebase
    await FirebaseAuth.instance.signOut();

    // 2. Dismiss all pages on top of the AuthGate (Settings, Profile, etc.)
    // This reveals the LoginPage that AuthGate is now showing.
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _deleteAccount() async {
    final bool confirmDelete = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.grey.shade800,
            title: const Text('Confirm Account Deletion',
                style: TextStyle(color: Colors.white)),
            content: const Text(
                'Are you sure you want to delete your account? This action is irreversible.',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child:
                    const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmDelete) {
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      // Call the Cloud Function to delete the user account and associated data
      final HttpsCallable callable =
          _functions.httpsCallable('deleteAllUserData');
      final result = await callable.call();

      if (result.data['success']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account deleted successfully.')),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (Route<dynamic> route) => false,
          );
        }
      } else {
        throw result.data['error'] ?? 'Unknown error';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Future<void> _launchAppStore() async {
    final uri = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/app/id$_appStoreId')
        : Uri.parse(
            'https://play.google.com/store/apps/details?id=$_playStoreId');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch app store.')),
        );
      }
    }
  }

  Future<void> _shareApp() async {
    final String appLink = Platform.isIOS
        ? 'Check out Wimbli on the App Store: https://apps.apple.com/app/id$_appStoreId'
        : 'Check out Wimbli on Google Play: https://play.google.com/store/apps/details?id=$_playStoreId';
    await Share.share(appLink);
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not launch $url'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildUserProfileHeader() {
    if (_isLoadingUser) {
      // Show a placeholder while the user data is loading
      return const SizedBox(
          height: 86); // Roughly the height of the final widget
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditProfilePage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 3.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white24,
              backgroundImage: _profileImageUrl != null
                  ? NetworkImage(_profileImageUrl!)
                  : null,
              child: _profileImageUrl == null
                  ? const Icon(Icons.person, size: 30, color: Colors.white70)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _username ?? 'Your Name',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Edit Profile',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // const Icon(Icons.arrow_forward_ios,
            //     color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
          // Apply the consistent gradient background
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade200, Colors.purple.shade300],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  title: Text(
                    'Settings',
                    style: GoogleFonts.poppins(
                      fontSize: 24, // Consistent with other app bar titles
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  // pinned: true,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0), // Consistent padding
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildUserProfileHeader(),
                        const Divider(color: Colors.white24, height: 1),
                        _buildSectionHeader(
                            'Account Settings'), // Adjusted header
                        _buildSettingsCard([
                          // Using _buildSettingsCard for consistency
                          _buildSettingsTile(
                              Icons.lock_outline, 'Change Password', onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ChangePasswordPage()),
                            );
                          }),
                          _buildSettingsTile(Icons.notifications_none,
                              'Notification Settings', // Moved here
                              onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const NotificationSettingsPage()),
                            );
                          }),
                          _buildSettingsTile(
                              Icons.person_add_alt_1, 'Friend Requests',
                              onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const FriendRequestsPage()),
                            );
                          }),
                          _buildSettingsTile(Icons.block, 'Blocked Users',
                              onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const BlockedUsersPage()),
                            );
                          }),
                        ]),
                        const SizedBox(height: 24),
                        _buildSectionHeader(
                            'Support & Information'), // Adjusted header
                        _buildSettingsCard([
                          // Using _buildSettingsCard for consistency
                          _buildSettingsTile(
                              Icons.help_outline, 'Help & Support', onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => HelpAndSupportPage()),
                            );
                          }),
                          _buildSettingsTile(Icons.info_outline, 'About Wimbli',
                              onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AboutAppPage()),
                            );
                          }),
                        ]),
                        const SizedBox(height: 24),
                        _buildSectionHeader('App Actions'), // Adjusted header
                        _buildSettingsCard([
                          // Using _buildSettingsCard for consistency
                          _buildSettingsTile(Icons.star_border, 'Rate Us',
                              onTap: _launchAppStore),
                          _buildSettingsTile(Icons.share, 'Share App',
                              onTap: _shareApp),
                        ]),
                        const SizedBox(height: 24),
                        _buildSectionHeader('Legal'), // Adjusted header
                        _buildSettingsCard([
                          // Using _buildSettingsCard for consistency
                          _buildSettingsTile(
                              Icons.gavel_outlined, 'Terms of Service',
                              onTap: () =>
                                  _launchURL('https://wimbli.app/terms')),
                          _buildSettingsTile(
                              Icons.privacy_tip_outlined, 'Privacy Policy',
                              onTap: () =>
                                  _launchURL('https://wimbli.app/privacy')),
                        ]),
                        const SizedBox(height: 36),
                        Center(
                          // Added Center widget for app version
                          child: Text(
                            'Version $_appVersion',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildActionButton(context, 'Log Out',
                            Colors.red.shade400, () => _signOut(context),
                            isLoading: _isLoggingOut),
                        const SizedBox(height: 16),
                        _buildActionButton(context, 'Delete Account',
                            Colors.grey.shade700, _deleteAccount,
                            isLoading: _isDeleting),
                        const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Card(
      color: Colors.white.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title,
      {required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w600)),
      trailing:
          const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildActionButton(
      BuildContext context, String text, Color color, VoidCallback onPressed,
      {required bool isLoading}) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
