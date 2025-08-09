import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For lastSeen timestamp
import 'dart:async'; // For Timer
import 'package:url_launcher/url_launcher.dart'; // For launching email client
import 'package:wimbli/pages/main/profile_page.dart';

// Define a Message model
class Message {
  final String id;
  final String text;
  final String senderId;
  final DateTime timestamp;
  final String? senderName;
  final String? senderAvatar; // URL for sender's avatar
  final String? replyToMessageText;
  final String? replyToSenderName;
  final List<String> likedBy;
  final bool isEdited;
  final DateTime? editedAt;

  Message({
    required this.id,
    required this.text,
    required this.senderId,
    required this.timestamp,
    this.senderName,
    this.senderAvatar,
    this.replyToMessageText,
    this.replyToSenderName,
    this.likedBy = const [],
    this.isEdited = false,
    this.editedAt,
  });

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Message(
      id: doc.id,
      text: data['text'] ?? '',
      senderId: data['senderId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      senderName: data['senderName'],
      senderAvatar: data['senderAvatar'],
      replyToMessageText: data['replyToMessageText'],
      replyToSenderName: data['replyToSenderName'],
      likedBy: List<String>.from(data['likedBy'] ?? []),
      isEdited: data['isEdited'] ?? false,
      editedAt: (data['editedAt'] is Timestamp)
          ? (data['editedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class ChatPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChatPage({super.key, required this.groupId, required this.groupName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoadingMessages = true;
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _blockedUsersSubscription;
  List<String> _blockedUsers = [];
  Message? _replyingTo;
  Message? _editingMessage;
  String? _originalMessageText; // To store original text for editing
  bool _isSendingMessage = false; // To show loading on send button
  String? _groupCreatorId; // To store the ID of the group's creator
  String? _postCreatorId;

  // Firestore instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _fetchGroupData();
    _setupBlockedUsersStream();
    _setupMessagesStream();
    _scrollController.addListener(_scrollListener);
    // FIX: Add listener to update the send button's state on text change.
    _messageController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _messagesSubscription?.cancel();
    _blockedUsersSubscription?.cancel();
    super.dispose();
  }

  void _scrollListener() {
    // Optional: Implement logic to load older messages when scrolling up
  }

  Future<void> _fetchGroupData() async {
    try {
      final groupRef = _firestore.collection('groups').doc(widget.groupId);
      final groupDoc = await groupRef.get();

      if (groupDoc.exists && mounted) {
        final data = groupDoc.data();
        if (data == null) return; // Exit if data is unexpectedly null

        String? fetchedPostCreatorId = data['postCreatorId'];

        // --- NEW: More Robust Fallback for Old Groups ---
        if (fetchedPostCreatorId == null) {
          final postId = data['postId'];
          if (postId != null) {
            final postDoc =
                await _firestore.collection('posts').doc(postId).get();
            if (postDoc.exists) {
              // First, try to get the new 'postCreatorId' field.
              // If it's null, fall back to the original 'createdBy' field.
              fetchedPostCreatorId = postDoc.data()?['postCreatorId'] ??
                  postDoc.data()?['createdBy'];

              // If we found a creator ID (from either field), update the group doc.
              // This makes future loads faster and migrates the old data.
              if (fetchedPostCreatorId != null) {
                await groupRef.update({'postCreatorId': fetchedPostCreatorId});
              }
            }
          }
        }
        // --- End Fallback ---

        setState(() {
          _groupCreatorId = data['createdBy'];
          _postCreatorId = fetchedPostCreatorId;
        });
      }
    } catch (e) {
      print("Error fetching group data: $e");
    }
  }

  void _setupBlockedUsersStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return;
    }

    _blockedUsersSubscription?.cancel();
    _blockedUsersSubscription = _firestore
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

  void _navigateToUserProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfilePage(userId: userId)),
    );
  }

  void _setupMessagesStream() {
    _messagesSubscription?.cancel();

    // FIX: Add .orderBy('timestamp') back to the query. This is crucial for
    // reliable real-time updates from Firestore's stream.
    final messagesQuery = _firestore
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .orderBy('timestamp'); // <--- ADD THIS BACK

    _messagesSubscription = messagesQuery.snapshots().listen(
      (snapshot) async {
        // The client-side sort is no longer needed since Firestore provides sorted data.
        List<Message> fetchedMessages =
            snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList();

        if (mounted) {
          setState(() {
            _messages = fetchedMessages;
            _isLoadingMessages = false;
          });

          // The rest of your function remains the same...
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
          _updateLastSeenTimestamp();
        }
      },
      onError: (error) {
        print("ChatPage: Error fetching messages: $error");
        if (mounted) {
          setState(() {
            _isLoadingMessages = false;
          });
        }
      },
    );
  }

  Future<void> _updateLastSeenTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'lastSeen_${widget.groupId}', DateTime.now().toIso8601String());
    } catch (e) {
      print("Error updating last seen timestamp: $e");
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSendingMessage) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      // ... error handling
      return;
    }

    // Exit edit mode if active
    if (_editingMessage != null) {
      // Keep your existing edit logic
      setState(() {
        _isSendingMessage = true;
      });
      try {
        await _firestore
            .collection('groups')
            .doc(widget.groupId)
            .collection('messages')
            .doc(_editingMessage!.id)
            .update({
          'text': text,
          'text_lowercase': text.toLowerCase(),
          'isEdited': true,
          'editedAt': FieldValue.serverTimestamp(),
        });
        _cancelEdit();
      } catch (e) {
        // ... error handling
      } finally {
        if (mounted) {
          setState(() {
            _isSendingMessage = false;
          });
        }
      }
      return; // Important: return after handling the edit
    }

    // --- FIX: Optimistic UI for new messages ---

    // 1. Clear the input field and cancel any reply UI immediately.
    _messageController.clear();
    final pendingReplyTo = _replyingTo; // Keep a reference
    _cancelReply(); // This will call setState and update the UI

    // 2. Create a temporary message object to display instantly.
    // We use a temporary ID which will be replaced by the real one from Firestore.
    final tempMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      senderId: currentUser.uid,
      timestamp: DateTime.now(), // Use local time for now
      senderName: currentUser.displayName ?? 'Anonymous',
      senderAvatar: currentUser.photoURL,
      replyToMessageText: pendingReplyTo?.text,
      replyToSenderName: pendingReplyTo?.senderName,
    );

    // 3. Add the temporary message to the local list and scroll down.
    setState(() {
      _messages.add(tempMessage);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // 4. Send the actual message to Firebase in the background.
    try {
      final groupDoc =
          await _firestore.collection('groups').doc(widget.groupId).get();
      final groupMembers = List<String>.from(groupDoc.data()?['members'] ?? []);

      final messageData = {
        'text': text,
        'text_lowercase': text.toLowerCase(),
        'senderId': currentUser.uid,
        'senderName': currentUser.displayName ?? 'Anonymous',
        'senderAvatar': currentUser.photoURL,
        'timestamp': FieldValue.serverTimestamp(),
        'likedBy': [],
        'isEdited': false,
        'groupId': widget.groupId,
        'members': groupMembers,
        'createdBy': _groupCreatorId,
        if (pendingReplyTo != null) ...{
          'replyToMessageText': pendingReplyTo.text,
          'replyToSenderName': pendingReplyTo.senderName,
        },
      };

      DocumentReference newMessageRef = await _firestore
          .collection('groups')
          .doc(widget.groupId)
          .collection('messages')
          .add(messageData);

      await _firestore.collection('groups').doc(widget.groupId).update({
        'lastMessage': text,
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastMessageSenderId': currentUser.uid,
        'lastMessageId': newMessageRef.id,
      });

      // Note: We don't need to call setState here anymore.
      // The stream listener will handle the final state update.
    } catch (e) {
      print("Error sending message: $e");
      // Optional: Remove the temp message and show an error if sending fails
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == tempMessage.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  void _handleLikeMessage(Message message) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final messageRef = _firestore
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .doc(message.id);

    final isLiked = message.likedBy.contains(currentUser.uid);

    try {
      if (isLiked) {
        await messageRef.update({
          'likedBy': FieldValue.arrayRemove([currentUser.uid]),
        });
      } else {
        await messageRef.update({
          'likedBy': FieldValue.arrayUnion([currentUser.uid]),
        });
      }
    } catch (e) {
      print("Error liking message: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update like status.')),
      );
    }
  }

  Future<void> _handleDeleteMessage(Message message) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || message.senderId != currentUser.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only delete your own messages.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade800,
        title: const Text('Delete Message?',
            style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this message?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    final groupRef = _firestore.collection('groups').doc(widget.groupId);
    final messageRef = groupRef.collection('messages').doc(message.id);

    try {
      // Get the group doc to check if the deleted message is the last one.
      final groupDoc = await groupRef.get();
      final lastMessageId = groupDoc.data()?['lastMessageId'];

      // Delete the message document.
      await messageRef.delete();

      // If the message we just deleted was the group's "lastMessage", we must find a new one.
      if (lastMessageId == message.id) {
        // Query for the new latest message (the one before the one we deleted).
        final newLastMessageQuery = groupRef
            .collection('messages')
            .where('members', arrayContains: currentUser.uid)
            .orderBy('timestamp', descending: true)
            .limit(1);

        final newLastMessageSnapshot = await newLastMessageQuery.get();

        if (newLastMessageSnapshot.docs.isNotEmpty) {
          // If a new last message exists, update the group with its data.
          final newLastMessage =
              Message.fromFirestore(newLastMessageSnapshot.docs.first);
          await groupRef.update({
            'lastMessage': newLastMessage.text,
            'lastUpdated': newLastMessage.timestamp,
            'lastMessageSenderId': newLastMessage.senderId,
            'lastMessageId': newLastMessage.id,
          });
        } else {
          // If no messages are left, clear the last message fields in the group.
          await groupRef.update({
            'lastMessage': 'Chat started.',
            'lastUpdated': FieldValue.serverTimestamp(),
            'lastMessageSenderId': null,
            'lastMessageId': null,
          });
        }
      }
    } catch (e) {
      print("Error deleting message and updating group: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $e')),
        );
      }
    }
  }

  void _handleEditMessage(Message message) {
    setState(() {
      _editingMessage = message;
      _originalMessageText = message.text;
      _messageController.text = message.text;
      _replyingTo = null; // Exit reply mode if in edit mode
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _originalMessageText = null;
      _messageController.clear();
    });
  }

  void _handleReplyMessage(Message message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null; // Exit edit mode if in reply mode
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate.isAtSameMomentAs(today)) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate.isAtSameMomentAs(yesterday)) {
      return 'Yesterday';
    } else {
      return '${timestamp.month}/${timestamp.day}'; // e.g., 3/20
    }
  }

  void _showMessageOptions(Message message) {
    final currentUser = _auth.currentUser;
    final isSender = message.senderId == currentUser?.uid;

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
                  'Message Options',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white70),
                title: Text('Reply',
                    style: GoogleFonts.poppins(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _handleReplyMessage(message);
                },
              ),
              if (isSender) ...[
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white70),
                  title: Text('Edit',
                      style: GoogleFonts.poppins(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleEditMessage(message);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text('Delete',
                      style: GoogleFonts.poppins(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleDeleteMessage(message);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: Icon(
                    _blockedUsers.contains(message.senderId)
                        ? Icons.lock_open
                        : Icons.block,
                    color: Colors.white70,
                  ),
                  title: Text(
                    _blockedUsers.contains(message.senderId)
                        ? 'Unblock User'
                        : 'Block User',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _toggleBlockUser(
                        message.senderId, message.senderName ?? 'this user');
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.flag_outlined, color: Colors.white70),
                  title: Text('Report User',
                      style: GoogleFonts.poppins(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _reportUser(
                        message.senderId, message.senderName ?? 'this user');
                  },
                ),
              ],
              const SizedBox(height: 50),
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

    const recipient = "wimbliapp@gmail.com";
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

  void _showLikedBy(List<String> userIds) {
    if (userIds.isEmpty) return;

    // This Future fetches the detailed user data from Firestore.
    final Future<List<Map<String, dynamic>>> usersFuture = _firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: userIds)
        .get()
        .then((snapshot) => snapshot.docs.map((doc) {
              // We combine the document data with its ID for later use (e.g., navigation).
              return {'id': doc.id, ...doc.data()};
            }).toList());

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Required for custom border radius.
      isScrollControlled: true, // Allows the sheet to be dragged up.
      builder: (context) {
        // DraggableScrollableSheet provides a modern, resizable bottom sheet.
        return DraggableScrollableSheet(
          initialChildSize: 0.4, // Sheet starts at 40% of screen height.
          minChildSize: 0.2, // Can be dragged down to 20%.
          maxChildSize: 0.7, // Can be dragged up to 70%.
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A3D), // Matches the app's dark theme.
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // A small visual handle for the draggable sheet.
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // The requested "Liked by" title.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'Liked by',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // FutureBuilder handles the asynchronous loading of user data.
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: usersFuture,
                      builder: (context, snapshot) {
                        // Display a loading spinner while fetching data.
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: Colors.blueAccent),
                          );
                        }

                        // Display an error message if the fetch fails.
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Could not load users.',
                              style: GoogleFonts.poppins(color: Colors.white70),
                            ),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Center(
                            child: Text(
                              'This message has no likes.', // Fallback message.
                              style: GoogleFonts.poppins(color: Colors.white70),
                            ),
                          );
                        }

                        // If data is ready, build the list of users.
                        final users = snapshot.data!;

                        return ListView.builder(
                          controller:
                              scrollController, // Link to the draggable controller.
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final username =
                                user['username'] ?? 'Anonymous User';
                            final avatarUrl = user[
                                'profilePicture']; // Assumes field is 'photoURL'.
                            final userId = user['id'];

                            return ListTile(
                              // Displays the user's profile picture.
                              leading: CircleAvatar(
                                backgroundColor: Colors.white24,
                                backgroundImage: avatarUrl != null
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: avatarUrl == null
                                    ? const Icon(Icons.person,
                                        size: 20, color: Colors.white70)
                                    : null,
                              ),
                              title: Text(
                                username,
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                              // ADDITION: Makes each user tappable to view their profile.
                              onTap: () {
                                Navigator.pop(
                                    context); // Close the bottom sheet.
                                _navigateToUserProfile(
                                    userId); // Navigate to the profile page.
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Group options logic
  void _showGroupOptions() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final isCreator = currentUser.uid == _postCreatorId;

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
              if (isCreator)
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text('Delete Group',
                      style: GoogleFonts.poppins(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleDeleteGroup();
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text('Leave Group',
                      style: GoogleFonts.poppins(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleLeaveGroup();
                  },
                ),
              const SizedBox(height: 50),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleLeaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade800,
        title:
            const Text('Leave Group?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to leave this group chat?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      await _firestore.collection('groups').doc(widget.groupId).update({
        'members': FieldValue.arrayRemove([currentUser.uid]),
      });
      if (mounted) {
        Navigator.of(context).pop(); // Go back from chat page
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to leave group: $e')),
        );
      }
    }
  }

  Future<void> _handleDeleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade800,
        title:
            const Text('Delete Group?', style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will permanently delete the group and all its messages for everyone. This action cannot be undone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // NOTE: Deleting subcollections from the client is not recommended for production.
      // A Cloud Function is the proper way to handle this to ensure all data is removed.
      final groupRef = _firestore.collection('groups').doc(widget.groupId);
      final messages = await groupRef.collection('messages').get();

      WriteBatch batch = _firestore.batch();
      for (var doc in messages.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(groupRef);

      await batch.commit();

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete group: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C), // Dark background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.groupName,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _showGroupOptions, // MODIFICATION: Call the new function
          ),
        ],
      ),
      // MODIFICATION: Wrap body in SafeArea to handle notches and home bars.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoadingMessages
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Colors.blueAccent),
                    )
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.message_outlined,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 60),
                              const SizedBox(height: 15),
                              Text(
                                'No messages yet. Start the conversation!',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isSender =
                                message.senderId == currentUser?.uid;

                            if (_blockedUsers.contains(message.senderId) &&
                                !isSender) {
                              return Container();
                            }

                            return _buildMessageBubble(message, isSender);
                          },
                        ),
            ),
            if (_replyingTo != null || _editingMessage != null)
              _buildPreviewArea(context),
            _buildInputArea(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewArea(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _editingMessage != null
                      ? 'Editing Message'
                      : 'Replying to ${_replyingTo!.senderName ?? 'User'}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                Text(
                  _editingMessage != null
                      ? (_originalMessageText ?? '')
                      : (_replyingTo!.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () {
              _editingMessage != null ? _cancelEdit() : _cancelReply();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8.0,
        left: 8.0,
        right: 8.0,
        top: 8.0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(25),
                // border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: TextField(
                controller: _messageController,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                maxLines: 5,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: _editingMessage != null
                      ? 'Edit your message...'
                      : 'Type your message...',
                  hintStyle:
                      GoogleFonts.poppins(color: Colors.white.withOpacity(0.6)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: _isSendingMessage ? 48 : 52,
            height: _isSendingMessage ? 48 : 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors:
                    _messageController.text.trim().isEmpty && !_isSendingMessage
                        ? [Colors.grey.shade700, Colors.grey.shade600]
                        : [Colors.blue.shade300, Colors.purple.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow:
                  _messageController.text.trim().isEmpty && !_isSendingMessage
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.purple.shade400.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap:
                    _messageController.text.trim().isEmpty && !_isSendingMessage
                        ? null
                        : _sendMessage,
                child: Center(
                  child: _isSendingMessage
                      ? const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2,
                        )
                      : Icon(
                          _editingMessage != null ? Icons.check : Icons.send,
                          color: Colors.white,
                          size: _editingMessage != null ? 24 : 20,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isSender) {
    final bubbleColor =
        isSender ? Colors.purple.shade400 : Colors.grey.shade700;
    const textColor = Colors.white;
    final timestampColor = Colors.white.withOpacity(0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment:
            isSender ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSender) ...[
            GestureDetector(
              onTap: () => _navigateToUserProfile(message.senderId),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                backgroundImage: message.senderAvatar != null
                    ? NetworkImage(message.senderAvatar!)
                    : null,
                child: message.senderAvatar == null
                    ? const Icon(Icons.person, size: 16, color: Colors.white70)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment:
                isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isSender)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0, bottom: 2.0),
                  child: Text(
                    message.senderName ?? 'Unknown User',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ),
              Stack(
                clipBehavior: Clip.none, // Allow the counter to overflow
                children: [
                  // Layer 1: The message bubble
                  GestureDetector(
                    onDoubleTap: () => _handleLikeMessage(message),
                    onLongPress: () => _showMessageOptions(message),
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isSender
                              ? const Radius.circular(16)
                              : const Radius.circular(4),
                          bottomRight: isSender
                              ? const Radius.circular(4)
                              : const Radius.circular(16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.replyToMessageText != null)
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(bottom: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(
                                    left: BorderSide(
                                        color: Colors.blue.shade300, width: 3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.replyToSenderName ?? 'Replied User',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade300,
                                    ),
                                  ),
                                  Text(
                                    message.replyToMessageText!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: textColor.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            message.text,
                            style: GoogleFonts.poppins(
                                color: textColor, fontSize: 15),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // The like counter has been removed from here.
                              Text(
                                '${message.isEdited ? 'Edited ' : ''}${_formatTimestamp(message.timestamp)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: timestampColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Layer 2: The positioned heart icon and counter
                  if (message.likedBy.isNotEmpty)
                    Positioned(
                        bottom: -10,
                        right: isSender ? 4 : null,
                        left: isSender ? null : 4,
                        child: GestureDetector(
                          onTap: () => _showLikedBy(message.likedBy),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFF2A2A3D),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.black.withOpacity(0.2),
                                    width: 1)),
                            child: Row(
                              children: [
                                Icon(Icons.favorite,
                                    color: Colors.red.shade400, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  message.likedBy.length.toString(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                ],
              ),
            ],
          ),
        ],
      ),
    );
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
