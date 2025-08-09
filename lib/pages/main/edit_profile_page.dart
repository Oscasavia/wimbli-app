import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wimbli/widgets/custom_textfield.dart';
import 'package:wimbli/constants/app_data.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final Set<String> _selectedInterests = {};
  final List<String> _allInterests = appCategories.map((c) => c.name).toList();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _profilePictureUrl;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        _usernameController.text = data['username'] ?? '';
        _bioController.text = data['bio'] ?? '';
        _profilePictureUrl = data['profilePicture'];
        _selectedInterests.addAll(List<String>.from(data['interests'] ?? []));
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load profile data.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadImage(File image) async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final storageRef =
          FirebaseStorage.instance.ref().child('profilePictures/${user.uid}');
      final uploadTask = storageRef.putFile(image);
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      _showErrorSnackBar('Failed to upload image.');
      return null;
    }
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (_usernameController.text.trim().length < 3) {
      _showErrorSnackBar('Username must be at least 3 characters.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      String? newImageUrl = _profilePictureUrl;

      if (_imageFile != null) {
        newImageUrl = await _uploadImage(_imageFile!);
        if (newImageUrl == null) {
          setState(() => _isSaving = false);
          return;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'username': _usernameController.text.trim(),
        'username_lowercase': _usernameController.text.trim().toLowerCase(),
        'bio': _bioController.text.trim(),
        'interests': _selectedInterests.toList(),
        'profilePicture': newImageUrl,
      });

      await user.updateDisplayName(_usernameController.text.trim());
      await user.updatePhotoURL(newImageUrl);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to save profile.');
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
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      centerTitle: true,
                      title: Text('Edit Profile',
                          style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios,
                            color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Save',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            _buildAvatar(),
                            const SizedBox(height: 24),
                            _buildSectionHeader('Username'),
                            CustomTextField(
                                controller: _usernameController,
                                hintText: 'Your username',
                                icon: Icons.person_outline),
                            const SizedBox(height: 24),
                            _buildSectionHeader('Bio'),
                            CustomTextField(
                                controller: _bioController,
                                hintText: 'Tell us about yourself',
                                icon: Icons.edit_note_outlined),
                            const SizedBox(height: 24),
                            _buildSectionHeader('Interests'),
                            _buildInterestsGrid(),
                            const SizedBox(height: 100),
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

  Widget _buildAvatar() {
    Widget child;
    if (_imageFile != null) {
      child = CircleAvatar(
        radius: 60,
        backgroundImage: FileImage(_imageFile!),
      );
    } else if (_profilePictureUrl != null) {
      child = CircleAvatar(
        radius: 60,
        backgroundImage: NetworkImage(_profilePictureUrl!),
      );
    } else {
      child = CircleAvatar(
        radius: 60,
        backgroundColor: Colors.white24,
        child: Icon(
          Icons.person,
          size: 60,
          color: Colors.white.withOpacity(0.7),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: child,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.purple.shade300, width: 2),
              ),
              child: Icon(Icons.edit, color: Colors.purple.shade300, size: 20),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ),
    );
  }

  Widget _buildInterestsGrid() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        spacing: 12.0,
        runSpacing: 12.0,
        children: _allInterests.map((interest) {
          final isSelected = _selectedInterests.contains(interest);
          return FilterChip(
            label: Text(interest),
            selected: isSelected,
            onSelected: (bool selected) {
              setState(() {
                if (selected) {
                  _selectedInterests.add(interest);
                } else {
                  _selectedInterests.remove(interest);
                }
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
                color:
                    isSelected ? Colors.white : Colors.white.withOpacity(0.2),
                width: 0,
              ),
            ),
            checkmarkColor: Colors.purple.shade300,
          );
        }).toList(),
      ),
    );
  }
}
