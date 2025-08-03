import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _isLoading = true;
  bool _masterNotificationsEnabled = false; // OS-level permission
  bool _newMessagesEnabled = true;
  bool _eventRemindersEnabled = true;

  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    await _checkNotificationStatus();
    await _fetchNotificationPreferences();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Checks the OS-level permission status for notifications.
  Future<void> _checkNotificationStatus() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _masterNotificationsEnabled = status.isGranted;
      });
    }
  }

  /// Fetches the user's saved notification preferences from Firestore.
  Future<void> _fetchNotificationPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (mounted && userDoc.exists) {
      final data = userDoc.data()?['notificationPreferences'];
      setState(() {
        // Default to true if the preference is not explicitly set to false
        _newMessagesEnabled = data?['newMessages'] ?? true;
        _eventRemindersEnabled = data?['eventReminders'] ?? true;
      });
    }
  }

  /// Handles the master toggle for enabling/disabling all notifications.
  Future<void> _handleMasterNotificationToggle(bool wantsToEnable) async {
    if (wantsToEnable) {
      final status = await Permission.notification.request();
      if (status.isGranted) {
        // Permission granted, now get the token and save it.
        try {
          final fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({
                'pushTokens': FieldValue.arrayUnion([fcmToken])
              }, SetOptions(merge: true));
            }
          }
          setState(() => _masterNotificationsEnabled = true);
        } catch (e) {
          // Handle token error
        }
      } else {
        // Permission denied, show dialog to open settings.
        _showOpenSettingsDialog();
      }
    } else {
      // User wants to disable, so we direct them to settings.
      _showOpenSettingsDialog(isDisabling: true);
    }
  }

  /// Toggles a specific notification preference and saves it to Firestore.
  Future<void> _handlePreferenceToggle(String key, bool newValue) async {
    // Optimistic UI update
    setState(() {
      if (key == 'newMessages') _newMessagesEnabled = newValue;
      if (key == 'eventReminders') _eventRemindersEnabled = newValue;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'notificationPreferences': {key: newValue}
      }, SetOptions(merge: true));
    } catch (e) {
      // Revert on error
      setState(() {
        if (key == 'newMessages') _newMessagesEnabled = !newValue;
        if (key == 'eventReminders') _eventRemindersEnabled = !newValue;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to update preference.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showOpenSettingsDialog({bool isDisabling = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade800,
        title: Text(
            isDisabling ? 'Disable Notifications' : 'Permission Required',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          isDisabling
              ? 'To turn off notifications, you need to do it from your device\'s system settings.'
              : 'Notification permissions are required. Please enable them in your device settings.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () {
              // If they were trying to disable, keep the switch on since they cancelled.
              if (isDisabling) {
                setState(() => _masterNotificationsEnabled = true);
              }
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: const Text('Open Settings',
                style: TextStyle(color: Colors.purpleAccent)),
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
                  title: Text('Notifications',
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: _isLoading
                        ? const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader('Push Notifications'),
                              _buildSettingsCard([
                                _buildSwitchTile(
                                  title: 'Allow Notifications',
                                  value: _masterNotificationsEnabled,
                                  onChanged: _handleMasterNotificationToggle,
                                ),
                              ]),
                              _buildSectionFooter(
                                  'This controls all push notifications from the app. To disable them, you must do so from your device settings.'),
                              _buildSectionHeader('Notification Types'),
                              _buildSettingsCard([
                                _buildSwitchTile(
                                  title: 'New Messages',
                                  value: _newMessagesEnabled,
                                  onChanged: (value) => _handlePreferenceToggle(
                                      'newMessages', value),
                                  isEnabled: _masterNotificationsEnabled,
                                ),
                                _buildSwitchTile(
                                  title: 'Event Reminders',
                                  value: _eventRemindersEnabled,
                                  onChanged: (value) => _handlePreferenceToggle(
                                      'eventReminders', value),
                                  isEnabled: _masterNotificationsEnabled,
                                ),
                              ]),
                              _buildSectionFooter(
                                  'Choose what you want to be notified about.'),
                              const SizedBox(height: 100),
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

  Widget _buildSectionFooter(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.7),
          fontSize: 13,
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

  Widget _buildSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isEnabled = true,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: isEnabled ? Colors.white : Colors.white54,
          fontWeight: FontWeight.w600,
        ),
      ),
      value: value,
      onChanged: isEnabled ? onChanged : null,
      activeColor: Colors.purple.shade300,
      activeTrackColor: Colors.purple.shade300.withOpacity(0.5),
      inactiveThumbColor: Colors.white70,
      inactiveTrackColor: Colors.grey.shade600,
    );
  }
}
