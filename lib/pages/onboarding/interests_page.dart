import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wimbli/constants/app_data.dart';
// import 'package:wimbli/pages/app_shell.dart';

class InterestsPage extends StatefulWidget {
  const InterestsPage({super.key});
  @override
  State<InterestsPage> createState() => _InterestsPageState();
}

class _InterestsPageState extends State<InterestsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  final List<String> _interests = appCategories.map((c) => c.name).toList();
  final Set<String> _selectedInterests = {};

  @override
  void initState() {
    super.initState();
    _fetchUserInterests();
  }

  Future<void> _fetchUserInterests() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists && userDoc.data()!.containsKey('interests')) {
          final interestsFromServer =
              List<String>.from(userDoc.data()!['interests']);
          setState(() {
            _selectedInterests.addAll(interestsFromServer);
          });
        }
      }
    } catch (e) {
      _showErrorSnackBar('Could not load your interests. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveInterests() async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not found");
      }
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'interests': _selectedInterests.toList(),
        'profileSetupCompleted': true,
      }, SetOptions(merge: true));

      // if (mounted) {
      //   Navigator.pushAndRemoveUntil(
      //     context,
      //     MaterialPageRoute(builder: (_) => const AppShell()),
      //     (route) => false,
      //   );
      // }
    } catch (e) {
      _showErrorSnackBar('Could not save your interests. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _skipAndContinue() async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not found");
      }
      // Set profile as complete but save an EMPTY list for interests.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'interests': [], // This is the key change
        'profileSetupCompleted': true,
      }, SetOptions(merge: true));

      // Your AuthGate will automatically handle the navigation from here.
    } catch (e) {
      _showErrorSnackBar('An error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
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
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32.0, vertical: 20.0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Select Your Interests',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          const SizedBox(height: 12),
                          Text(
                              'Choose a few of your favorite things to personalize your experience.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withOpacity(0.9))),
                          const SizedBox(height: 40),
                          Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12.0,
                              runSpacing: 12.0,
                              children: _interests.map((interest) {
                                final isSelected =
                                    _selectedInterests.contains(interest);
                                return FilterChip(
                                    label: Text(interest),
                                    selected: isSelected,
                                    onSelected: (bool selected) => setState(
                                        () => selected
                                            ? _selectedInterests.add(interest)
                                            : _selectedInterests
                                                .remove(interest)),
                                    backgroundColor:
                                        Colors.white.withOpacity(0.2),
                                    selectedColor: Colors.white,
                                    labelStyle: TextStyle(
                                        color: isSelected
                                            ? Colors.purple.shade700
                                            : Colors.white,
                                        fontWeight: FontWeight.bold),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        side: BorderSide(
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.white.withOpacity(0.4),
                                            width: 2)),
                                    checkmarkColor: Colors.purple.shade300);
                              }).toList()),
                          const SizedBox(height: 48),
                          ElevatedButton(
                              onPressed:
                                  (_isSaving || _selectedInterests.isEmpty)
                                      ? null
                                      : _saveInterests,
                              style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.purple.shade700,
                                  backgroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      Colors.white.withOpacity(0.5),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30))),
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.purple),
                                    )
                                  : const Text('CONTINUE',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold))),
                          const SizedBox(height: 16),
                          TextButton(
                              onPressed: _isSaving ? null : _skipAndContinue,
                              child: const Text('Skip for now',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)))
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
