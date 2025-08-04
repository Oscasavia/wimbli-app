import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wimbli/models/event_model.dart';
// import 'package:wimbli/models/search_category_model.dart';
import 'package:wimbli/pages/main/chat_page.dart';
import 'package:wimbli/pages/main/event_details_page.dart';
import 'package:wimbli/pages/main/profile_page.dart';
import 'package:wimbli/models/app_category.dart';
import 'package:wimbli/constants/app_data.dart';
// import 'package:wimbli/pages/main/home_page.dart';
// import 'package:wimbli/widgets/event_card.dart';

// --- Data Models ---
// These models are used to structure the search results.
// Ideally, they would be in their own files, but are included here for completeness.

class AppUser {
  final String uid;
  final String username;
  final String? profilePicture;

  AppUser({required this.uid, required this.username, this.profilePicture});

  factory AppUser.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      username: data['username'] ?? 'Unknown User',
      profilePicture: data['profilePicture'],
    );
  }
}

class MessageSearchResult {
  final String messageId;
  final String text;
  final String senderId;
  final String? senderName;
  final String groupId;
  final String groupTitle;
  final DateTime timestamp;

  MessageSearchResult({
    required this.messageId,
    required this.text,
    required this.senderId,
    this.senderName,
    required this.groupId,
    required this.groupTitle,
    required this.timestamp,
  });
}

// --- Main Page Widget ---

class SearchPage extends StatefulWidget {
  final void Function(String category) onCategoryTapped;

  // Update the constructor
  const SearchPage({super.key, required this.onCategoryTapped});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;
  Timer? _searchDebounce;

  List<String> _blockedUsers = [];
  StreamSubscription? _blockedUsersSubscription;

  // --- State Management ---
  bool _isSearching = false;
  String _currentQuery = '';

  // Search Results
  List<Event> _eventResults = [];
  List<AppUser> _userResults = [];
  List<MessageSearchResult> _messageResults = [];

  // Initial Page Content
  List<String> _recentSearches = [];
  final List<AppCategory> _categories = appCategories;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(_onSearchChanged);
    _loadRecentSearches();
    _setupBlockedUsersStream();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.dispose();
    _blockedUsersSubscription?.cancel();
    super.dispose();
  }

  // --- Data Loading and Persistence ---

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _recentSearches = prefs.getStringList('recentSearches') ?? [];
        });
      }
    } catch (e) {
      debugPrint("Failed to load recent searches: $e");
    }
  }

  Future<void> _setupBlockedUsersStream() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _blockedUsersSubscription?.cancel();
    _blockedUsersSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists) {
        final data = snapshot.data();
        setState(() {
          _blockedUsers = List<String>.from(data?['blockedUsers'] ?? []);
        });
      }
    });
  }

  Future<void> _saveSearchQuery(String query) async {
    if (query.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> searches = prefs.getStringList('recentSearches') ?? [];

    // Remove existing entry to move it to the top
    searches.removeWhere((s) => s.toLowerCase() == query.toLowerCase());
    // Add to the beginning
    searches.insert(0, query);
    // Keep only the last 10 searches
    if (searches.length > 10) {
      searches = searches.sublist(0, 10);
    }

    await prefs.setStringList('recentSearches', searches);
    if (mounted) {
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  Future<void> _removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    // Create a mutable copy of the list to modify it
    List<String> searches = List<String>.from(_recentSearches);

    // Remove the specific query
    searches.removeWhere((s) => s.toLowerCase() == query.toLowerCase());

    // Save the updated list back to SharedPreferences
    await prefs.setStringList('recentSearches', searches);

    // Update the state to reflect the change in the UI
    if (mounted) {
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  // --- Search Logic ---

  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        setState(() {
          _isSearching = false;
          _currentQuery = '';
          _clearResults();
        });
      } else if (query != _currentQuery) {
        _currentQuery = query;
        _performSearch(query);
      }
    });
  }

  void _clearResults() {
    setState(() {
      _eventResults = [];
      _userResults = [];
      _messageResults = [];
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() => _isSearching = true);
    _clearResults();

    final lowerCaseQuery = query.toLowerCase();

    // Perform all searches in parallel
    final results = await Future.wait([
      _searchEvents(lowerCaseQuery),
      _searchUsers(lowerCaseQuery),
      _searchMessages(lowerCaseQuery),
    ]);

    if (mounted) {
      // Filter results before setting state
      List<Event> rawEvents = results[0] as List<Event>;
      List<AppUser> rawUsers = results[1] as List<AppUser>;
      List<MessageSearchResult> rawMessages =
          results[2] as List<MessageSearchResult>;

      final filteredEvents = rawEvents
          .where((event) => !_blockedUsers.contains(event.createdBy))
          .toList();
      final filteredUsers =
          rawUsers.where((user) => !_blockedUsers.contains(user.uid)).toList();
      final filteredMessages = rawMessages
          .where((message) => !_blockedUsers.contains(message.senderId))
          .toList();

      setState(() {
        _eventResults = filteredEvents;
        _userResults = filteredUsers;
        _messageResults = filteredMessages;
        _isSearching = false;
      });
    }
  }

  Future<List<Event>> _searchEvents(String query) async {
    try {
      // This query requires a 'title_lowercase' field on your 'posts' documents.
      final eventQuerySnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('isPrivate', isEqualTo: false)
          .where('title_lowercase', isGreaterThanOrEqualTo: query)
          .where('title_lowercase', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(20)
          .get();

      return eventQuerySnapshot.docs
          .map((doc) => Event.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint(
          'Error searching events: $e. Make sure you have a `title_lowercase` field and a composite index for this query in Firestore.');
      return [];
    }
  }

  Future<List<AppUser>> _searchUsers(String query) async {
    try {
      // This query requires a 'username_lowercase' field on your 'users' documents.
      final userQuerySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('username_lowercase', isGreaterThanOrEqualTo: query)
          .where('username_lowercase', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(20)
          .get();

      return userQuerySnapshot.docs.map((doc) => AppUser.fromDoc(doc)).toList();
    } catch (e) {
      debugPrint(
          'Error searching users: $e. Make sure you have a `username_lowercase` field and an index for this query in Firestore.');
      return [];
    }
  }

  Future<List<MessageSearchResult>> _searchMessages(String query) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    try {
      // This is a more direct and efficient query.
      // It finds all messages in any group where the current user is a member
      // AND the message text matches the search query.
      final messageSnapshot = await FirebaseFirestore.instance
          .collectionGroup('messages')
          .where('members',
              arrayContains: currentUser.uid) // Filter by membership directly
          .where('text_lowercase', isGreaterThanOrEqualTo: query)
          .where('text_lowercase', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(20)
          .get();

      // This part needs to fetch group titles after finding the messages.
      // It's a trade-off for a working search.
      final groupIds = messageSnapshot.docs
          .map((doc) => doc.data()['groupId'] as String)
          .toSet();
      Map<String, String> groupTitles = {};

      if (groupIds.isNotEmpty) {
        final groupsSnapshot = await FirebaseFirestore.instance
            .collection('groups')
            .where(FieldPath.documentId, whereIn: groupIds.toList())
            .get();
        for (var doc in groupsSnapshot.docs) {
          groupTitles[doc.id] = doc.data()['title'] ?? 'Untitled';
        }
      }

      List<MessageSearchResult> results = [];
      for (var doc in messageSnapshot.docs) {
        final data = doc.data();
        final groupId = data['groupId'];
        if (data.containsKey('text') &&
            data.containsKey('senderId') &&
            data.containsKey('timestamp')) {
          results.add(MessageSearchResult(
            messageId: doc.id,
            text: data['text'],
            senderId: data['senderId'],
            senderName: data['senderName'],
            groupId: groupId,
            groupTitle: groupTitles[groupId] ?? 'Chat', // Use the fetched title
            timestamp: (data['timestamp'] as Timestamp).toDate(),
          ));
        }
      }
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      // The error log you're seeing will appear here.
      debugPrint(
          'Error searching messages: $e. Ensure your data structure is correct and you have created the required Firestore index.');
      return [];
    }
  }

  void _onCategoryTap(String categoryName) {
    widget.onCategoryTapped(categoryName);
  }

  // --- UI Building ---

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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: DefaultTabController(
              length: 4,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    _buildSliverAppBar(),
                    if (_currentQuery.isNotEmpty) _buildSliverTabBar(),
                  ];
                },
                body: _buildBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text('Discover',
          style: GoogleFonts.pacifico(fontSize: 32, color: Colors.white)),
      pinned: true,
      floating: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            onSubmitted: (query) {
              if (query.isNotEmpty) {
                _saveSearchQuery(query);
              }
            },
            decoration: InputDecoration(
              hintText: 'Search events, people, messages...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              suffixIcon: _currentQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white70),
                      onPressed: () => _searchController.clear(),
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
                borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  SliverPersistentHeader _buildSliverTabBar() {
    return SliverPersistentHeader(
      delegate: _SliverAppBarDelegate(
        TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          indicatorColor: Colors.white,
          indicatorWeight: 3.0,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Events'),
            Tab(text: 'People'),
            Tab(text: 'Chats'),
          ],
        ),
      ),
      pinned: true,
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    if (_currentQuery.isEmpty) {
      return _buildInitialView();
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildAllResultsTab(),
        _buildResultsList(
            _eventResults, "No events found.", _buildEventResultTile),
        _buildResultsList(
            _userResults, "No people found.", _buildUserResultTile),
        _buildResultsList(
            _messageResults, "No messages found.", _buildMessageResultTile),
      ],
    );
  }

  Widget _buildInitialView() {
    return CustomScrollView(
      slivers: [
        if (_recentSearches.isNotEmpty) ...[
          _buildSectionHeader('Recent Searches'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _recentSearches.length,
                itemBuilder: (context, index) {
                  final search = _recentSearches[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: InputChip(
                      label: Text(search),
                      // Still allow tapping the chip to perform a search
                      onPressed: () {
                        _searchController.text = search;
                        // This moves the cursor to the end of the text, which is a nice UX touch
                        _searchController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: _searchController.text.length),
                        );
                      },
                      // Add the delete functionality
                      onDeleted: () => _removeRecentSearch(search),
                      backgroundColor: Colors.white.withOpacity(0.2),
                      deleteIconColor: Colors.white.withOpacity(0.8),
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: Colors.white.withOpacity(0.4),
                          width: 0,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        _buildSectionHeader('Browse Categories'),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
              childAspectRatio: 1.2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildCategoryCard(_categories[index]),
              childCount: _categories.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildAllResultsTab() {
    final hasResults = _eventResults.isNotEmpty ||
        _userResults.isNotEmpty ||
        _messageResults.isNotEmpty;
    if (!hasResults) {
      return _buildEmptyState("No results found for '$_currentQuery'.");
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        if (_userResults.isNotEmpty) ...[
          _buildResultsSection<AppUser>(
              'People', _userResults, _buildUserResultTile),
        ],
        if (_eventResults.isNotEmpty) ...[
          _buildResultsSection<Event>(
              'Events', _eventResults, _buildEventResultTile),
        ],
        if (_messageResults.isNotEmpty) ...[
          _buildResultsSection<MessageSearchResult>(
              'Chats', _messageResults, _buildMessageResultTile),
        ],
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildResultsSection<T>(
      String title, List<T> items, Widget Function(T) tileBuilder) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
        const SizedBox(height: 8),
        ...items.take(3).map((item) => tileBuilder(item)),
        if (items.length > 3)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextButton(
              onPressed: () {
                // Switch to the specific tab
                if (T == Event) _tabController.animateTo(1);
                if (T == AppUser) _tabController.animateTo(2);
                if (T == MessageSearchResult) _tabController.animateTo(3);
              },
              child: Text('See all ${items.length} results',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildResultsList<T>(
      List<T> items, String emptyMessage, Widget Function(T) tileBuilder) {
    if (items.isEmpty) {
      return _buildEmptyState(emptyMessage);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: items.length,
      itemBuilder: (context, index) => tileBuilder(items[index]),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, color: Colors.white70, size: 60),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildSectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
        child: Text(title,
            style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ),
    );
  }

  Widget _buildCategoryCard(AppCategory category) {
    return Card(
      color: category.color.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      shadowColor: category.color.withOpacity(0.4),
      child: InkWell(
        onTap: () => _onCategoryTap(category.name),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(category.icon, color: Colors.white, size: 40),
              const SizedBox(height: 12),
              Text(
                category.name,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Result Tile Widgets ---

  Widget _buildEventResultTile(Event event) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: () {
          _saveSearchQuery(_searchController.text.trim());
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => EventDetailsPage(event: event)));
        },
        // Using a simplified card for search results
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(15),
                    bottomLeft: Radius.circular(15)),
                child: Image.network(
                  event.imageUrl,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 100,
                    height: 100,
                    color: Colors.white.withOpacity(0.1),
                    child: const Icon(Icons.image_not_supported,
                        color: Colors.white54),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(event.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserResultTile(AppUser user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ListTile(
        leading: Hero(
          tag: 'profile_pic_${user.uid}',
          child: CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withOpacity(0.2),
            backgroundImage: user.profilePicture != null
                ? NetworkImage(user.profilePicture!)
                : null,
            child: user.profilePicture == null
                ? Icon(
                    Icons.person,
                    color: Colors.white.withOpacity(0.7),
                    size: 24,
                  )
                : null,
          ),
        ),
        title: Text(user.username,
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios,
            color: Colors.white70, size: 16),
        onTap: () {
          _saveSearchQuery(_searchController.text.trim());
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => ProfilePage(userId: user.uid)));
        },
      ),
    );
  }

  Widget _buildMessageResultTile(MessageSearchResult message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.blueGrey.shade600,
          child: const Icon(Icons.chat_bubble, color: Colors.white, size: 24),
        ),
        title: Text(message.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text("in ${message.groupTitle}",
            style:
                TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios,
            color: Colors.white70, size: 16),
        onTap: () {
          _saveSearchQuery(_searchController.text.trim());
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ChatPage(
                      groupId: message.groupId,
                      groupName: message.groupTitle)));
        },
      ),
    );
  }
}

// --- Helper class for the sticky TabBar ---
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
