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

  const FeaturedEventCard({
    super.key,
    required this.event,
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
        ],
      ),
    );
  }
}

class ForYouEventCard extends StatelessWidget {
  final Event event;

  const ForYouEventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final hasImage = event.imageUrl.isNotEmpty;
    const cardHeight = 300.0;

    return Container(
      width: double.infinity,
      height: cardHeight,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.grey.shade800,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Tune these two numbers:
          const infoMinHeight = 96.0; // enough space for 3 compact rows
          const infoMaxHeight = 124.0; // avoid “too tall / airy” look

          final total = constraints.maxHeight;
          final imageHeight =
              (total - infoMinHeight).clamp(140.0, total - 72.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // IMAGE SECTION (takes remaining space automatically)
              SizedBox(
                height: imageHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: hasImage
                          ? Image.network(
                              event.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) =>
                                  _fallbackGradient(),
                            )
                          : _fallbackGradient(),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          event.category,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // INFO SECTION (no Expanded, bounded height)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: infoMinHeight,
                  maxHeight: infoMaxHeight,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    // START (not center) avoids the “too much vertical padding” look
                    mainAxisAlignment: MainAxisAlignment.start,
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
                      const SizedBox(height: 6),
                      _buildInfoRow(Icons.location_on, event.location),
                      const SizedBox(height: 4),
                      _buildInfoRow(
                        Icons.access_time,
                        DateFormat('MMM d, h:mm a').format(event.date),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fallbackGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.shade400,
            Colors.blue.shade400,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _getIconForCategory(event.category),
          color: Colors.white.withOpacity(0.5),
          size: 60,
        ),
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
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  IconData _getIconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'sports':
        return Icons.sports_soccer;
      case 'music':
        return Icons.music_note;
      case 'games':
        return Icons.videogame_asset;
      default:
        return Icons.event;
    }
  }
}
