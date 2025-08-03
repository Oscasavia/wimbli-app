import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wimbli/pages/auth/splash_screen.dart';
import 'package:app_links/app_links.dart';
// Assuming you place auth_gate.dart in 'lib/pages/' or adjust the path as needed
// import 'package:wimbli/pages/auth_gate.dart';
import 'package:wimbli/models/event_model.dart';
import 'package:wimbli/pages/main/event_details_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Make main async
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase
  await Firebase.initializeApp();
  await _initAppLinks();

  // Set system UI styles for edge-to-edge display
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.poppinsTextTheme(
          Theme.of(context).textTheme,
        ),
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.purple,
          brightness: Brightness.dark,
          primary: Colors.white,
          secondary: Colors.purple.shade300,
        ),
      ),
      // Use AuthGate as the entry point for your app
      // home: const AuthGate(),
      home: const SplashScreen(),
    );
  }
}

Future<void> _initAppLinks() async {
  final appLinks = AppLinks();

  // Listen for links when the app is already open
  appLinks.uriLinkStream.listen((uri) {
    _handleDeepLink(uri);
  });

  // Handle the link that opened the app from a terminated state
  final initialUri = await appLinks.getInitialAppLink();
  if (initialUri != null) {
    _handleDeepLink(initialUri);
  }
}

void _handleDeepLink(Uri deepLink) async {
  if (deepLink.host == 'wimbli.app' &&
      deepLink.pathSegments.length == 2 &&
      deepLink.pathSegments.first == 'event') {
    final String eventId = deepLink.pathSegments.last;
    final context = navigatorKey.currentContext;

    if (eventId.isNotEmpty && context != null && context.mounted) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('posts')
            .doc(eventId)
            .get();
        if (doc.exists) {
          final event = Event.fromFirestore(doc);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => EventDetailsPage(event: event),
          ));
        }
      } catch (e) {
        // Handle error
      }
    }
  }
}
