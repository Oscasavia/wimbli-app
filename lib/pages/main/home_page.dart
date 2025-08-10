import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wimbli/models/event_model.dart';
import 'package:wimbli/widgets/event_card.dart';
import 'package:wimbli/constants/app_data.dart';
import 'package:wimbli/pages/main/event_details_page.dart';
import 'dart:async';
// import 'dart:math';
import 'package:geolocator/geolocator.dart';

class HomePage extends StatefulWidget {
  final String? initialCategoryFilter;

  const HomePage({super.key, this.initialCategoryFilter});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _scrollController = ScrollController();
  List<Event> _allEvents = [];
  List<String> _savedPostIds = [];
  bool _isLoading = true;

  // --- Stream Subscription for real-time data ---
  StreamSubscription? _userSubscription;
  StreamSubscription? _publicEventsSubscription;
  StreamSubscription? _myPrivateEventsSubscription;
  StreamSubscription? _invitedEventsSubscription;

  List<Event> _publicEvents = [];
  List<Event> _myPrivateEvents = [];
  List<Event> _invitedEvents = [];
  List<String> _blockedUsers = [];

  // --- Search & Filter State ---
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _selectedTimeFilter = 'All';
  Map<String, dynamic> _advancedFilters = {
    'category': 'All',
    'fee': 'All',
    'distance': 50.0, // Default distance in miles
    'privacy': 'All',
  };
  Position? _userLocation;

  final List<String> _timeFilterOptions = [
    'All',
    'Now',
    'Today',
    'This Weekend',
    'This Week',
    'Next Week',
    'This Month',
  ];

  final List<String> _categoryFilterOptions = [
    'All',
    ...appCategories.map((c) => c.name)
  ];

  @override
  void initState() {
    super.initState();
    _initializePage();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _publicEventsSubscription?.cancel();
    _myPrivateEventsSubscription?.cancel();
    _invitedEventsSubscription?.cancel();
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // This method runs when AppShell provides a new HomePage with a filter.
    // We check if the new filter is different from the old one.
    if (widget.initialCategoryFilter != null &&
        widget.initialCategoryFilter != oldWidget.initialCategoryFilter) {
      // If the filter has changed, we apply it and reload the data.
      setState(() {
        // Update the filter state.
        _advancedFilters['category'] = widget.initialCategoryFilter!;
        // Reset other filters for a clean view.
        _selectedTimeFilter = 'All';
        _searchController.clear();
      });

      // Crucially, re-run the data fetching with the new category.
      _setupDataStreams(widget.initialCategoryFilter!);
      _scrollToTop();
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _initializePage() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    // This keeps the _savedPostIds list always in sync.
    _userSubscription?.cancel();
    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((userDoc) {
      if (mounted && userDoc.exists) {
        final data = userDoc.data();
        // When the user's saved posts or blocked users change in the database,
        // update our local lists and rebuild the UI.
        setState(() {
          _savedPostIds = List<String>.from(data?['savedPosts'] ?? []);
          _blockedUsers = List<String>.from(data?['blockedUsers'] ?? []);
        });
      }
    });

    // Load the user's saved filters first.
    await _loadFilterPreferences();

    String initialCategory =
        widget.initialCategoryFilter ?? _advancedFilters['category'] ?? 'All';

    // If an initial filter was passed from another page, override the loaded preference.
    if (widget.initialCategoryFilter != null) {
      setState(() {
        _advancedFilters['category'] = widget.initialCategoryFilter!;
        _selectedTimeFilter = 'All'; // Also reset time filter for consistency
      });
      initialCategory = widget.initialCategoryFilter!;
    }

    // Pass the determined filter to the data stream setup.
    _setupDataStreams(initialCategory);

    await _getUserLocation();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    await _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() => _userLocation = position);
    }
  }

  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {});
        _scrollToTop();
      }
    });
  }

  void _combineAndSetEvents() {
    // Use a Map to automatically handle duplicates
    // (e.g., if you created an event and also invited yourself)
    final allVisibleEvents = <String, Event>{};

    for (var event in _publicEvents) {
      allVisibleEvents[event.id] = event;
    }
    for (var event in _myPrivateEvents) {
      allVisibleEvents[event.id] = event;
    }
    for (var event in _invitedEvents) {
      allVisibleEvents[event.id] = event;
    }

    // Convert the map back to a list and sort it by date
    final finalList = allVisibleEvents.values.toList();
    finalList.sort((a, b) => a.date.compareTo(b.date)); // Sort ascending

    if (mounted) {
      setState(() {
        _allEvents = finalList;
      });
    }
  }

  void _updateEventEverywhere(Event updatedEvent) {
    final index = _allEvents.indexWhere((e) => e.id == updatedEvent.id);
    if (index != -1) {
      _allEvents[index] = updatedEvent;
    }
  }

  void _setupDataStreams(String categoryFilter) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Cancel any existing subscriptions before creating new ones
    _publicEventsSubscription?.cancel();
    _myPrivateEventsSubscription?.cancel();
    _invitedEventsSubscription?.cancel();

    // -- QUERY 1: All PUBLIC events --
    Query publicQuery = FirebaseFirestore.instance
        .collection('posts')
        .where('isPrivate', isEqualTo: false);
    if (categoryFilter != 'All') {
      publicQuery = publicQuery.where('category', isEqualTo: categoryFilter);
    }
    _publicEventsSubscription = publicQuery.snapshots().listen((snapshot) {
      _publicEvents = snapshot.docs.map((doc) {
        final event = Event.fromFirestore(doc);
        event.isInterested = _savedPostIds.contains(event.id);
        return event;
      }).toList();
      _combineAndSetEvents(); // Combine results
    });

    // -- QUERY 2: Private events CREATED BY the current user --
    Query myPrivateQuery = FirebaseFirestore.instance
        .collection('posts')
        .where('isPrivate', isEqualTo: true)
        .where('createdBy', isEqualTo: user.uid);
    if (categoryFilter != 'All') {
      myPrivateQuery =
          myPrivateQuery.where('category', isEqualTo: categoryFilter);
    }
    _myPrivateEventsSubscription =
        myPrivateQuery.snapshots().listen((snapshot) {
      _myPrivateEvents = snapshot.docs.map((doc) {
        final event = Event.fromFirestore(doc);
        event.isInterested = _savedPostIds.contains(event.id);
        return event;
      }).toList();
      _combineAndSetEvents(); // Combine results
    });

    // -- QUERY 3: Private events the current user is INVITED TO --
    Query invitedQuery = FirebaseFirestore.instance
        .collection('posts')
        .where('isPrivate', isEqualTo: true)
        .where('invitedUsers', arrayContains: user.uid);
    if (categoryFilter != 'All') {
      invitedQuery = invitedQuery.where('category', isEqualTo: categoryFilter);
    }
    _invitedEventsSubscription = invitedQuery.snapshots().listen((snapshot) {
      _invitedEvents = snapshot.docs.map((doc) {
        final event = Event.fromFirestore(doc);
        event.isInterested = _savedPostIds.contains(event.id);
        return event;
      }).toList();
      _combineAndSetEvents(); // Combine results
    });
  }

  Future<void> _loadFilterPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && mounted) {
        final prefs =
            userDoc.data()?['filterPreferences'] as Map<String, dynamic>?;
        if (prefs != null) {
          setState(() {
            final savedCategory = prefs['category'] ?? 'All';

            // Check if the saved category exists in our list of valid options.
            if (_categoryFilterOptions.contains(savedCategory)) {
              _advancedFilters['category'] = savedCategory;
            } else {
              // If it's not a valid option, default to 'All' to prevent a crash.
              _advancedFilters['category'] = 'All';
            }

            // The rest of the filters can be loaded as usual
            _selectedTimeFilter = prefs['timeFilter'] ?? 'All';
            _advancedFilters['fee'] = prefs['fee'] ?? 'All';
            _advancedFilters['distance'] =
                (prefs['distance'] ?? 50.0).toDouble();
            _advancedFilters['privacy'] = prefs['privacy'] ?? 'All';
          });
        }
      }
    } catch (e) {
      // It's okay if this fails, the user will just have default filters.
    }
  }

  Future<void> _saveFilterPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final Map<String, dynamic> filterPreferences = {
      'timeFilter': _selectedTimeFilter,
      'category': _advancedFilters['category'],
      'fee': _advancedFilters['fee'],
      'distance': _advancedFilters['distance'],
      'privacy': _advancedFilters['privacy'],
    };

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'filterPreferences': filterPreferences}, SetOptions(merge: true));
    } catch (e) {
      // Handle or log error if saving fails.
    }
  }

  void _navigateToEventDetails(Event event) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventDetailsPage(event: event)),
    );
  }

  Duration _parseDuration(String durationStr) {
    if (durationStr.isEmpty) {
      return Duration.zero;
    }
    try {
      final parts = durationStr.split(' ');
      if (parts.length != 2) return Duration.zero;

      final value = int.tryParse(parts[0]);
      if (value == null) return Duration.zero;

      final unit = parts[1].toLowerCase();
      switch (unit) {
        case 'minutes':
          return Duration(minutes: value);
        case 'hours':
          return Duration(hours: value);
        case 'days':
          return Duration(days: value);
        default:
          return Duration.zero;
      }
    } catch (e) {
      // Log error if needed, for now, return zero.
      print('Error parsing duration: $e');
      return Duration.zero;
    }
  }

  List<Event> _getFilteredEvents() {
    List<Event> events = List.from(_allEvents);
    final now = DateTime.now();

    // Helper to get start of day
    DateTime startOfDay(DateTime date) =>
        DateTime(date.year, date.month, date.day);
    // Helper to get end of day (up to the last millisecond)
    DateTime endOfDay(DateTime date) =>
        DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    final searchTerm = _searchController.text.toLowerCase();
    if (searchTerm.isNotEmpty) {
      events = events.where((event) {
        return event.title.toLowerCase().contains(searchTerm) ||
            event.description.toLowerCase().contains(searchTerm);
      }).toList();
    }

    switch (_selectedTimeFilter) {
      case 'Now':
        events = events.where((e) {
          final eventStartTime = e.date;
          final eventDuration = _parseDuration(e.duration);
          // If duration is invalid, the event won't be considered "Now"
          if (eventDuration == Duration.zero) {
            return false;
          }
          final eventEndTime = eventStartTime.add(eventDuration);
          // The window starts 10 minutes before the event's official start time
          final filterStartTime =
              eventStartTime.subtract(const Duration(minutes: 10));

          // Check if the current time is within the event's active window
          return now.isAfter(filterStartTime) && now.isBefore(eventEndTime);
        }).toList();
        break;
      case 'Today':
        events = events
            .where((e) =>
                e.date.year == now.year &&
                e.date.month == now.month &&
                e.date.day == now.day)
            .toList();
        break;
      case 'This Weekend':
        // Calculate the upcoming Saturday and Sunday, focusing on the date part
        DateTime weekendStart = startOfDay(
            now.add(Duration(days: DateTime.saturday - now.weekday)));
        DateTime weekendEnd = endOfDay(weekendStart
            .add(const Duration(days: 1))); // Saturday + 1 day = Sunday

        events = events
            .where((e) =>
                !e.date.isBefore(weekendStart) && !e.date.isAfter(weekendEnd))
            .toList();
        break;
      case 'This Week':
        final weekEnd =
            now.add(Duration(days: DateTime.daysPerWeek - now.weekday));
        events = events
            .where((e) => e.date.isAfter(now) && e.date.isBefore(weekEnd))
            .toList();
        break;
      case 'Next Week':
        final startOfNextWeek =
            startOfDay(now.add(Duration(days: 8 - now.weekday)));
        final endOfNextWeek =
            endOfDay(startOfNextWeek.add(const Duration(days: 6)));
        events = events
            .where((e) =>
                !e.date.isBefore(startOfNextWeek) &&
                !e.date.isAfter(endOfNextWeek))
            .toList();
        break;
      case 'This Month':
        events = events
            .where((e) => e.date.year == now.year && e.date.month == now.month)
            .toList();
        break;
    }

    if (_advancedFilters['category'] != 'All') {
      events = events
          .where((e) => e.category == _advancedFilters['category'])
          .toList();
    }
    if (_advancedFilters['fee'] == 'Free') {
      events = events.where((e) => e.fee == 0).toList();
    } else if (_advancedFilters['fee'] == 'Paid') {
      events = events.where((e) => e.fee > 0).toList();
    }
    if (_advancedFilters['privacy'] == 'Public') {
      events = events.where((e) => e.isPrivate == false).toList();
    } else if (_advancedFilters['privacy'] == 'Private') {
      events = events.where((e) => e.isPrivate == true).toList();
    }
    if (_userLocation != null) {
      final maxDistance =
          (_advancedFilters['distance'] as double) * 1609.34; // miles to meters
      events = events.where((e) {
        if (e.coordinates == null) return false;
        final distance = Geolocator.distanceBetween(
            _userLocation!.latitude,
            _userLocation!.longitude,
            e.coordinates!.latitude,
            e.coordinates!.longitude);
        return distance <= maxDistance;
      }).toList();
    }

    if (_blockedUsers.isNotEmpty) {
      events = events.where((event) {
        // Keep the event only if its creator's ID is NOT in the blocked list.
        return !_blockedUsers.contains(event.createdBy);
      }).toList();
    }

    return events;
  }

  void _showFilterDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, controller) {
            return _FilterDrawer(
              scrollController: controller,
              currentFilters: _advancedFilters,
              onApplyFilters: (newFilters) {
                setState(() {
                  _advancedFilters = newFilters;
                });
                _scrollToTop();
                _saveFilterPreferences();

                _setupDataStreams(_advancedFilters['category']);
              },
              categoryOptions: _categoryFilterOptions,
            );
          },
        );
      },
    );
  }

  Widget _buildTimeFilterChips() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _timeFilterOptions.length,
        itemBuilder: (context, index) {
          final filter = _timeFilterOptions[index];
          final isSelected = _selectedTimeFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: filter == 'Now'
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_sharp,
                          color: isSelected
                              ? Colors.purple.shade700
                              : const Color.fromARGB(255, 250, 158, 20),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(filter),
                      ],
                    )
                  : Text(filter),
              selected: isSelected,
              onSelected: (bool selected) {
                if (selected) {
                  setState(() => _selectedTimeFilter = filter);
                  _scrollToTop();
                  _saveFilterPreferences(); // Save filters when changed
                }
              },
              backgroundColor: Colors.white.withOpacity(0.2),
              selectedColor: Colors.white,
              checkmarkColor: Colors.purple.shade300,
              labelStyle: TextStyle(
                color: isSelected ? Colors.purple.shade700 : Colors.white,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color:
                      isSelected ? Colors.white : Colors.white.withOpacity(0.2),
                  width: 0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredEvents = _getFilteredEvents();
    final featuredEvents = filteredEvents.take(5).toList();
    final forYouEvents = filteredEvents.skip(5).toList();

    return SafeArea(
      bottom: false,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              onRefresh: _handleRefresh,
              color: Colors.white,
              backgroundColor: Colors.purple.shade400,
              displacement: 100.0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverAppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      centerTitle: true,
                      title: Text('Wimbli',
                          style: GoogleFonts.pacifico(
                              fontSize: 32, color: Colors.white)),
                      floating: true,
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Search for events...',
                                hintStyle: TextStyle(
                                    color: Colors.white.withOpacity(0.7)),
                                prefixIcon: Image.asset(
                                  'assets/wimbliLogoWhite.png',
                                  height: 5,
                                  color: Colors.white70,
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.filter_list,
                                      color: Colors.white70),
                                  onPressed: _showFilterDrawer,
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.2),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30),
                                  borderSide: BorderSide(
                                      color: Colors.white.withOpacity(0.5)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _buildTimeFilterChips(),
                    ),
                    if (filteredEvents.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_busy,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 80),
                              const SizedBox(height: 20),
                              Text('No Events Found',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white.withOpacity(0.9))),
                              const SizedBox(height: 8),
                              Text(
                                "It's a bit quiet right now.\nTry a different filter or check back later!",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.7)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
                          child: Text('Featured Events',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 320,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: featuredEvents.length,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            itemBuilder: (context, index) {
                              final event = featuredEvents[index];
                              return Container(
                                width: MediaQuery.of(context).size.width * 0.8,
                                margin: EdgeInsets.only(
                                    right: index == featuredEvents.length - 1
                                        ? 0
                                        : 16),
                                child: GestureDetector(
                                  onTap: () => _navigateToEventDetails(event),
                                  child: FeaturedEventCard(
                                    key: ValueKey(event.id),
                                    event: event,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (forYouEvents.isNotEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 18, 16, 4),
                            child: Text('For You',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ),
                      if (forYouEvents.isNotEmpty)
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final event = forYouEvents[index];
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: GestureDetector(
                                  onTap: () => _navigateToEventDetails(event),
                                  child: ForYouEventCard(
                                    key: ValueKey(event.id),
                                    event: event,
                                  ),
                                ),
                              );
                            },
                            childCount: forYouEvents.length,
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ]
                  ],
                ),
              )),
    );
  }
}

class _FilterDrawer extends StatefulWidget {
  final ScrollController scrollController;
  final Map<String, dynamic> currentFilters;
  final Function(Map<String, dynamic>) onApplyFilters;
  final List<String> categoryOptions;

  const _FilterDrawer({
    required this.scrollController,
    required this.currentFilters,
    required this.onApplyFilters,
    required this.categoryOptions,
  });

  @override
  State<_FilterDrawer> createState() => __FilterDrawerState();
}

class __FilterDrawerState extends State<_FilterDrawer> {
  late Map<String, dynamic> _tempFilters;

  @override
  void initState() {
    super.initState();
    _tempFilters = Map.from(widget.currentFilters);
  }

  @override
  Widget build(BuildContext context) {
    final int miles = _tempFilters['distance'].toInt();
    final int km = (miles * 1.60934).toInt();
    final String distanceLabel = '$miles mi / $km km';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2C),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Filters',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSectionHeader('Category'),
                DropdownButton<String>(
                  value: _tempFilters['category'],
                  onChanged: (String? newValue) {
                    setState(() => _tempFilters['category'] = newValue!);
                  },
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2A2A3D),
                  style: const TextStyle(color: Colors.white),
                  items: widget.categoryOptions
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                        value: value, child: Text(value));
                  }).toList(),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('Fee'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['All', 'Free', 'Paid'].map((fee) {
                    return ChoiceChip(
                      label: Text(fee),
                      selected: _tempFilters['fee'] == fee,
                      onSelected: (selected) =>
                          setState(() => _tempFilters['fee'] = fee),
                      backgroundColor: Colors.white.withOpacity(0.1),
                      selectedColor: Colors.purple.shade300,
                      labelStyle: const TextStyle(color: Colors.white),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('Visibility'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['All', 'Public', 'Private'].map((privacy) {
                    return ChoiceChip(
                      label: Text(privacy),
                      selected: _tempFilters['privacy'] == privacy,
                      onSelected: (selected) =>
                          setState(() => _tempFilters['privacy'] = privacy),
                      backgroundColor: Colors.white.withOpacity(0.1),
                      selectedColor: Colors.purple.shade300,
                      labelStyle: const TextStyle(color: Colors.white),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('Distance ($distanceLabel)'),
                Slider(
                  value: _tempFilters['distance'],
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: distanceLabel,
                  onChanged: (value) =>
                      setState(() => _tempFilters['distance'] = value),
                  activeColor: Colors.purple.shade300,
                  inactiveColor: Colors.white.withOpacity(0.3),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 55.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade400,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15))),
              onPressed: () {
                widget.onApplyFilters(_tempFilters);
                Navigator.pop(context);
              },
              child: const Text('Apply Filters',
                  style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600)),
    );
  }
}
