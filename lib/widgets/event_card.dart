import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wimbli/models/event_model.dart';
import 'package:wimbli/constants/app_data.dart'; // <-- ADD THIS IMPORT
import 'package:wimbli/models/app_category.dart';   // <-- ADD THIS IMPORT

// Helper to get an icon for a category
IconData _getIconForCategory(String categoryName) {
  // Find the category in the appCategories list, or use a default icon if not found.
  final category = appCategories.firstWhere(
    (c) => c.name == categoryName,
    orElse: () => const AppCategory(name: 'Default', icon: Icons.event, color: Colors.grey),
  );
  return category.icon;
}

class FeaturedEventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onToggleSave;

  const FeaturedEventCard({
    super.key,
    required this.event,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    bool hasImage = event.imageUrl.isNotEmpty;

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      clipBehavior: Clip.antiAlias, // Ensures content respects border radius
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        // Use a gradient if no image is available
        gradient: !hasImage
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.purple.shade300,
                  Colors.blue.shade300,
                ],
              )
            : null,
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(event.imageUrl),
                fit: BoxFit.cover,
                onError: (exception, stackTrace) {}, // Handle image load errors
              )
            : null,
      ),
      child: Stack(
        children: [
          // Show a placeholder icon if no image
          if (!hasImage)
            Center(
              child: Icon(
                _getIconForCategory(event.category),
                color: Colors.white.withOpacity(0.3),
                size: 100,
              ),
            ),
          // The content overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                stops: const [0.5, 1.0],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 10.0, color: Colors.black)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.white70, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location,
                          style: const TextStyle(color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMM d, yyyy').format(event.date),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      GestureDetector(
                        onTap: onToggleSave,
                        child: Row(
                          children: [
                            Icon(
                              event.isInterested ? Icons.star : Icons.star_border,
                              color: event.isInterested ? Colors.yellow.shade600 : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              event.interestedCount.toString(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ForYouEventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onToggleSave;

  const ForYouEventCard({
    super.key,
    required this.event,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    bool hasImage = event.imageUrl.isNotEmpty;

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomLeft: Radius.circular(20),
              ),
              gradient: !hasImage
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.purple.shade400,
                        Colors.blue.shade400,
                      ],
                    )
                  : null,
              image: hasImage
                  ? DecorationImage(
                      image: NetworkImage(event.imageUrl),
                      fit: BoxFit.cover,
                      onError: (exception, stackTrace) {},
                    )
                  : null,
            ),
            child: !hasImage
                ? Center(
                    child: Icon(
                      _getIconForCategory(event.category),
                      color: Colors.white.withOpacity(0.5),
                      size: 50,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  _buildInfoRow(Icons.location_on, event.location),
                  _buildInfoRow(Icons.access_time, DateFormat('MMM d, h:mm a').format(event.date)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: onToggleSave,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    event.isInterested ? Icons.star : Icons.star_border,
                    color: event.isInterested ? Colors.yellow.shade600 : Colors.white,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.interestedCount.toString(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}