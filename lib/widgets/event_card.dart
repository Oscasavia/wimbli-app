import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wimbli/models/event_model.dart';
import 'package:wimbli/constants/app_data.dart';
import 'package:wimbli/models/app_category.dart';

// Helper to get an icon for a category
IconData _getIconForCategory(String categoryName) {
  // Find the category in the appCategories list, or use a default icon if not found.
  final category = appCategories.firstWhere(
    (c) => c.name == categoryName,
    orElse: () => const AppCategory(
        name: 'Default', icon: Icons.event, color: Colors.grey),
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

          // Gradient overlay for text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                stops: const [0.4, 1.0],
              ),
            ),
          ),

          // Bottom Info Section
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: const BorderRadius.only(
                  bottomLeft:
                      Radius.circular(15.0), // Adjust the value as needed
                  bottomRight: Radius.circular(15.0),
                  topLeft: Radius.circular(0.0),
                  topRight: Radius.circular(0.0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.white70, size: 16),
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
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d, yyyy').format(event.date),
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),

          // Category Chip (Top Left)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(_getIconForCategory(event.category),
                      color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(event.category,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ],
              ),
            ),
          ),

          // Star Icon & Counter (Top Right)
          Positioned(
            top: 16,
            right: 16,
            child: GestureDetector(
              onTap: onToggleSave,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      event.isInterested
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: event.isInterested
                          ? Colors.yellow.shade600
                          : Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      event.interestedCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  _buildInfoRow(Icons.location_on, event.location),
                  _buildInfoRow(Icons.access_time,
                      DateFormat('MMM d, h:mm a').format(event.date)),
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
                    color: event.isInterested
                        ? Colors.yellow.shade600
                        : Colors.white,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.interestedCount.toString(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
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
            style:
                TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
