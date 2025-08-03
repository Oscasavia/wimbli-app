import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

// A simple model to hold the data for a blocked user.
class BlockedUser {
  final String id;
  final String username;
  final String? profilePictureUrl;

  BlockedUser({
    required this.id,
    required this.username,
    this.profilePictureUrl,
  });
}

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  bool _isLoading = true;
  List<BlockedUser> _blockedUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchBlockedUsers();
  }

  /// Fetches the list of blocked user IDs and then fetches their profile data.
  Future<void> _fetchBlockedUsers() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

    // Listen to real-time changes on the user's document
    userDocRef.snapshots().listen((userDoc) async {
      if (mounted && userDoc.exists) {
        final blockedUserIds =
            List<String>.from(userDoc.data()?['blockedUsers'] ?? []);

        if (blockedUserIds.isEmpty) {
          setState(() {
            _blockedUsers = [];
            _isLoading = false;
          });
          return;
        }

        // Fetch profile data for each blocked user ID
        final List<BlockedUser> usersData = [];
        for (String id in blockedUserIds) {
          final docSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(id)
              .get();
          if (docSnap.exists) {
            usersData.add(BlockedUser(
              id: docSnap.id,
              username: docSnap.data()?['username'] ?? 'Unknown User',
              profilePictureUrl: docSnap.data()?['profilePicture'],
            ));
          }
        }

        setState(() {
          _blockedUsers = usersData;
          _isLoading = false;
        });
      }
    }, onError: (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to load blocked users.'),
          backgroundColor: Colors.red,
        ));
      }
    });
  }

  /// Shows a confirmation dialog and unblocks the user if confirmed.
  Future<void> _unblockUser(String userId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade800,
        title: Text('Unblock $username?',
            style: const TextStyle(color: Colors.white)),
        content: const Text(
            'They will be able to see your profile and interact with you again.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Unblock', style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

    try {
      await userDocRef.update({
        'blockedUsers': FieldValue.arrayRemove([userId])
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unblocked $username'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to unblock user. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
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
                  title: Text('Blocked Users',
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                _isLoading
                    ? const SliverFillRemaining(
                        child: Center(
                            child:
                                CircularProgressIndicator(color: Colors.white)))
                    : _blockedUsers.isEmpty
                        ? _buildEmptyState()
                        : _buildBlockedUserList(),
              ],
            ),
          )),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_accounts_outlined,
                size: 80, color: Colors.white.withOpacity(0.7)),
            const SizedBox(height: 20),
            Text(
              'No Blocked Users',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9)),
            ),
            const SizedBox(height: 8),
            Text(
              "When you block someone, they'll appear here.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedUserList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final user = _blockedUsers[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ListTile(
                contentPadding: const EdgeInsets.all(0),
                leading: CircleAvatar(
                  radius: 25,
                  backgroundImage: user.profilePictureUrl != null
                      ? NetworkImage(user.profilePictureUrl!)
                      : null,
                  backgroundColor: Colors.white24,
                  child: user.profilePictureUrl == null
                      ? const Icon(Icons.person, color: Colors.white70)
                      : null,
                ),
                title: Text(
                  user.username,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                trailing: TextButton(
                  onPressed: () => _unblockUser(user.id, user.username),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.25),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Unblock'),
                ),
              ),
            );
          },
          childCount: _blockedUsers.length,
        ),
      ),
    );
  }
}
