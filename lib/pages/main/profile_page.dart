import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wimbli/models/event_model.dart';
import 'package:wimbli/pages/main/edit_profile_page.dart';
import 'package:wimbli/pages/main/settings_page.dart';
import 'package:wimbli/pages/main/event_details_page.dart';
import 'package:wimbli/constants/app_data.dart';
import 'package:wimbli/models/app_category.dart';

class ProfilePage extends StatefulWidget {
  final String? userId; // Can be null to show the current user's profile

  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late ScrollController _scrollController;
  StreamSubscription? _userSubscription;
  StreamSubscription? _postsSubscription;
  StreamSubscription? _interestedEventsSubscription;
  StreamSubscription? _currentUserSubscription;

  // --- State for the CURRENT user's saved posts ---
  StreamSubscription? _currentUserSavedPostsSubscription;
  List<String> _currentUserSavedPostIds = [];

  // --- NEW: Friend related state ---
  StreamSubscription?
      _targetUserFriendsSubscription; // To listen to the target user's friends list
  StreamSubscription?
      _friendRequestStatusSubscription; // To listen for friend request status between users
  String _friendRequestStatus = 'none'; // 'none', 'sent', 'received', 'friends'
  int _friendCount = 0; // How many friends does the target user have?

  Map<String, dynamic>? _userData;
  int _postCount = 0;
  List<Event> _interestedEvents = [];
  List<Event> _myPosts = [];
  bool _isLoading = true;
  bool _isCurrentUserProfile = false;
  List<Event> _friendActivityEvents = [];
  List<Map<String, dynamic>> _profileUserFriends =
      []; // To hold friend data (id, username, etc.)
  List<Map<String, dynamic>> _mutualFriends = [];
  List<String> _currentUserFriendIds = [];
  bool _isFriendsTabLoading = true;

  List<String> _blockedUsers = [];
  bool _isBlocked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scrollController = ScrollController();
    _determineProfileTypeAndFetchData();
  }

  void _determineProfileTypeAndFetchData() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId ?? currentUser?.uid;

    if (targetUserId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    setState(() {
      _isCurrentUserProfile =
          widget.userId == null || widget.userId == currentUser?.uid;
    });

    _fetchCurrentUserSavedPosts();
    _fetchUserData(targetUserId);

    if (!_isCurrentUserProfile && currentUser != null) {
      _fetchBlockedUsers(currentUser.uid, targetUserId);
      // --- NEW: Fetch friend status and target user's friend count ---
      _fetchFriendStatusAndCount(currentUser.uid, targetUserId);
    } else if (_isCurrentUserProfile && currentUser != null) {
      // If it's the current user's profile, fetch their own friend count
      // No friend request status needed for self profile
      _fetchFriendStatusAndCount(currentUser.uid, currentUser.uid);
    }
  }

  /// Fetches the current logged-in user's list of saved posts.
  void _fetchCurrentUserSavedPosts() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _currentUserSavedPostsSubscription?.cancel();
    _currentUserSavedPostsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists) {
        setState(() {
          _currentUserSavedPostIds =
              List<String>.from(snapshot.data()?['savedPosts'] ?? []);
        });
      }
    });
  }

  void _fetchBlockedUsers(String currentUserId, String targetUserId) {
    _currentUserSubscription?.cancel();
    _currentUserSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists) {
        final data = snapshot.data();
        final blocked = List<String>.from(data?['blockedUsers'] ?? []);
        setState(() {
          _blockedUsers = blocked;
          _isBlocked = _blockedUsers.contains(targetUserId);
        });
      }
    });
  }

  void _fetchFriendStatusAndCount(
      String currentUserId, String targetUserId) async {
    if (_currentUserFriendIds.isEmpty) {
      final currentUserDoc =
          await _firestore.collection('users').doc(currentUserId).get();
      if (mounted) {
        setState(() {
          _currentUserFriendIds =
              List<String>.from(currentUserDoc.data()?['friends'] ?? []);
        });
      }
    }

    // Listen to the target user's friends list to get their friend count
    _targetUserFriendsSubscription?.cancel();
    _targetUserFriendsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(targetUserId)
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists) {
        final data = snapshot.data();
        final friends = List<String>.from(data?['friends'] ?? []);
        setState(() {
          _friendCount = friends.length;
          _isFriendsTabLoading = true;
        });

        if (targetUserId == currentUserId) {
          // It's our own profile, so fetch friend activity
          _fetchFriendActivity(friends);
        } else {
          // It's someone else's profile, fetch their friends list
          _fetchProfileUserFriends(targetUserId);
        }
      }
    });

    // If viewing another user's profile, also check friend request status
    if (currentUserId != targetUserId) {
      _friendRequestStatusSubscription?.cancel();
      _friendRequestStatusSubscription = FirebaseFirestore.instance
          .collection('friendRequests')
          .where(Filter.or(
            Filter.and(
              Filter('senderId', isEqualTo: currentUserId),
              Filter('receiverId', isEqualTo: targetUserId),
            ),
            Filter.and(
              Filter('senderId', isEqualTo: targetUserId),
              Filter('receiverId', isEqualTo: currentUserId),
            ),
          ))
          .snapshots()
          .listen((snapshot) async {
        if (mounted) {
          String newStatus = 'none';
          if (snapshot.docs.isNotEmpty) {
            final request = snapshot.docs.first.data();
            final status = request['status'];
            final senderId = request['senderId'];

            if (status == 'pending') {
              if (senderId == currentUserId) {
                newStatus = 'sent'; // Current user sent the request
              } else {
                newStatus = 'received'; // Current user received the request
              }
            } else if (status == 'accepted') {
              // If a request was accepted, but the document still exists,
              // it means the cleanup hasn't happened yet.
              // We should still consider them friends for UI purposes.
              newStatus = 'friends';
            }
          } else {
            // No pending or accepted request document, check if they are already friends
            final currentUserDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUserId)
                .get();
            final currentUserFriends =
                List<String>.from(currentUserDoc.data()?['friends'] ?? []);

            if (currentUserFriends.contains(targetUserId)) {
              newStatus = 'friends';
            } else {
              newStatus = 'none';
            }
          }

          setState(() {
            _friendRequestStatus = newStatus;
          });
        }
      });
    } else {
      // If viewing own profile, no friend request status
      if (mounted) {
        setState(() {
          _friendRequestStatus = 'none';
        });
      }
    }
  }

  @override
  void dispose() {
    print("--- DISPOSING PROFILE PAGE ---");
    _tabController.dispose();
    _scrollController.dispose();
    _userSubscription?.cancel();
    _postsSubscription?.cancel();
    _interestedEventsSubscription?.cancel();
    _currentUserSubscription?.cancel();
    _currentUserSavedPostsSubscription?.cancel();
    _targetUserFriendsSubscription?.cancel(); // Cancel new subscription
    _friendRequestStatusSubscription?.cancel(); // Cancel new subscription
    super.dispose();
  }

  void _fetchUserData(String userId) {
    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _userData = snapshot.data();
          _isLoading = false;
        });
        final savedPostIds = List<String>.from(_userData?['savedPosts'] ?? []);
        _fetchInterestedEvents(savedPostIds);
      }
    });

    _postsSubscription = FirebaseFirestore.instance
        .collection('posts')
        .where('createdBy', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        final posts = snapshot.docs.map((doc) {
          final event = Event.fromFirestore(doc);
          // --- FIX: Set interested status based on the CURRENT user ---
          event.isInterested = _currentUserSavedPostIds.contains(event.id);
          return event;
        }).toList();
        posts.sort((a, b) => b.date.compareTo(a.date));
        setState(() {
          _myPosts = posts;
          _postCount = snapshot.docs.length;
        });
      }
    });
  }

  void _fetchInterestedEvents(List<String> eventIds) {
    _interestedEventsSubscription?.cancel();

    if (eventIds.isEmpty) {
      if (mounted) setState(() => _interestedEvents = []);
      return;
    }

    final query = FirebaseFirestore.instance
        .collection('posts')
        .where(FieldPath.documentId, whereIn: eventIds);

    _interestedEventsSubscription = query.snapshots().listen((snapshot) {
      if (mounted) {
        final events = snapshot.docs.map((doc) {
          final event = Event.fromFirestore(doc);
          event.isInterested = _currentUserSavedPostIds.contains(event.id);
          return event;
        }).toList();

        final filteredEvents = events.where((event) {
          return !_blockedUsers.contains(event.createdBy);
        }).toList();

        setState(() {
          // Use the newly filtered list
          _interestedEvents = filteredEvents;
        });
      }
    });
  }

  Future<void> _toggleBlockUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId;
    if (currentUser == null || targetUserId == null) return;

    final targetUsername = _userData?['username'] ?? 'this user';
    final isCurrentlyBlocked = _isBlocked;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade800,
        title: Text(isCurrentlyBlocked ? 'Unblock User' : 'Block User',
            style: const TextStyle(color: Colors.white)),
        content: Text(
            'Are you sure you want to ${isCurrentlyBlocked ? 'unblock' : 'block'} $targetUsername?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(isCurrentlyBlocked ? 'Unblock' : 'Block',
                  style: TextStyle(
                      color: isCurrentlyBlocked ? null : Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    final currentUserDocRef =
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

    try {
      await currentUserDocRef.update({
        'blockedUsers': isCurrentlyBlocked
            ? FieldValue.arrayRemove([targetUserId])
            : FieldValue.arrayUnion([targetUserId]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Successfully ${isCurrentlyBlocked ? 'unblocked' : 'blocked'} $targetUsername.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Failed to ${isCurrentlyBlocked ? 'unblock' : 'block'} user. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _fetchFriendActivity(List<String> friendIds) async {
    if (friendIds.isEmpty) {
      if (mounted) setState(() => _isFriendsTabLoading = false);
      return;
    }

    // 1. Get all the post IDs your friends are interested in
    final friendsQuery = await _firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: friendIds)
        .get();

    final Set<String> allInterestedPostIds = {};
    for (var friendDoc in friendsQuery.docs) {
      final savedPosts =
          List<String>.from(friendDoc.data()['savedPosts'] ?? []);
      allInterestedPostIds.addAll(savedPosts);
    }

    if (allInterestedPostIds.isEmpty) {
      if (mounted) setState(() => _isFriendsTabLoading = false);
      return;
    }

    // 2. Fetch the actual event data for those post IDs
    final eventsQuery = await _firestore
        .collection('posts')
        .where(FieldPath.documentId, whereIn: allInterestedPostIds.toList())
        .get();

    final events =
        eventsQuery.docs.map((doc) => Event.fromFirestore(doc)).toList();

    // Sort by date so the newest events appear first
    events.sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _friendActivityEvents = events;
        _isFriendsTabLoading = false;
      });
    }
  }

  Future<void> _fetchProfileUserFriends(String profileUserId) async {
    final userDoc =
        await _firestore.collection('users').doc(profileUserId).get();
    final profileFriendIds =
        List<String>.from(userDoc.data()?['friends'] ?? []);

    if (profileFriendIds.isEmpty) {
      if (mounted) {
        setState(() {
          _mutualFriends = []; // Ensure both lists are cleared
          _profileUserFriends = [];
          _isFriendsTabLoading = false;
        });
      }
      return;
    }

    // 1. Calculate which friends are mutual and which are not
    final mutualFriendIds = profileFriendIds
        .where((id) => _currentUserFriendIds.contains(id))
        .toList();
    final otherFriendIds = profileFriendIds
        .where((id) => !_currentUserFriendIds.contains(id))
        .toList();

    // 2. Fetch data for mutual friends (if any)
    if (mutualFriendIds.isNotEmpty) {
      final mutualsSnapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: mutualFriendIds)
          .get();
      if (mounted) {
        setState(() {
          _mutualFriends = mutualsSnapshot.docs
              .map((doc) =>
                  {'uid': doc.id, ...doc.data()})
              .toList();
        });
      }
    } else if (mounted) {
      setState(() {
        _mutualFriends = []; // Clear the list if there are no mutuals
      });
    }

    // 3. Fetch data for the rest of the friends (if any)
    if (otherFriendIds.isNotEmpty) {
      final othersSnapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: otherFriendIds)
          .get();
      if (mounted) {
        setState(() {
          _profileUserFriends = othersSnapshot.docs
              .map((doc) =>
                  {'uid': doc.id, ...doc.data()})
              .toList();
        });
      }
    } else if (mounted) {
      setState(() {
        _profileUserFriends = []; // Clear the list if all friends were mutual
      });
    }

    // 4. Set loading to false once all fetches are complete
    if (mounted) {
      setState(() {
        _isFriendsTabLoading = false;
      });
    }
  }

  Future<void> _sendFriendRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId;
    if (currentUser == null || targetUserId == null) return;

    try {
      await FirebaseFirestore.instance.collection('friendRequests').add({
        'senderId': currentUser.uid,
        'receiverId': targetUserId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Friend request sent to ${_userData?['username'] ?? 'user'}.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send friend request. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _acceptFriendRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId;
    if (currentUser == null || targetUserId == null) return;

    try {
      // Find the pending request
      final querySnapshot = await FirebaseFirestore.instance
          .collection('friendRequests')
          .where('senderId', isEqualTo: targetUserId)
          .where('receiverId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final requestId = querySnapshot.docs.first.id;
        // Delete the request document after processing
        await FirebaseFirestore.instance
            .collection('friendRequests')
            .doc(requestId)
            .delete();

        // Add each other to friends list (mutual friendship)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({
          'friends': FieldValue.arrayUnion([targetUserId]),
        });
        await FirebaseFirestore.instance
            .collection('users')
            .doc(targetUserId)
            .update({
          'friends': FieldValue.arrayUnion([currentUser.uid]),
        });

        if (mounted) {
          setState(() {
            _friendRequestStatus = 'friends';
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'You are now friends with ${_userData?['username'] ?? 'user'}!'),
            backgroundColor: Colors.green,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to accept friend request. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _declineFriendRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId;
    if (currentUser == null || targetUserId == null) return;

    try {
      // Find the pending request
      final querySnapshot = await FirebaseFirestore.instance
          .collection('friendRequests')
          .where('senderId', isEqualTo: targetUserId)
          .where('receiverId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final requestId = querySnapshot.docs.first.id;
        // Delete the request document after processing
        await FirebaseFirestore.instance
            .collection('friendRequests')
            .doc(requestId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Friend request from ${_userData?['username'] ?? 'user'} declined.'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to decline friend request. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _cancelFriendRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId;
    if (currentUser == null || targetUserId == null) return;

    try {
      // Find the pending request sent by current user
      final querySnapshot = await FirebaseFirestore.instance
          .collection('friendRequests')
          .where('senderId', isEqualTo: currentUser.uid)
          .where('receiverId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final requestId = querySnapshot.docs.first.id;
        await FirebaseFirestore.instance
            .collection('friendRequests')
            .doc(requestId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Friend request to ${_userData?['username'] ?? 'user'} cancelled.'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to cancel friend request. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _removeFriend() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId;
    if (currentUser == null || targetUserId == null) return;

    final targetUsername = _userData?['username'] ?? 'this user';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade800,
        title:
            const Text('Remove Friend', style: TextStyle(color: Colors.white)),
        content: Text(
            'Are you sure you want to remove $targetUsername from your friends?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Remove from current user's friends list
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
        'friends': FieldValue.arrayRemove([targetUserId]),
      });
      // Remove from target user's friends list
      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUserId)
          .update({
        'friends': FieldValue.arrayRemove([currentUser.uid]),
      });

      // Optionally, delete any associated friend request documents if they exist
      final querySnapshot = await FirebaseFirestore.instance
          .collection('friendRequests')
          .where(Filter.or(
            Filter.and(
              Filter('senderId', isEqualTo: currentUser.uid),
              Filter('receiverId', isEqualTo: targetUserId),
            ),
            Filter.and(
              Filter('senderId', isEqualTo: targetUserId),
              Filter('receiverId', isEqualTo: currentUser.uid),
            ),
          ))
          .get();

      for (var doc in querySnapshot.docs) {
        await doc.reference.delete();
      }

      if (mounted) {
        setState(() {
          _friendRequestStatus = 'none';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Successfully removed $targetUsername as a friend.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to remove friend. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _reportUser() async {
    final reportData = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _ReportUserDialog(
        reportedUsername: _userData?['username'] ?? 'this user',
      ),
    );

    if (reportData == null || reportData['reason']!.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUserId = widget.userId;

    const recipient = "wimbliapp@gmail.com";
    final subject =
        "User Report: ${_userData?['username']} (ID: $targetUserId)";
    final body = """
    --- Wimbli User Report ---

    Reported User:
    - Username: ${_userData?['username']}
    - User ID: $targetUserId

    Reporting User:
    - Username: ${currentUser?.displayName}
    - User ID: ${currentUser?.uid}

    Reason for Report:
    - ${reportData['reason']}

    Additional Details:
    - ${reportData['details'] ?? "No additional details provided."}

    --------------------------------
    Please do not modify the user IDs above.
    Sent from the Wimbli app on ${DateTime.now().toUtc()}
    """;

    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: recipient,
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );

    try {
      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open email app.'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('An unexpected error occurred.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditProfilePage()),
    );
  }

  // --- SIMPLIFIED NAVIGATION: No need to await result anymore ---
  void _navigateToEventDetails(Event event) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventDetailsPage(event: event)),
    );
  }

  IconData _getIconForCategory(String categoryName) {
    // Find the category in the appCategories list, or use a default icon if not found.
    final category = appCategories.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => const AppCategory(
          name: 'Default', icon: Icons.event, color: Colors.grey),
    );
    return category.icon;
  }

  void _showFullImage(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white));
                    },
                    errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 50),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    final userBio = _userData?['bio'] as String? ?? 'No bio yet.';
    final userInterests = List<String>.from(_userData?['interests'] ?? []);
    final interestedCount =
        (_userData?['savedPosts'] as List<dynamic>? ?? []).length;
    final profilePictureUrl = _userData?['profilePicture'] as String?;
    final username = _userData?['username'] as String? ?? 'Wimbli User';

    Widget profileContent = SafeArea(
      bottom: false,
      child: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: widget.userId != null
                  ? IconButton(
                      icon:
                          const Icon(Icons.arrow_back_ios, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop())
                  : null,
              actions: [
                if (_isCurrentUserProfile)
                  IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsPage(
                              // The function we pass is now async
                              onBeforeSignOut: () async {
                                // Await each cancellation Future to complete
                                await _userSubscription?.cancel();
                                await _postsSubscription?.cancel();
                                await _interestedEventsSubscription?.cancel();
                                await _currentUserSubscription?.cancel();
                                await _currentUserSavedPostsSubscription
                                    ?.cancel();
                                await _targetUserFriendsSubscription?.cancel();
                                await _friendRequestStatusSubscription
                                    ?.cancel();
                              },
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                      ))
                else
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'report') {
                        _reportUser();
                      } else if (value == 'block') {
                        _toggleBlockUser();
                      }
                    },
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined),
                            SizedBox(width: 8),
                            Text('Report User'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'block',
                        child: Row(
                          children: [
                            const Icon(Icons.block),
                            const SizedBox(width: 8),
                            Text(_isBlocked ? 'Unblock User' : 'Block User'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    Hero(
                      tag:
                          'profile_pic_${widget.userId ?? FirebaseAuth.instance.currentUser?.uid}',
                      child: GestureDetector(
                        onTap: () {
                          if (profilePictureUrl != null) {
                            _showFullImage(profilePictureUrl);
                          }
                        },
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white24,
                          backgroundImage: profilePictureUrl != null
                              ? NetworkImage(profilePictureUrl)
                              : null, // Set to null if no URL
                          child: profilePictureUrl == null
                              ? Icon(
                                  // Display Icon if no URL
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white.withOpacity(0.7),
                                )
                              : null, // Display nothing here if there is an image
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(username,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(userBio,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.8))),
                    const SizedBox(height: 16),
                    if (_isCurrentUserProfile)
                      ElevatedButton.icon(
                        onPressed: _navigateToEditProfile,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Profile'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      )
                    else if (!_isBlocked) // Only show friend buttons if not blocked
                      _buildFriendActionButtons(),
                    const SizedBox(height: 24),
                    _buildStatsRow(interestedCount),
                    const SizedBox(height: 24),
                    // _buildInterestsSection(userInterests),
                    // const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildInterestsSection(userInterests),
            ),
            SliverPersistentHeader(
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.7),
                  indicatorColor: Colors.white,
                  indicatorWeight: 3.0,
                  tabs: const [
                    Tab(text: 'Interested'),
                    Tab(text: 'Posts'),
                    Tab(text: 'Friends'),
                  ],
                ),
              ),
              pinned: true,
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildEventList(_interestedEvents,
                "Doesn't have any saved events yet.", Icons.bookmark_border),
            _buildEventList(_myPosts, "Hasn't posted any events yet.",
                Icons.add_photo_alternate_outlined),
            _buildFriendsTab(),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: _isCurrentUserProfile
            ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue.shade200, Colors.purple.shade300],
                ),
              )
            : BoxDecoration(
                color: Colors.purple.shade300,
              ),
        child: profileContent,
      ),
    );
  }

  Widget _buildFriendsTab() {
    if (_isFriendsTabLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    if (_isCurrentUserProfile) {
      // On our own profile, show friend activity
      return _buildEventList(
        _friendActivityEvents,
        "Your friends haven't expressed interest in any events yet.",
        Icons.people_outline,
      );
    } else {
      // On someone else's profile, show their friend list
      if (_profileUserFriends.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.no_accounts_outlined,
                  size: 50, color: Colors.white.withOpacity(0.7)),
              const SizedBox(height: 16),
              Text("This user doesn't have any friends yet.",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 16)),
            ],
          ),
        );
      }
      return _buildFriendList();
    }
  }

  Widget _buildFriendList() {
    // Combine lists into sections for the ListView
    final List<Widget> listItems = [];

    if (_mutualFriends.isNotEmpty) {
      listItems.add(_buildSectionHeader('Mutual Friends'));
      listItems.addAll(
          _mutualFriends.map((friend) => _buildFriendTile(friend)).toList());
    }

    if (_profileUserFriends.isNotEmpty) {
      listItems.add(_buildSectionHeader('All Friends'));
      listItems.addAll(_profileUserFriends
          .map((friend) => _buildFriendTile(friend))
          .toList());
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 100),
      itemCount: listItems.length,
      itemBuilder: (context, index) {
        return listItems[index];
      },
    );
  }

  Widget _buildFriendTile(Map<String, dynamic> friend) {
    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfilePage(userId: friend['uid'])),
        );
      },
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: friend['profilePicture'] != null
            ? NetworkImage(friend['profilePicture']!)
            : null,
        child:
            friend['profilePicture'] == null ? const Icon(Icons.person) : null,
      ),
      title: Text(
        friend['username'] ?? 'Unknown',
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      trailing:
          const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildFriendActionButtons() {
    switch (_friendRequestStatus) {
      case 'none':
        return ElevatedButton.icon(
          onPressed: _sendFriendRequest,
          icon: const Icon(Icons.person_add, size: 16),
          label: const Text('Add Friend'),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.green.shade400,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        );
      case 'sent':
        return ElevatedButton.icon(
          onPressed: _cancelFriendRequest,
          icon: const Icon(Icons.send, size: 16),
          label: const Text('Request Sent'),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.orange.withOpacity(0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        );
      case 'received':
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _acceptFriendRequest,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Accept'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.green.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _declineFriendRequest,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Decline'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.red.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ],
        );
      case 'friends':
        return ElevatedButton.icon(
          onPressed: _removeFriend, // Call the new _removeFriend method
          icon: const Icon(Icons.person_remove, size: 16),
          label: const Text('Unfriend'), // Changed label to "Unfriend"
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.blueGrey.withOpacity(0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        );
      default:
        return const SizedBox
            .shrink(); // Hide button if status is unknown or self profile
    }
  }

  Widget _buildEventList(
      List<Event> events, String emptyMessage, IconData emptyIcon) {
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 50, color: Colors.white.withOpacity(0.7)),
            const SizedBox(height: 16),
            Text(emptyMessage,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: events.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: GestureDetector(
            onTap: () => _navigateToEventDetails(events[index]),
            child: _buildForYouEventCard(events[index]),
          ),
        );
      },
    );
  }

  Widget _buildStatsRow(int interestedCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(_postCount.toString(), 'Posts'),
        _buildStatItem(interestedCount.toString(), 'Interested'),
        // --- NEW: Display friend count ---
        _buildStatItem(_friendCount.toString(), 'Friends'),
      ],
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 4),
        Text(label,
            style:
                TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
      ],
    );
  }

  Widget _buildInterestsSection(List<String> interests) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 24.0), // Padding for the title
          child: Text('Interests',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
        const SizedBox(height: 12),
        if (interests.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 24.0), // Padding for the empty text
            child: Text('No interests added yet.',
                style: TextStyle(
                    color: Colors.white70, fontStyle: FontStyle.italic)),
          )
        else
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              itemCount: interests.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Chip(
                    label: Text(interests[index]),
                    backgroundColor: Colors.white.withOpacity(0.2),
                    labelStyle: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          30), // Customize the radius here
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildForYouEventCard(Event event) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
            child: Image.network(event.imageUrl,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                    width: 120,
                    height: 120,
                    color: Colors.white.withOpacity(0.2),
                    // --- This now uses the correct category icon ---
                    child: Icon(_getIconForCategory(event.category),
                        color: Colors.white.withOpacity(0.7), size: 40))),
          ),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  _buildEventInfoRow(Icons.location_on, event.location,
                      size: 14),
                  _buildEventInfoRow(Icons.access_time,
                      DateFormat('MMM d, h:mm a').format(event.date),
                      size: 14),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEventInfoRow(IconData icon, String text, {double size = 16}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: size),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style:
                  TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.purple.shade300.withOpacity(0.2),
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

class _ReportUserDialog extends StatefulWidget {
  final String reportedUsername;
  const _ReportUserDialog({required this.reportedUsername});

  @override
  State<_ReportUserDialog> createState() => _ReportUserDialogState();
}

class _ReportUserDialogState extends State<_ReportUserDialog> {
  String _selectedReason = '';
  final _detailsController = TextEditingController();
  final List<String> _reasons = [
    'Spam',
    'Inappropriate Profile Information',
    'Harassment or Hateful Speech',
    'Impersonation',
    'Other'
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade800,
      title: Text('Report ${widget.reportedUsername}',
          style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please select a reason for the report:',
                style: TextStyle(color: Colors.white70)),
            ..._reasons.map((reason) => RadioListTile<String>(
                  title:
                      Text(reason, style: const TextStyle(color: Colors.white)),
                  value: reason,
                  groupValue: _selectedReason,
                  activeColor: Colors.purple.shade300,
                  onChanged: (value) {
                    setState(() {
                      _selectedReason = value!;
                    });
                  },
                )),
            const SizedBox(height: 16),
            TextField(
              controller: _detailsController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Additional Details (Optional)',
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.purple.shade300),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple.shade400,
            disabledBackgroundColor: Colors.grey.shade700,
          ),
          onPressed: _selectedReason.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop({
                    'reason': _selectedReason,
                    'details': _detailsController.text,
                  });
                },
          child: const Text('Submit Report',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
