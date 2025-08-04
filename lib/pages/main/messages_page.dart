import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For local storage (lastSeen)
import 'dart:async';
import 'package:url_launcher/url_launcher.dart'; // For launching email client
import 'package:wimbli/pages/main/chat_page.dart'; // Adjust this import based on your project structure

final StreamController<bool> unreadMessagesStreamController =
    StreamController<bool>.broadcast();

// Define a Group model similar to your TypeScript Group type
// You might want to put this in a separate file like `lib/models/group_model.dart`
// For now, I'll define it here for completeness.
class Group {
  final String id;
  final String title;
  final List<String> members;
  final String? lastMessage;
  final DateTime? lastUpdated;
  final String? lastMessageSenderId;
  final bool isPrivate;
  bool isUnread; // This can be mutable as it's a UI state

  Group({
    required this.id,
    required this.title,
    required this.members,
    this.lastMessage,
    this.lastUpdated,
    this.lastMessageSenderId,
    required this.isPrivate,
    this.isUnread = false, // Default to false
  });

  // Factory constructor to create a Group from a Firestore DocumentSnapshot
  factory Group.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final bool isPrivateChat = data['isPrivate'] ?? false;

    return Group(
      id: doc.id,
      title: data['title'] ?? 'Untitled Group',
      members: List<String>.from(data['members'] ?? []),
      lastMessage: data['lastMessage'] ?? '',
      lastUpdated: (data['lastUpdated'] is Timestamp)
          ? (data['lastUpdated'] as Timestamp).toDate()
          : null,
      lastMessageSenderId: data['lastMessageSenderId'],
      isPrivate: isPrivateChat,
      isUnread:
          false, // Will be determined after fetching from SharedPreferences
    );
  }
}

class MessagesPage extends StatefulWidget {
  final VoidCallback onNavigateToHome;

  const MessagesPage({super.key, required this.onNavigateToHome});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Group> _publicGroups = [];
  List<Group> _privateGroups = [];

  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  StreamSubscription? _groupsSubscription;
  StreamSubscription? _blockedUsersSubscription;
  List<String> _blockedUsers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeMessages();
    _searchController.addListener(_onSearchChanged);
    _setupBlockedUsersStream(); // Setup stream for blocked users
  }

  @override
  void dispose() {
    _tabController.dispose();
    _groupsSubscription?.cancel();
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _blockedUsersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeMessages() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _publicGroups = [];
          _privateGroups = [];
        });
      }
      print("MessagesPage: No user logged in.");
      return;
    }
    _setupGroupsStream(user.uid);
  }

  void _setupBlockedUsersStream() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    _blockedUsersSubscription?.cancel();
    _blockedUsersSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .listen((docSnap) {
      if (docSnap.exists) {
        if (mounted) {
          setState(() {
            _blockedUsers =
                List<String>.from(docSnap.data()?['blockedUsers'] ?? []);
          });
        }
      }
    });
  }

  void _setupGroupsStream(String currentUserId) {
    _groupsSubscription?.cancel(); // Cancel previous subscription if any

    // Query groups where the current user is a member
    final groupsQuery = FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: currentUserId)
        .orderBy('lastUpdated', descending: true);

    _groupsSubscription = groupsQuery.snapshots().listen(
      (snapshot) async {
        print(
            "MessagesPage: Snapshot received for user $currentUserId. Size: ${snapshot.size}");
        List<Group> allFetchedGroups = [];
        for (var docSnap in snapshot.docs) {
          Group group = Group.fromFirestore(docSnap);

          group.isUnread = await _isGroupUnread(group, currentUserId);
          allFetchedGroups.add(group);
        }

        // Check if there's at least one unread group
        final bool hasUnread = allFetchedGroups.any((g) => g.isUnread);
        // Add the status to the global stream
        if (!unreadMessagesStreamController.isClosed) {
          unreadMessagesStreamController.add(hasUnread);
        }

        if (mounted) {
          setState(() {
            // Separate the groups into public and private lists
            _publicGroups =
                allFetchedGroups.where((g) => !g.isPrivate).toList();
            _privateGroups =
                allFetchedGroups.where((g) => g.isPrivate).toList();
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        print("MessagesPage: Error on groups listener: $error");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _publicGroups = [];
            _privateGroups = [];
          });
          // Consider showing a SnackBar or AlertDialog for the user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading messages: $error')),
          );
        }
      },
    );
  }

  // Helper function for unread status to keep the stream clean
  Future<bool> _isGroupUnread(Group group, String currentUserId) async {
    bool isUnread = false;
    final lastMessageWasByCurrentUser =
        group.lastMessageSenderId == currentUserId;

    if (!lastMessageWasByCurrentUser && group.lastUpdated != null) {
      final prefs = await SharedPreferences.getInstance();
      final lastSeenKey = 'lastSeen_${group.id}';
      final lastSeenStr = prefs.getString(lastSeenKey);

      if (lastSeenStr != null) {
        final lastSeenDate = DateTime.tryParse(lastSeenStr);
        isUnread = lastSeenDate != null
            ? group.lastUpdated!.isAfter(lastSeenDate)
            : true;
      } else {
        isUnread = true;
      }
    }
    return isUnread;
  }

  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          // Trigger rebuild to apply filter
        });
      }
    });
  }

  // This method now filters BOTH lists
  List<Group> _getFilteredGroups(List<Group> sourceList) {
    if (_searchController.text.isEmpty) {
      return sourceList;
    }
    final searchTerm = _searchController.text.toLowerCase();
    return sourceList.where((group) {
      return group.title.toLowerCase().contains(searchTerm) ||
          (group.lastMessage?.toLowerCase().contains(searchTerm) ?? false);
    }).toList();
  }

  String _formatDate(DateTime? dateInput) {
    if (dateInput == null) return "";

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final date = DateTime(dateInput.year, dateInput.month, dateInput.day);

    if (date.isAtSameMomentAs(today)) {
      return '${dateInput.hour.toString().padLeft(2, '0')}:${dateInput.minute.toString().padLeft(2, '0')}';
    } else if (date.isAtSameMomentAs(yesterday)) {
      return "Yesterday";
    } else if (dateInput.year == now.year) {
      return '${dateInput.month}/${dateInput.day}'; // e.g., 3/20
    } else {
      return '${dateInput.month}/${dateInput.day}/${dateInput.year % 100}'; // e.g., 3/20/24
    }
  }

  Future<void> _handleOpenChat(Group group) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'lastSeen_${group.id}', DateTime.now().toIso8601String());

      // Optimistically update UI
      if (mounted) {
        setState(() {
          // Simply mark the group as read. Do NOT re-sort the list here.
          // The Firestore listener is the only thing that should control the order.
          group.isUnread = false;
        });
        // You might also want to trigger a global unread status update here

        // After marking one as read, re-check if any others are unread
        final bool stillHasUnread = _publicGroups.any((g) => g.isUnread) ||
            _privateGroups.any((g) => g.isUnread);
        if (!unreadMessagesStreamController.isClosed) {
          unreadMessagesStreamController.add(stillHasUnread);
        }
      }

      // Navigate to chat screen using the ChatPage widget directly
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            groupId: group.id,
            groupName: group.title,
          ),
        ),
      );
    } catch (error) {
      print("Error updating lastSeen or navigating: $error");
      // Still navigate even if SharedPreferences fails
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            groupId: group.id,
            groupName: group.title,
          ),
        ),
      );
    }
  }

  // --- New: Show options for a message (block/report user) ---
  void _showMessageOptions(String senderId, String senderName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Options for $senderName',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  _blockedUsers.contains(senderId)
                      ? Icons.lock_open
                      : Icons.block,
                  color: Colors.white70,
                ),
                title: Text(
                  _blockedUsers.contains(senderId)
                      ? 'Unblock User'
                      : 'Block User',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context); // Close bottom sheet
                  _toggleBlockUser(senderId, senderName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.white70),
                title: Text(
                  'Report User',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _reportUser(senderId, senderName);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleBlockUser(
      String targetUserId, String targetUsername) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final isCurrentlyBlocked = _blockedUsers.contains(targetUserId);

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

  Future<void> _reportUser(
      String reportedUserId, String reportedUsername) async {
    final reportData = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _ReportUserDialog(
        reportedUsername: reportedUsername,
      ),
    );

    if (reportData == null || reportData['reason']!.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;

    const recipient = "wimbliapp@gmail.com"; // Your app's support email
    final subject = "User Report: $reportedUsername (ID: $reportedUserId)";
    final body = """
    --- Wimbli User Report ---

    Reported User:
    - Username: $reportedUsername
    - User ID: $reportedUserId

    Reporting User:
    - Username: ${currentUser?.displayName ?? 'Anonymous'}
    - User ID: ${currentUser?.uid ?? 'N/A'}

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

  Widget _buildGroupList(
      List<Group> groups, String emptyTitle, String emptySubtitle) {
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.message_outlined,
                color: Colors.white.withOpacity(0.7), size: 50),
            const SizedBox(height: 15),
            Text(emptyTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 16, color: Colors.white.withOpacity(0.7))),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: widget.onNavigateToHome,
              child: Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade300,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 160),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        // (Your existing logic for checking blocked users can go here)
        return Column(
          children: [
            _buildMessageTile(
                group), // Your existing tile builder works perfectly
            if (index < groups.length - 1)
              Divider(
                  color: Colors.white.withOpacity(0.1),
                  height: 1,
                  indent: 16,
                  endIndent: 16),
          ],
        );
      },
    );
  }

  Widget _buildMessageTile(Group group) {
    // Determine if the group's last message sender is blocked
    final currentUser = FirebaseAuth.instance.currentUser;
    final isLastMessageSenderBlocked = group.lastMessageSenderId != null &&
        _blockedUsers.contains(group.lastMessageSenderId) &&
        group.lastMessageSenderId !=
            currentUser?.uid; // Don't hide your own messages

    if (isLastMessageSenderBlocked) {
      return Container(); // Hide the message tile if the sender is blocked
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: GestureDetector(
        onLongPress: () {
          // Only show options if it's not the current user's message
          if (group.lastMessageSenderId != null &&
              group.lastMessageSenderId != currentUser?.uid) {
            _showMessageOptions(group.lastMessageSenderId!,
                group.title); // Using group title as sender name for simplicity
          }
        },
        child: CircleAvatar(
          radius: 28,
          // Using a generic group icon as in TypeScript, or you can use a placeholder image
          backgroundColor: group.isUnread
              ? Colors.blue.shade300.withOpacity(0.5)
              : Colors.white24,
          child: Icon(Icons.group, color: Colors.white70, size: 30),
          // If you want to use network images for avatars, you'd need a field in Group model
          // backgroundImage: NetworkImage(group.senderAvatarUrl),
        ),
      ),
      title: Text(
        group.title,
        style: GoogleFonts.poppins(
          fontWeight: group.isUnread ? FontWeight.bold : FontWeight.normal,
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        group.lastMessage ?? 'Start chatting!',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
          color: group.isUnread
              ? Colors.white.withOpacity(0.9)
              : Colors.white.withOpacity(0.8),
          fontWeight: group.isUnread ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatDate(group.lastUpdated),
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          if (group.isUnread)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.blue.shade300, // Unread dot color
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      onTap: () => _handleOpenChat(group),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                title: Text(
                  'Messages',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                floating: true,
                pinned: true,
                bottom: TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.7),
                  indicatorColor: Colors.white,
                  indicatorWeight: 3.0,
                  tabs: const [
                    Tab(text: 'Public'),
                    Tab(text: 'Private'),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: TextField(
                    controller: _searchController,
                    enableSuggestions: false,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search messages...',
                      hintStyle:
                          TextStyle(color: Colors.white.withOpacity(0.7)),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white70),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: Colors.white70),
                              onPressed: () {
                                _searchController.clear();
                                setState(
                                    () {}); // Trigger rebuild to clear filter
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide:
                            BorderSide(color: Colors.white.withOpacity(0.5)),
                      ),
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child:
                        CircularProgressIndicator(color: Colors.blue.shade300),
                  ),
                )
              else
                SliverFillRemaining(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Pass the filtered public list
                      _buildGroupList(
                          _getFilteredGroups(_publicGroups),
                          "No public chats found.",
                          "Join public event chats to see them here."),
                      // Pass the filtered private list
                      _buildGroupList(
                          _getFilteredGroups(_privateGroups),
                          "No private chats found.",
                          "Join private event chats to see them here."),
                    ],
                  ),
                ),
            ],
          ),
        ));
  }
}

// Re-using the _ReportUserDialog from profile_page.dart
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
