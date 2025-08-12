import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wimbli/pages/create/create_event_page.dart'; // To get AppUser
import 'package:wimbli/widgets/custom_textfield.dart';

class InviteFriendsModal extends StatefulWidget {
  final List<AppUser> initiallyInvitedUsers;
  final ScrollController scrollController;

  const InviteFriendsModal({
    super.key,
    required this.initiallyInvitedUsers,
    required this.scrollController,
  });

  @override
  State<InviteFriendsModal> createState() => _InviteFriendsModalState();
}

class _InviteFriendsModalState extends State<InviteFriendsModal> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<AppUser> _searchResults = [];
  List<AppUser> _suggestedUsers = [];
  bool _isSearching = false;
  bool _isLoadingSuggestions = true;
  late List<AppUser> _selectedUsers;

  @override
  void initState() {
    super.initState();
    _selectedUsers = List<AppUser>.from(widget.initiallyInvitedUsers);
    _searchController.addListener(_onSearchChanged);
    _fetchInitialSuggestions();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        final query = _searchController.text.trim();
        if (query.isNotEmpty) {
          _searchUsers(query);
        } else {
          setState(() => _searchResults = []);
        }
      }
    });
  }

  Future<void> _fetchInitialSuggestions() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _isLoadingSuggestions = false);
      return;
    }

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, isNotEqualTo: currentUser.uid)
          .limit(10)
          .get();

      final users =
          querySnapshot.docs.map((doc) => AppUser.fromDoc(doc)).toList();
      if (mounted) {
        setState(() {
          _suggestedUsers = users;
          _isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSuggestions = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final lowerCaseQuery = query.toLowerCase();
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username_lowercase', isGreaterThanOrEqualTo: lowerCaseQuery)
        .where('username_lowercase', isLessThanOrEqualTo: '$lowerCaseQuery\uf8ff')
        .limit(10)
        .get();

    final users = querySnapshot.docs
        .where((doc) => doc.id != currentUser.uid)
        .map((doc) => AppUser.fromDoc(doc))
        .toList();

    if (mounted) {
      setState(() {
        _searchResults = users;
        _isSearching = false;
      });
    }
  }

  void _toggleSelection(AppUser user) {
    setState(() {
      final isSelected = _selectedUsers.contains(user);
      if (isSelected) {
        _selectedUsers.remove(user);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  void _confirmSelection() {
    Navigator.of(context).pop(_selectedUsers);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2c2c2e), // A dark, sleek color for the modal
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 8.0, 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Invite Friends",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: _confirmSelection,
                  child: const Text("Confirm",
                      style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: CustomTextField(
              controller: _searchController,
              hintText: "Search by username...",
              icon: Icons.search,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildResultsOrSuggestionsList()),
        ],
      ),
    );
  }

  Widget _buildResultsOrSuggestionsList() {
    bool showSuggestions = _searchController.text.isEmpty;
    bool isLoading = showSuggestions ? _isLoadingSuggestions : _isSearching;
    List<AppUser> listToShow =
        showSuggestions ? _suggestedUsers : _searchResults;

    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    if (listToShow.isEmpty) {
      return Center(
        child: Text(
          showSuggestions
              ? "No suggestions. Start searching!"
              : "No users found for '${_searchController.text}'.",
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.only(top: 8),
      itemCount: listToShow.length,
      itemBuilder: (context, index) {
        final user = listToShow[index];
        final isSelected = _selectedUsers.contains(user);

        return ListTile(
          leading: CircleAvatar(
            backgroundImage: user.profilePicture != null
                ? NetworkImage(user.profilePicture!)
                : null,
            backgroundColor: Colors.white.withOpacity(0.7),
            child: user.profilePicture == null
                ? Icon(Icons.person, color: Colors.purple.shade700)
                : null,
          ),
          title: Text(user.username,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: Checkbox(
            value: isSelected,
            onChanged: (bool? value) {
              _toggleSelection(user);
            },
            activeColor: Colors.blueAccent,
            checkColor: Colors.white,
            side: const BorderSide(color: Colors.white70),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onTap: () => _toggleSelection(user),
        );
      },
    );
  }
}