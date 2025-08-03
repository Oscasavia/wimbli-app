import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wimbli/pages/app_shell.dart';
import 'package:wimbli/pages/auth/login_page.dart';
import 'package:wimbli/pages/onboarding/interests_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoginPage();
        }

        // User is logged in, check if their profile setup is complete.
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .snapshots(),
          builder: (context, userDocSnapshot) {
            if (userDocSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            if (!userDocSnapshot.hasData || !userDocSnapshot.data!.exists) {
              return const InterestsPage();
            }
            
            final userData = userDocSnapshot.data!.data() as Map<String, dynamic>;
            final bool setupCompleted = userData['profileSetupCompleted'] ?? false;

            if (setupCompleted) {
              return const AppShell();
            } else {
              return const InterestsPage();
            }
          },
        );
      },
    );
  }
}