import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:wimbli/models/event_model.dart';
import 'package:wimbli/pages/create/create_event_page.dart';
import 'dart:ui';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wimbli/pages/main/profile_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:device_calendar/device_calendar.dart' as device_calendar;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:wimbli/pages/main/chat_page.dart'; // Import the ChatPage

class EventDetailsPage extends StatefulWidget {
  final Event event;

  const EventDetailsPage({super.key, required this.event});

  @override
  State<EventDetailsPage> createState() => _EventDetailsPageState();
}

class _EventDetailsPageState extends State<EventDetailsPage> {
  // --- REAL-TIME STATE MANAGEMENT ---
  late Event _currentEvent;
  bool _isLoading = true;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _userSubscription;
  List<Map<String, dynamic>> _interestedUsers = [];
  bool _isFetchingInterestedUsers = true;

  final currentUser = FirebaseAuth.instance.currentUser;
  final device_calendar.DeviceCalendarPlugin _deviceCalendarPlugin =
      device_calendar.DeviceCalendarPlugin();
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance; // Firestore instance

  @override
  void initState() {
    super.initState();
    // Initialize with the data passed in, but immediately start listening for live updates.
    _currentEvent = widget.event;
    _setupStreams();
    tz.initializeTimeZones();
  }

  @override
  void dispose() {
    // Cancel the streams to prevent memory leaks
    _eventSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    // 1. Listen for changes to the event document itself (e.g., title, interestedCount)
    _eventSubscription = _firestore
        .collection('posts')
        .doc(widget.event.id)
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists) {
        // Create a new event object from the latest data
        final newEventData = Event.fromFirestore(snapshot);
        // IMPORTANT: Preserve the current 'isInterested' status, which is managed by the other stream.
        newEventData.isInterested = _currentEvent.isInterested;
        setState(() {
          _currentEvent = newEventData;
          _isLoading = false;
        });

        _fetchInterestedUsers();
      }
    });

    // 2. Listen for changes to the current user's saved posts to update the star icon
    if (currentUser != null) {
      _userSubscription = _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .snapshots()
          .listen((snapshot) {
        if (mounted && snapshot.exists) {
          final savedPostIds =
              List<String>.from(snapshot.data()?['savedPosts'] ?? []);
          // This is the single source of truth for whether the star should be filled
          final isNowInterested = savedPostIds.contains(widget.event.id);
          // Only update the state if it has actually changed to prevent unnecessary rebuilds
          if (_currentEvent.isInterested != isNowInterested) {
            setState(() {
              _currentEvent.isInterested = isNowInterested;
            });
          }
        }
      });
    } else {
      // If there's no user, we can't be interested in anything.
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onMenuSelection(String value) {
    if (value == 'edit') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateEventPage(
            isPrivate: _currentEvent.isPrivate,
            eventToEdit: _currentEvent,
          ),
        ),
      );
    } else if (value == 'delete') {
      _confirmDelete();
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade800,
        title:
            const Text('Delete Event?', style: TextStyle(color: Colors.white)),
        content: const Text('This action cannot be undone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            onPressed: _deleteEvent,
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEvent() async {
    try {
      Navigator.of(context).pop(); // Pop the dialog
      await _firestore.collection('posts').doc(_currentEvent.id).delete();
      if (mounted) {
        Navigator.of(context).pop(); // Pop the details page
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Event deleted successfully'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to delete event: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _fetchInterestedUsers() async {
    if (!mounted) return;
    setState(() {
      _isFetchingInterestedUsers = true;
    });

    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('savedPosts', arrayContains: _currentEvent.id)
          .limit(10) // Limit to 10 to keep the UI clean and reads low
          .get();

      final users = querySnapshot.docs.map((doc) {
        return {
          'uid': doc.id,
          'username': doc.data()['username'] ?? 'Wimbli User',
          'profilePicture': doc.data()['profilePicture'],
        };
      }).toList();

      if (mounted) {
        setState(() {
          _interestedUsers = users;
          _isFetchingInterestedUsers = false;
        });
      }
    } catch (e) {
      print("Error fetching interested users: $e");
      if (mounted) {
        setState(() {
          _isFetchingInterestedUsers = false;
        });
      }
    }
  }

  Future<void> _shareEvent() async {
    const String appDomain = 'https://wimbli.app';
    final String eventUrl = '$appDomain/event/${_currentEvent.id}';
    final String shareMessage =
        'Check out this event on Wimbli!\n\n${_currentEvent.title}\n$eventUrl';
    await Share.share(
      shareMessage,
      subject: 'Event: ${_currentEvent.title}',
    );
  }

  Future<void> _toggleSave() async {
    if (currentUser == null) return;

    final bool isSaving = !_currentEvent.isInterested;

    try {
      final batch = _firestore.batch();
      final userDocRef = _firestore.collection('users').doc(currentUser!.uid);
      final postDocRef = _firestore.collection('posts').doc(_currentEvent.id);

      if (isSaving) {
        batch.update(userDocRef, {
          'savedPosts': FieldValue.arrayUnion([_currentEvent.id])
        });
        batch.update(postDocRef, {'interestedCount': FieldValue.increment(1)});
      } else {
        batch.update(userDocRef, {
          'savedPosts': FieldValue.arrayRemove([_currentEvent.id])
        });
        batch.update(postDocRef, {'interestedCount': FieldValue.increment(-1)});
      }
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not update status. Please try again.')),
        );
      }
    }
  }

  Future<void> _addToCalendar() async {
    // 1. Request permissions
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
      permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      if (!permissionsGranted.isSuccess ||
          !(permissionsGranted.data ?? false)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Calendar permissions are required to add events.')),
          );
        }
        return;
      }
    }

    // 2. Get available calendars
    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    if (!calendarsResult.isSuccess || (calendarsResult.data?.isEmpty ?? true)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not find any calendars on the device.')),
        );
      }
      return;
    }

    // 3. Find a writable calendar
    final calendar = calendarsResult.data!.firstWhere(
      (cal) => cal.isReadOnly == false,
      orElse: () => calendarsResult.data!.first,
    );

    // 4. Create the event object for the device_calendar package
    final eventToCreate = device_calendar.Event(
      calendar.id,
      title: _currentEvent.title,
      description: _currentEvent.description,
      location: _currentEvent.location,
      start: tz.TZDateTime.from(_currentEvent.date, tz.local),
      end: tz.TZDateTime.from(
          _currentEvent.date.add(const Duration(hours: 1)), tz.local),
    );

    // 5. Add the event to the calendar
    final createEventResult =
        await _deviceCalendarPlugin.createOrUpdateEvent(eventToCreate);

    if (mounted) {
      if (createEventResult?.isSuccess ?? false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event added to your calendar successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add event to calendar.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleJoinChat() async {
    final user = currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to join chat.')),
        );
      }
      return;
    }

    final String groupId = _currentEvent.id; // Use event ID as group ID
    final String groupName =
        _currentEvent.title; // Use event title as group name

    try {
      final groupDocRef = _firestore.collection('groups').doc(groupId);
      final groupSnapshot = await groupDocRef.get();

      if (!groupSnapshot.exists) {
        // Group does not exist, create it
        await groupDocRef.set({
          'postId': _currentEvent.id, // Link group to the event post
          'title': groupName,
          'createdAt': FieldValue.serverTimestamp(),
          'members': [user.uid], // Add current user as the first member
          'createdBy': _currentEvent.createdBy, // Store event creator
          'lastMessage': 'Group created for ${_currentEvent.title}',
          'lastUpdated': FieldValue.serverTimestamp(),
          'lastMessageSenderId': user.uid,
          'isPrivate': _currentEvent.isPrivate,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New chat group created!')),
          );
        }
      } else {
        // Group exists, join it by adding user to members array if not already present
        final List<String> currentMembers =
            List<String>.from(groupSnapshot.data()?['members'] ?? []);
        if (!currentMembers.contains(user.uid)) {
          await groupDocRef.update({
            'members': FieldValue.arrayUnion([user.uid]),
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Joined existing chat group!')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are already in this chat.')),
            );
          }
        }
      }

      // Navigate to the Chat screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              groupId: groupId,
              groupName: groupName,
            ),
          ),
        );
      }
    } catch (e) {
      print("Error joining or creating chat: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join chat: $e')),
        );
      }
    }
  }

  void _navigateToUserProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfilePage(userId: userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue.shade200, Colors.purple.shade300],
                ),
              ),
              child: CustomScrollView(
                slivers: [
                  _buildSliverAppBar(context),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEventInfo(context),
                          const SizedBox(height: 32),
                          _buildInterestedUsersList(),
                          const Text(
                            'About this event',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _currentEvent.description,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    final isCreator = currentUser?.uid == _currentEvent.createdBy;

    return SliverAppBar(
      expandedHeight: 350.0,
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      stretch: true,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (_currentEvent.imageUrl.isNotEmpty)
                  Image.network(
                    _currentEvent.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.image_not_supported,
                          color: Colors.white54, size: 50),
                    ),
                  )
                else
                  Container(
                    color: Colors.grey.shade800,
                    child: const Icon(Icons.image_not_supported,
                        color: Colors.white54, size: 50),
                  ),
                Container(color: Colors.black.withOpacity(0.2)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                      stops: [0.4, 1.0],
                    ),
                  ),
                ),
              ],
            ),
            title: Text(
              _currentEvent.title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            titlePadding: const EdgeInsets.only(left: 60, bottom: 16),
          ),
        ),
      ),
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (isCreator)
          PopupMenuButton<String>(
            onSelected: _onMenuSelection,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: Colors.grey.shade800,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit',
                child:
                    Text('Edit Event', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child:
                    Text('Delete Event', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildInterestedUsersList() {
    if (_isFetchingInterestedUsers || _interestedUsers.isEmpty) {
      // Return an empty container if loading or no one is interested
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Who\'s Interested',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                NumberFormat.compact().format(_currentEvent.interestedCount),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _interestedUsers.length,
            itemBuilder: (context, index) {
              final user = _interestedUsers[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: GestureDetector(
                  onTap: () => _navigateToUserProfile(user['uid']),
                  child: CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.white24,
                    backgroundImage: user['profilePicture'] != null
                        ? NetworkImage(user['profilePicture']!)
                        : null,
                    child: user['profilePicture'] == null
                        ? const Icon(Icons.person, color: Colors.white70)
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildEventInfo(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _navigateToUserProfile(_currentEvent.createdBy),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: _currentEvent.creatorProfilePic != null
                          ? NetworkImage(_currentEvent.creatorProfilePic!)
                          : null,
                      backgroundColor: Colors.white24,
                      child: _currentEvent.creatorProfilePic == null
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Created by',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12),
                          ),
                          Text(
                            _currentEvent.creatorUsername,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: _shareEvent,
                  child: _buildActionIcon(Icons.share_outlined),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _toggleSave,
                  child: _buildActionIcon(
                    _currentEvent.isInterested
                        ? Icons.star
                        : Icons.star_border_outlined,
                    label: _currentEvent.interestedCount.toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(color: Colors.white30),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              _buildInfoRow(Icons.calendar_today_outlined,
                  DateFormat('EEEE, MMMM d').format(_currentEvent.date)),
              const SizedBox(height: 20),
              _buildInfoRow(Icons.access_time_outlined,
                  DateFormat('h:mm a').format(_currentEvent.date)),
              const SizedBox(height: 20),
              _buildInfoRow(Icons.timelapse_outlined, _currentEvent.duration),
              const SizedBox(height: 20),
              _buildInfoRow(Icons.location_on_outlined, _currentEvent.location),
              const SizedBox(height: 20),
              _buildInfoRow(Icons.category_outlined, _currentEvent.category),
              const SizedBox(height: 20),
              _buildInfoRow(
                  Icons.attach_money_outlined,
                  _currentEvent.fee > 0
                      ? _currentEvent.fee.toStringAsFixed(2)
                      : 'Free'),
              const SizedBox(height: 20),
              const Divider(color: Colors.white30),
              const SizedBox(height: 20),
              _buildCalendarButton(),
              const SizedBox(height: 10), // Add spacing between buttons
              _buildJoinChatButton(), // New Join Chat Button
            ],
          ),
        )
      ],
    );
  }

  Widget _buildCalendarButton() {
    return GestureDetector(
      onTap: _addToCalendar,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'Add to Calendar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinChatButton() {
    return GestureDetector(
      onTap: _handleJoinChat,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade300, Colors.purple.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.shade400.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'Join Chat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, {String? label}) {
    final iconColor =
        icon == Icons.star ? Colors.yellow.shade600 : Colors.white;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
          ),
        ),
        Opacity(
          opacity: label != null ? 1.0 : 0.0,
          child: Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              label ?? '0',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 22),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
