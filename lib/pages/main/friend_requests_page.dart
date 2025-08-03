import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // For formatting timestamps

class FriendRequestsPage extends StatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  State<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends State<FriendRequestsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription? _incomingRequestsSubscription;
  StreamSubscription? _outgoingRequestsSubscription;

  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _outgoingRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _listenToFriendRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _incomingRequestsSubscription?.cancel();
    _outgoingRequestsSubscription?.cancel();
    super.dispose();
  }

  void _listenToFriendRequests() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Listen for incoming friend requests
    _incomingRequestsSubscription = _firestore
        .collection('friendRequests')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) async {
      List<Map<String, dynamic>> requests = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final senderId = data['senderId'];
        // Fetch sender's user data
        final senderDoc =
            await _firestore.collection('users').doc(senderId).get();
        final senderData = senderDoc.data();
        final senderUsername = senderData?['username'] ?? 'Unknown User';
        final senderAvatar = senderData?['profilePicture'];

        requests.add({
          'id': doc.id,
          'senderId': senderId,
          'senderUsername': senderUsername,
          'senderAvatar': senderAvatar,
          'createdAt': data['createdAt'],
        });
      }
      if (mounted) {
        setState(() => _incomingRequests = requests);
      }
    });

    // Listen for outgoing friend requests
    _outgoingRequestsSubscription = _firestore
        .collection('friendRequests')
        .where('senderId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) async {
      List<Map<String, dynamic>> requests = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final receiverId = data['receiverId'];
        // Fetch receiver's user data
        final receiverDoc =
            await _firestore.collection('users').doc(receiverId).get();
        final receiverData = receiverDoc.data();
        final receiverUsername = receiverData?['username'] ?? 'Unknown User';
        final receiverAvatar = receiverData?['profilePicture'];

        requests.add({
          'id': doc.id,
          'receiverId': receiverId,
          'receiverUsername': receiverUsername,
          'receiverAvatar': receiverAvatar,
          'createdAt': data['createdAt'],
        });
      }
      if (mounted) {
        setState(() => _outgoingRequests = requests);
      }
    });
  }

  Future<void> _acceptFriendRequest(String requestId, String senderId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Delete the friend request document
      await _firestore.collection('friendRequests').doc(requestId).delete();

      // Add each other to friends list (mutual friendship)
      await _firestore.collection('users').doc(currentUser.uid).update({
        'friends': FieldValue.arrayUnion([senderId]),
      });
      await _firestore.collection('users').doc(senderId).update({
        'friends': FieldValue.arrayUnion([currentUser.uid]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Friend request accepted.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to accept request. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _declineFriendRequest(String requestId) async {
    try {
      // Delete the friend request document
      await _firestore.collection('friendRequests').doc(requestId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Friend request declined.'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to decline request. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _cancelFriendRequest(String requestId) async {
    try {
      // Delete the friend request document
      await _firestore.collection('friendRequests').doc(requestId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Friend request cancelled.'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to cancel request. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
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
                    'Friend Requests',
                    style: GoogleFonts.poppins(
                      fontSize: 24, // Consistent with other app bar titles
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  bottom: TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white.withOpacity(0.7),
                    indicatorColor: Colors.white,
                    indicatorWeight: 3.0,
                    tabs: const [
                      Tab(text: 'Incoming'),
                      Tab(text: 'Outgoing'),
                    ],
                  ),
                ),
                SliverFillRemaining(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildIncomingRequestsList(),
                      _buildOutgoingRequestsList(),
                    ],
                  ),
                ),
              ],
            ),
          )),
    );
  }

  Widget _buildIncomingRequestsList() {
    if (_incomingRequests.isEmpty) {
      return Center(
        child: Text(
          'No incoming friend requests.',
          style: GoogleFonts.poppins(
              fontSize: 16, color: Colors.white.withOpacity(0.7)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _incomingRequests.length,
      itemBuilder: (context, index) {
        final request = _incomingRequests[index];
        final senderAvatar = request['senderAvatar'] as String?;
        final timestamp = (request['createdAt'] as Timestamp?)?.toDate();
        final formattedTime = timestamp != null
            ? DateFormat('MMM d, h:mm a').format(timestamp)
            : 'N/A';

        return ListTile(
          leading: CircleAvatar(
            radius: 25,
            backgroundColor: Colors.white24,
            backgroundImage:
                senderAvatar != null ? NetworkImage(senderAvatar) : null,
            child: senderAvatar == null
                ? const Icon(Icons.person, color: Colors.white70)
                : null,
          ),
          title: Text(
            request['senderUsername'],
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'Sent: $formattedTime',
            style:
                TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
          ),
          // --- MODIFIED: Replaced ElevatedButton with compact IconButtons ---
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Accept Button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.shade400,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.check, size: 20),
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      _acceptFriendRequest(request['id'], request['senderId']),
                ),
              ),
              const SizedBox(width: 8),
              // Decline Button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  onPressed: () => _declineFriendRequest(request['id']),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOutgoingRequestsList() {
    if (_outgoingRequests.isEmpty) {
      return Center(
        child: Text(
          'No outgoing friend requests.',
          style: GoogleFonts.poppins(
              fontSize: 16, color: Colors.white.withOpacity(0.7)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _outgoingRequests.length,
      itemBuilder: (context, index) {
        final request = _outgoingRequests[index];
        final receiverAvatar = request['receiverAvatar'] as String?;
        // --- ADDED: Timestamp formatting ---
        final timestamp = (request['createdAt'] as Timestamp?)?.toDate();
        final formattedTime = timestamp != null
            ? DateFormat('MMM d, h:mm a').format(timestamp)
            : 'N/A';

        return ListTile(
          leading: CircleAvatar(
            radius: 25,
            backgroundColor: Colors.white24,
            backgroundImage:
                receiverAvatar != null ? NetworkImage(receiverAvatar) : null,
            child: receiverAvatar == null
                ? const Icon(Icons.person, color: Colors.white70)
                : null,
          ),
          title: Text(
            request['receiverUsername'],
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          // --- ADDED: Subtitle for the timestamp ---
          subtitle: Text(
            'Sent: $formattedTime',
            style:
                TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
          ),
          trailing: ElevatedButton(
            onPressed: () => _cancelFriendRequest(request['id']),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Cancel'),
          ),
        );
      },
    );
  }
}
