import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
// The AuthGate will handle navigation, so we don't need to import InterestsPage here.

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _agreedToTerms = false;
  bool _isPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showErrorSnackBar('Could not launch $url');
    }
  }

  Future<void> _signUp() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    // --- Validation ---
    if (_usernameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty ||
        _confirmPasswordController.text.trim().isEmpty) {
      _showErrorSnackBar('Please fill in all fields.');
      return;
    }
    if (_usernameController.text.trim().length < 3) {
      _showErrorSnackBar('Username must be at least 3 characters long.');
      return;
    }
    if (_passwordController.text.trim().length < 8) {
      _showErrorSnackBar('Password must be at least 8 characters long.');
      return;
    }
    if (_passwordController.text.trim() !=
        _confirmPasswordController.text.trim()) {
      _showErrorSnackBar('Passwords do not match.');
      return;
    }
    if (!_agreedToTerms) {
      _showErrorSnackBar('You must agree to the Terms and Privacy Policy.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Create user in Firebase Auth. This is the primary check for email uniqueness.
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      User? user = userCredential.user;

      if (user != null) {
        // 2. Update user's display name in Auth
        await user.updateDisplayName(_usernameController.text.trim());

        // 3. Create user document in Firestore.
        // The AuthGate will now take over navigation once this document is created.
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'username': _usernameController.text.trim(),
          'username_lowercase': _usernameController.text.trim().toLowerCase(),
          'email': _emailController.text.trim(),
          'createdAt': Timestamp.now(),
          'interests': [],
          'profilePicture': null,
          'bio': "",
          'profileSetupCompleted':
              false, // This flag is crucial for the AuthGate
        });

        // 4. IMPORTANT: Pop all pages until we get back to the root (AuthGate).
        // This clears the SignUp and Login pages from the navigation stack.
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered. Please log in.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'weak-password':
          message = 'The password is too weak.';
          break;
        default:
          message = 'An error occurred during sign-up. Please try again.';
          break;
      }
      _showErrorSnackBar(message);
    } catch (e) {
      // Generic catch for any other errors (like Firestore permission errors or network issues)
      _showErrorSnackBar(
          'An unexpected error occurred. Please check your connection and try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final safeArea = MediaQuery.of(context).padding;
    final minHeight = screenHeight - safeArea.top - safeArea.bottom;

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
            child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset(
                          'assets/wimbliLogoWhite.png',
                          height: 100,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 6),
                        Text('Wimbli',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.pacifico(
                                fontSize: 60,
                                // fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 16),
                        Text('Create your account',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 18,
                                color: Colors.white.withOpacity(0.9))),
                        const SizedBox(height: 48),
                        _buildUsernameField(),
                        const SizedBox(height: 20),
                        _buildEmailField(),
                        const SizedBox(height: 20),
                        _buildPasswordField(
                          controller: _passwordController,
                          labelText: 'Password',
                          isObscured: _isPasswordObscured,
                          onToggleVisibility: () {
                            setState(() {
                              _isPasswordObscured = !_isPasswordObscured;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildPasswordField(
                          controller: _confirmPasswordController,
                          labelText: 'Confirm Password',
                          isObscured: _isConfirmPasswordObscured,
                          onToggleVisibility: () {
                            setState(() {
                              _isConfirmPasswordObscured =
                                  !_isConfirmPasswordObscured;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                  value: _agreedToTerms,
                                  onChanged: (value) =>
                                      setState(() => _agreedToTerms = value!),
                                  activeColor: Colors.white,
                                  checkColor: Colors.purple.shade400,
                                  side:
                                      const BorderSide(color: Colors.white70))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: RichText(
                                  text: TextSpan(
                                      text: 'I agree to the ',
                                      style:
                                          const TextStyle(color: Colors.white),
                                      children: [
                                TextSpan(
                                    text: 'Terms',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        _launchURL('https://wimbli.app/terms');
                                      }),
                                const TextSpan(text: ' and '),
                                TextSpan(
                                    text: 'Privacy Policy',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        _launchURL(
                                            'https://wimbli.app/privacy');
                                      })
                              ])))
                        ]),
                        const SizedBox(height: 32),
                        ElevatedButton(
                            onPressed: _isLoading ? null : _signUp,
                            style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.purple.shade700,
                                backgroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30))),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.purple),
                                  )
                                : const Text('SIGN UP',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold))),
                        const SizedBox(height: 40),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Already have an account?",
                                  style: TextStyle(color: Colors.white70)),
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Login',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)))
                            ])
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        )),
      ),
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Username',
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
        prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.emailAddress,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Email',
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
        prefixIcon: const Icon(Icons.email_outlined, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String labelText,
    required bool isObscured,
    required VoidCallback onToggleVisibility,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isObscured,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
        prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
        suffixIcon: IconButton(
          icon: Icon(
            isObscured
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.white70,
          ),
          onPressed: onToggleVisibility,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Colors.white),
        ),
      ),
    );
  }
}
