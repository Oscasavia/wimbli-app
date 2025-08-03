import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// A simple model for the FAQ items
class FaqItem {
  final String question;
  final String answer;

  FaqItem({required this.question, required this.answer});
}

class HelpAndSupportPage extends StatelessWidget {
  HelpAndSupportPage({super.key});

  // --- Contact & FAQ Data ---
  static const String _supportEmail = "wimbliapp@gmail.com";
  final List<FaqItem> faqs = [
    FaqItem(
      question: 'How do I create an event?',
      answer:
          'From the main navigation bar, tap the central "Create" button. You can then choose to create a public or private event and fill in all the necessary details.',
    ),
    FaqItem(
      question: 'Can I edit an event after creating it?',
      answer:
          'Yes, if you are the creator of an event, you can edit it. Navigate to the event details page and tap the menu icon (three dots) in the top right corner to find the "Edit" option.',
    ),
    FaqItem(
      question: 'How do I change my profile picture or bio?',
      answer:
          'Navigate to your profile page and tap the "Edit Profile" button. This will take you to a screen where you can update your profile information, including your picture, username, and bio.',
    ),
    FaqItem(
      question: 'What happens when I block a user?',
      answer:
          'When you block a user, they will no longer be able to see your profile, view your events, or interact with you in any way. You can manage your blocked users list in the Settings.',
    ),
     FaqItem(
      question: 'How do I save an event I\'m interested in?',
      answer:
          'On the event details page, tap the star icon. The event will then be added to the "Interested" tab on your profile page.',
    ),
    FaqItem(
      question: 'Where can I see the events I\'ve created?',
      answer:
          'The events you have created will appear under the "Posts" tab on your profile page.',
    ),
  ];

  Future<void> _launchEmail(BuildContext context, {required String subject}) async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );

    if (!await launchUrl(emailLaunchUri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open email app.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              title: Text('Help & Support',
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('Frequently Asked Questions'),
                    _buildFaqList(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Contact Us'),
                    _buildContactCard(context),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),)
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildFaqList() {
    return Card(
      color: Colors.white.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: faqs.length,
        itemBuilder: (context, index) {
          final faq = faqs[index];
          return ExpansionTile(
            title: Text(
              faq.question,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            iconColor: Colors.white70,
            collapsedIconColor: Colors.white70,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  faq.answer,
                  style: TextStyle(color: Colors.white.withOpacity(0.9), height: 1.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContactCard(BuildContext context) {
    return Card(
      color: Colors.white.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.mail_outline, color: Colors.white),
            title: const Text('Email Support', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
            onTap: () => _launchEmail(context, subject: 'Wimbli App Support Request'),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined, color: Colors.white),
            title: const Text('Report an Issue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
            onTap: () => _launchEmail(context, subject: 'Wimbli App - Issue Report'),
          ),
        ],
      ),
    );
  }
}
