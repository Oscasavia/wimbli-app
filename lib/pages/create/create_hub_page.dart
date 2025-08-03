import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:wimbli/pages/create/create_event_page.dart';

class CreateHubPage extends StatelessWidget {
  const CreateHubPage({super.key});

  void _navigateToCreateEvent(BuildContext context, bool isPrivate) {
    Navigator.pop(context); // Close the modal sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEventPage(isPrivate: isPrivate),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          24.0,  // left
          24.0,  // top
          24.0,  // right
          48.0,  // bottom
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Create an Event', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
            const SizedBox(height: 24),
            _buildOptionCard(
              context,
              icon: Icons.public,
              title: 'Public Event',
              subtitle: 'Visible to everyone on Wimbli',
              onTap: () => _navigateToCreateEvent(context, false),
            ),
            const SizedBox(height: 16),
            _buildOptionCard(
              context,
              icon: Icons.lock,
              title: 'Private Event',
              subtitle: 'Only visible to people you invite',
              onTap: () => _navigateToCreateEvent(context, true),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.8))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
