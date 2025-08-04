import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:wimbli/models/event_model.dart';
import 'package:wimbli/widgets/custom_textfield.dart';
import 'package:wimbli/constants/app_data.dart';

// A simple model to represent a user for search results
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

class CreateEventPage extends StatefulWidget {
  final bool isPrivate;
  final Event? eventToEdit; // Make event optional for editing

  const CreateEventPage({super.key, required this.isPrivate, this.eventToEdit});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _isSaving = false;

  // --- State for Event Data ---
  File? _eventImageFile;
  String? _eventImageUrl; // To hold the existing image URL when editing
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedCategory;
  final _feeController = TextEditingController();
  DateTime? _selectedDate;
  final _durationController = TextEditingController();
  String _durationUnit = 'minutes';

  final _searchController = TextEditingController();
  Timer? _debounce;
  List<AppUser> _searchResults = [];
  List<AppUser> _suggestedUsers = [];
  bool _isSearching = false;
  bool _isLoadingSuggestions = true;
  final List<AppUser> _invitedUsers = [];

  final List<String> _categories = appCategories.map((c) => c.name).toList();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _searchController.addListener(_onSearchChanged);
    _fetchInitialSuggestions();

    if (widget.eventToEdit != null) {
      _populateFieldsForEditing();
    }
  }

  void _populateFieldsForEditing() {
    final event = widget.eventToEdit!;
    _titleController.text = event.title;
    _descriptionController.text = event.description;
    _locationController.text = event.location;
    _selectedCategory = event.category;
    _feeController.text = event.fee.toString();
    _selectedDate = event.date;
    _eventImageUrl = event.imageUrl;

    // Parse duration string
    final durationParts = event.duration.split(' ');
    if (durationParts.length == 2) {
      _durationController.text = durationParts[0];
      _durationUnit = durationParts[1];
    } else {
      _durationController.text = event.duration;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _feeController.dispose();
    _durationController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        if (_searchController.text.trim().isNotEmpty) {
          _searchUsers(_searchController.text.trim());
        } else {
          setState(() {
            _searchResults = [];
          });
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
          .limit(3)
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
      if (mounted) {
        setState(() => _isLoadingSuggestions = false);
      }
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
        .where('username_lowercase',
            isLessThanOrEqualTo: '$lowerCaseQuery\uf8ff')
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

  void _toggleInvite(AppUser user) {
    setState(() {
      if (_invitedUsers.any((invitedUser) => invitedUser.uid == user.uid)) {
        _invitedUsers.removeWhere((invitedUser) => invitedUser.uid == user.uid);
      } else {
        _invitedUsers.add(user);
      }
    });
  }

  void _nextPage() {
    final totalSteps = widget.isPrivate ? 9 : 8;
    if (_currentPage < totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _saveEvent();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _eventImageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _selectDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate ?? DateTime.now()),
      );
      if (time != null) {
        setState(() {
          _selectedDate =
              DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _saveEvent() async {
    FocusScope.of(context).unfocus();
    // --- Validation ---
    if ((_eventImageFile == null && widget.eventToEdit == null) ||
        _titleController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty ||
        _locationController.text.trim().isEmpty ||
        _selectedCategory == null ||
        _selectedDate == null ||
        _durationController.text.trim().isEmpty) {
      _showErrorSnackBar('Please complete all steps.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      String? imageUrl = _eventImageUrl;
      if (_eventImageFile != null) {
        final storageRef = FirebaseStorage.instance.ref().child(
            'event_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}');
        final uploadTask = storageRef.putFile(_eventImageFile!);
        final snapshot = await uploadTask;
        imageUrl = await snapshot.ref.getDownloadURL();
      }

      final durationString =
          '${_durationController.text.trim()} $_durationUnit';
      final invitedUserIds = _invitedUsers.map((user) => user.uid).toList();

      final eventData = {
        'title': _titleController.text.trim(),
        'title_lowercase': _titleController.text.trim().toLowerCase(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'category': _selectedCategory,
        'fee': double.tryParse(_feeController.text.trim()) ?? 0.0,
        'date': Timestamp.fromDate(_selectedDate!),
        'duration': durationString,
        'imageUrl': imageUrl,
        'isPrivate': widget.isPrivate,
        'invitedUsers': widget.isPrivate ? invitedUserIds : [],
      };

      if (widget.eventToEdit != null) {
        // Update existing event
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.eventToEdit!.id)
            .update(eventData);
      } else {
        // Create new event
        final position = await _getCurrentLocation();
        final geoPoint = GeoPoint(position.latitude, position.longitude);
        final fullEventData = {
          ...eventData,
          'coordinates': geoPoint,
          'createdBy': user.uid,
          'postCreatorId': user.uid,
          'creatorUsername': user.displayName ?? 'A User',
          'creatorProfilePic': user.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
          'interestedCount': 0,
          'likedBy': [],
        };
        await FirebaseFirestore.instance.collection('posts').add(fullEventData);
      }

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to save event: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.eventToEdit != null;
    final totalSteps = widget.isPrivate ? 9 : 8;
    final List<Widget> pages = [
      _buildImageStep(),
      _buildStep(
          "What's the title of your event?",
          "e.g., Sunset Yoga Session",
          CustomTextField(
            controller: _titleController,
            hintText: "Event Title",
            icon: Icons.title,
            keyboardType: TextInputType.text,
          )),
      _buildStep(
          "Describe your event",
          "Tell everyone what it's about.",
          CustomTextField(
            controller: _descriptionController,
            hintText: "Description",
            icon: Icons.description,
            keyboardType: TextInputType.multiline, // Enables the 'Enter' key
            maxLines: 5,
            minLines: 1,
          )),
      _buildStep(
          "Where is it happening?",
          "Add a location.",
          CustomTextField(
            controller: _locationController,
            hintText: "Location",
            icon: Icons.location_on_outlined,
            keyboardType: TextInputType.text,
          )),
      _buildStep("Choose a category", "This helps others find your event.",
          _buildCategorySelector()),
      _buildStep(
          "Is there an entry fee?",
          "(Optional)",
          CustomTextField(
            controller: _feeController,
            hintText: "Fee (e.g., 10 or Free)",
            icon: Icons.attach_money,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
            ],
          )),
      _buildStep("When is the event?", "Select date and time.",
          _buildDateTimeSelector()),
      _buildStep(
          "What's the duration?", "e.g., 2 hours", _buildDurationInput()),
      if (widget.isPrivate)
        _buildStep("Invite your friends", "Select who can see this event.",
            _buildInviteFriendsStep()),
    ];

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
          child: Column(
            children: [
              _buildAppBar(context, isEditing),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: _buildProgressBar(totalSteps),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (int page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  children: pages,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isEditing) {
    String title;
    if (isEditing) {
      title = 'Edit Event';
    } else {
      title = widget.isPrivate ? 'Create Private Event' : 'Create Public Event';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: _currentPage == 0
                ? () => Navigator.of(context).pop()
                : _previousPage,
          ),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProgressBar(int totalSteps) {
    return Row(
      children: List.generate(totalSteps, (index) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.0),
            height: 4.0,
            decoration: BoxDecoration(
              color: index <= _currentPage
                  ? Colors.white
                  : Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStep(String title, String subtitle, Widget content) {
    final isLastStep = _currentPage == (widget.isPrivate ? 8 : 7);
    final isEditing = widget.eventToEdit != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 16, color: Colors.white.withOpacity(0.8))),
          const SizedBox(height: 5),
          content,
          const Spacer(),
          ElevatedButton(
            onPressed: _isSaving ? null : _nextPage,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.purple.shade700,
              backgroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            child: _isSaving && isLastStep
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.purple))
                : Text(
                    isLastStep
                        ? (isEditing ? 'Save Changes' : 'Create Event')
                        : 'Next',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildImageStep() {
    ImageProvider? imageProvider;
    if (_eventImageFile != null) {
      imageProvider = FileImage(_eventImageFile!);
    } else if (_eventImageUrl != null) {
      imageProvider = NetworkImage(_eventImageUrl!);
    }

    return _buildStep(
      "Add a photo for your event",
      "This will be the first thing people see.",
      GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
            image: imageProvider != null
                ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
                : null,
          ),
          child: imageProvider == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        color: Colors.white.withOpacity(0.8), size: 50),
                    const SizedBox(height: 16),
                    Text('Tap to select an image',
                        style: TextStyle(color: Colors.white.withOpacity(0.8))),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            children: _categories.map((category) {
              final isSelected = _selectedCategory == category;
              return ChoiceChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (bool selected) {
                  setState(() {
                    _selectedCategory = selected ? category : null;
                  });
                },
                backgroundColor: Colors.white.withOpacity(0.2),
                selectedColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.purple.shade700 : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimeSelector() {
    return GestureDetector(
      onTap: _selectDateTime,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, color: Colors.white70),
            const SizedBox(width: 12),
            Text(
              _selectedDate == null
                  ? 'Select Date & Time'
                  : DateFormat('MMM d, yyyy - h:mm a').format(_selectedDate!),
              style: TextStyle(
                  color: Colors.white
                      .withOpacity(_selectedDate == null ? 0.7 : 1.0),
                  fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationInput() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: CustomTextField(
            controller: _durationController,
            hintText: 'e.g., 2',
            icon: Icons.hourglass_bottom_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(30),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _durationUnit,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                dropdownColor: Colors.purple.shade400,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                items: <String>['minutes', 'hours', 'days']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _durationUnit = newValue!;
                  });
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvitedUsersList() {
    if (_invitedUsers.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Invited",
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _invitedUsers.length,
            itemBuilder: (context, index) {
              final user = _invitedUsers[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Chip(
                  avatar: CircleAvatar(
                    backgroundImage: user.profilePicture != null
                        ? NetworkImage(user.profilePicture!)
                        : null,
                    backgroundColor: Colors.white.withOpacity(0.7),
                    child: user.profilePicture == null
                        ? Icon(Icons.person,
                            size: 18, color: Colors.purple.shade700)
                        : null,
                  ),
                  label: Text(user.username),
                  onDeleted: () => _toggleInvite(user),
                  deleteIconColor: Colors.white70,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
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
              ? "No suggestions found."
              : "No users found for '${_searchController.text}'.",
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    return ListView.builder(
      itemCount: listToShow.length,
      itemBuilder: (context, index) {
        final user = listToShow[index];
        final isInvited =
            _invitedUsers.any((invitedUser) => invitedUser.uid == user.uid);

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
          title:
              Text(user.username, style: const TextStyle(color: Colors.white)),
          trailing: Checkbox(
            value: isInvited,
            onChanged: (bool? value) {
              _toggleInvite(user);
            },
            activeColor: Colors.white,
            checkColor: Colors.purple.shade400,
            side: const BorderSide(color: Colors.white70),
          ),
        );
      },
    );
  }

  Widget _buildInviteFriendsStep() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomTextField(
            controller: _searchController,
            hintText: "Search by username...",
            icon: Icons.search,
          ),
          const SizedBox(height: 16),
          _buildInvitedUsersList(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              _searchController.text.isEmpty ? "Suggestions" : "Search Results",
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ),
          const Divider(color: Colors.white54),
          Expanded(
            child: _buildResultsOrSuggestionsList(),
          ),
        ],
      ),
    );
  }
}
