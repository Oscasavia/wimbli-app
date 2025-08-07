import 'package:flutter/material.dart';
import 'package:wimbli/pages/main/home_page.dart';
import 'package:wimbli/pages/main/messages_page.dart';
import 'package:wimbli/pages/main/profile_page.dart';
import 'package:wimbli/pages/main/search_page.dart';
import 'package:wimbli/pages/create/create_hub_page.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  String? _homePageCategoryFilter;
  String? _profileImageUrl;
  StreamSubscription? _userSubscription;
  bool _hasUnreadMessages = false;
  StreamSubscription? _unreadMessagesSubscription;

  // final List<Widget> _pages = <Widget>[
  //   const HomePage(),
  //   const SearchPage(),
  //   const SizedBox.shrink(), // Placeholder for Create action
  //   MessagesPage(),
  //   const ProfilePage(),
  // ];

  @override
  void initState() {
    super.initState();
    _setupUserStream();
    _unreadMessagesSubscription =
        unreadMessagesStreamController.stream.listen((hasUnread) {
      if (mounted) {
        setState(() {
          _hasUnreadMessages = hasUnread;
        });
      }
    });
  }

  @override
  void dispose() {
    print("--- DISPOSING APP SHELL ---");
    _userSubscription?.cancel();
    _unreadMessagesSubscription?.cancel();
    super.dispose();
  }

  void _setupUserStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          setState(() {
            // CORRECTED: Field name is 'profilePicture' based on your file
            _profileImageUrl = snapshot.data()?['profilePicture'];
          });
        }
      });
    }
  }

  void _navigateToHome() {
    _onItemTapped(0);
  }

  void _navigateToHomeWithFilter(String category) {
    setState(() {
      _homePageCategoryFilter = category;
      _selectedIndex = 0;
    });
  }

  void _onItemTapped(int index) {
    if (index == 2) {
      // Index 2 is the 'Create' action
      _showCreateHub(context);
    } else {
      setState(() {
        _selectedIndex = index;
        _homePageCategoryFilter = null;
      });
    }
  }

  void _showCreateHub(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateHubPage(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // Handle case where user might be null during logout
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // This list is now built every time the state changes.
    final List<Widget> pages = <Widget>[
      HomePage(initialCategoryFilter: _homePageCategoryFilter),
      SearchPage(onCategoryTapped: _navigateToHomeWithFilter),
      const SizedBox.shrink(),
      MessagesPage(onNavigateToHome: _navigateToHome),
      const ProfilePage(),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          // Re-apply the transparent settings
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          extendBody: true,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade200, Colors.purple.shade300],
              ),
            ),
            child: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
          ),
          bottomNavigationBar: _buildBottomNavBar(),
        ));
  }

  Widget _buildProfileIcon({bool isSelected = false}) {
    final hasImage = _profileImageUrl != null && _profileImageUrl!.isNotEmpty;

    if (hasImage) {
      return Container(
        padding: const EdgeInsets.all(1.2), // This creates the border
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? Colors.white : Colors.transparent,
        ),
        child: CircleAvatar(
          radius: 11, // Adjusted radius for better fit
          backgroundImage: NetworkImage(_profileImageUrl!),
          backgroundColor: Colors.grey.shade300, // Fallback color
        ),
      );
    } else {
      // Use filled person icon when selected
      return Icon(isSelected ? Icons.person : Icons.person_outline);
    }
  }

  Widget _buildBottomNavBar() {
    return ClipRRect(
      child: SafeArea(
        top: false,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: Colors.transparent,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 5,
                )
              ],
            ),
            child: ClipRRect(
              child: BottomNavigationBar(
                items: <BottomNavigationBarItem>[
                  BottomNavigationBarItem(
                    label: 'Home',
                    // Icon for the unselected state (dimmed color)
                    icon: Transform.scale(
                      scale: 1.45,
                      child: Image.asset(
                        'assets/wimbliLogoWhite.png',
                        width: 24,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    activeIcon: Transform.scale(
                      scale: 1.45,
                      child: Image.asset(
                        'assets/wimbliLogoWhite.png',
                        width: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.search),
                    label: 'Discover',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.add_circle_outlined),
                    label: 'Create',
                  ),
                  BottomNavigationBarItem(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.chat_bubble_outline),
                        if (_hasUnreadMessages)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade400,
                                shape: BoxShape.circle,
                                // border:
                                //     Border.all(color: Colors.white, width: 0.5),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 8,
                                minHeight: 8,
                              ),
                            ),
                          ),
                      ],
                    ),
                    label: 'Messages',
                  ),
                  BottomNavigationBarItem(
                    icon: _buildProfileIcon(),
                    activeIcon: _buildProfileIcon(isSelected: true),
                    label: 'Profile',
                  ),
                ],
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
                backgroundColor: Colors.transparent,
                type: BottomNavigationBarType.fixed,
                elevation: 0,
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.white.withOpacity(0.6),
                // REVERTED: Restored original label visibility and font size
                showSelectedLabels: true,
                showUnselectedLabels: true,
                selectedFontSize: 12,
                unselectedFontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
