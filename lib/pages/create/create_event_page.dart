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
import 'package:wimbli/widgets/invite_friends_modal.dart';
import 'package:flutter/cupertino.dart';

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

  // It's good practice to override equality checks when working with lists of objects
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser && runtimeType == other.runtimeType && uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
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

  String? _ageRestriction = 'All Ages';
  final List<String> _ageOptions = ['All Ages', '18+', '21+'];

  final List<AppUser> _invitedUsers = [];

  final List<String> _categories = appCategories.map((c) => c.name).toList();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    if (widget.eventToEdit != null) {
      _populateFieldsForEditing();
      _fetchInvitedUsersForEditing(widget.eventToEdit!.invitedUsers);
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
    super.dispose();
  }

  void _nextPage() {
    FocusScope.of(context).unfocus();
    final totalSteps = widget.isPrivate ? 10 : 9;
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
    // 1. Pick the date first (this is already platform-adaptive)
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    // Exit if the user cancelled the date selection
    if (date == null || !mounted) return;

    // 2. Pick the time, conditionally based on the platform
    TimeOfDay? time;

    if (Platform.isIOS) {
      // --- Show iOS-style "wheel" picker ---
      time = await showCupertinoModalPopup<TimeOfDay>(
        context: context,
        builder: (BuildContext context) {
          DateTime tempDate = _selectedDate ?? DateTime.now();
          return Container(
            height: 250,
            color: CupertinoColors.systemBackground.resolveFrom(context),
            child: SafeArea(
          top: false,
            child: Column(
              children: [
                // Top bar with a "Done" button
                Container(
                  height: 50,
                  color: CupertinoColors.secondarySystemBackground
                      .resolveFrom(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        child: const Text('Done'),
                        onPressed: () {
                          // Pop the modal and return the selected time
                          Navigator.of(context)
                              .pop(TimeOfDay.fromDateTime(tempDate));
                        },
                      ),
                    ],
                  ),
                ),
                // The actual time picker wheel
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: false,
                    initialDateTime: _selectedDate ?? DateTime.now(),
                    onDateTimeChanged: (DateTime newDate) {
                      tempDate = newDate; // Update the temp time when user scrolls
                    },
                  ),
                ),
              ],
            ),
            ),
          );
        },
      );
    } else {
      // --- Show Android-style "clock" picker ---
      time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate ?? DateTime.now()),
      );
    }

    // 3. If a time was selected on either platform, update the state
    if (time != null) {
      setState(() {
        _selectedDate = DateTime(
          date.year,
          date.month,
          date.day,
          time!.hour,
          time.minute,
        );
      });
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
        'ageRestriction': _ageRestriction,
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

  Future<void> _fetchInvitedUsersForEditing(List<String> userIds) async {
    if (userIds.isEmpty) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: userIds)
          .get();

      final users = querySnapshot.docs.map((doc) => AppUser.fromDoc(doc)).toList();

      if (mounted) {
        setState(() {
          _invitedUsers.addAll(users);
        });
      }
    } catch (e) {
      print("Error fetching invited users for editing: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load invited users.')),
        );
      }
    }
  }

  Future<void> _openInviteFriendsModal() async {
    final List<AppUser>? result = await showModalBottomSheet<List<AppUser>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.85,
        minChildSize: 0.5,
        builder: (_, scrollController) {
          return InviteFriendsModal(
            initiallyInvitedUsers: _invitedUsers,
            scrollController: scrollController,
          );
        },
      ),
    );

    // Update the state with the returned list of users
    if (result != null && mounted) {
      setState(() {
        _invitedUsers.clear();
        _invitedUsers.addAll(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.eventToEdit != null;
    final totalSteps = widget.isPrivate ? 10 : 9;
    final List<Widget> pages = [
      _buildImageStep(totalSteps),
      _buildStep(
          "What's the title of your event?",
          "e.g., Sunset Yoga Session",
          CustomTextField(
            controller: _titleController,
            hintText: "Event Title",
            icon: Icons.title,
            keyboardType: TextInputType.text,
          ), totalSteps),
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
          ), totalSteps),
      _buildStep(
          "Where is it happening?",
          "Add a location.",
          CustomTextField(
            controller: _locationController,
            hintText: "Location",
            icon: Icons.location_on_outlined,
            keyboardType: TextInputType.text,
          ), totalSteps),
      _buildStep("Choose a category", "This helps others find your event.",
          _buildCategorySelector(), totalSteps),
      _buildStep("Is there an age restriction?",
          "Select the appropriate age group.", _buildAgeRestrictionSelector(), totalSteps),
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
          ), totalSteps),
      _buildStep("When is the event?", "Select date and time.",
          _buildDateTimeSelector(), totalSteps),
      _buildStep(
          "What's the duration?", "e.g., 2 hours", _buildDurationInput(), totalSteps),
      if (widget.isPrivate)
        _buildStep("Invite your friends", "Select who can see this event.",
            _buildInviteFriendsStep(), totalSteps),
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
          IconButton(
  icon: const Icon(Icons.close, color: Colors.white),
  onPressed: () {
    // Show a confirmation dialog
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade800,
          title: const Text('Discard Event?', style: TextStyle(color: Colors.white)),
          content: const Text('If you go back, your progress will be lost.', style: TextStyle(color: Colors.white70)),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close the dialog
              },
            ),
            TextButton(
              child: const Text('Discard', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close the dialog
                Navigator.of(context).pop();      // Close the CreateEventPage
                FocusScope.of(context).unfocus();
              },
            ),
          ],
        );
      },
    );
  },
)
        ],
      ),
    );
  }

  Widget _buildAgeRestrictionSelector() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(30),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _ageRestriction,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
          dropdownColor: Colors.purple.shade400,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          items: _ageOptions.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _ageRestriction = newValue;
            });
          },
        ),
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

  Widget _buildStep(String title, String subtitle, Widget content, int totalSteps) {
    final isLastStep = _currentPage == totalSteps - 1;
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

  Widget _buildImageStep(int totalSteps) {
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
      totalSteps,
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
      return Center(
        child: Text(
          "No one invited yet. Tap below to add friends!",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
        ),
      );
    }

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: _invitedUsers.map((user) {
        return Chip(
          avatar: CircleAvatar(
            backgroundImage: user.profilePicture != null
                ? NetworkImage(user.profilePicture!)
                : null,
            backgroundColor: Colors.white.withOpacity(0.7),
            child: user.profilePicture == null
                ? Icon(Icons.person, size: 18, color: Colors.purple.shade700)
                : null,
          ),
          label: Text(user.username),
          backgroundColor: Colors.white.withOpacity(0.3),
          labelStyle: const TextStyle(color: Colors.white),
          deleteIconColor: Colors.white70,
          onDeleted: () {
            setState(() {
              _invitedUsers.remove(user);
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildInviteFriendsStep() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Invited",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _buildInvitedUsersList(),
          ),
          const Spacer(),
          Center(
            child: OutlinedButton.icon(
              onPressed: _openInviteFriendsModal,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text("Add / Edit Invites"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                side: const BorderSide(color: Colors.white),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
