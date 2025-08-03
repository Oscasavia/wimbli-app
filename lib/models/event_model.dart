import 'package:cloud_firestore/cloud_firestore.dart';

class Event {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String location;
  final String category;
  final DateTime date;
  final String createdBy; // This is the UID
  final String creatorUsername;
  final String? creatorProfilePic;
  final double fee;
  final String duration;
  final GeoPoint? coordinates;
  final bool isPrivate;
  int interestedCount;
  bool isInterested;
  final List<String> likedBy;
  final List<String> invitedUsers;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.location,
    required this.category,
    required this.date,
    required this.createdBy,
    required this.creatorUsername,
    this.creatorProfilePic,
    required this.fee,
    required this.duration,
    this.coordinates,
    required this.isPrivate,
    this.interestedCount = 0,
    this.isInterested = false,
    required this.likedBy,
    required this.invitedUsers,
  });

  // Factory constructor to create an Event from a Firestore document
  factory Event.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      location: data['location'] ?? '',
      category: data['category'] ?? 'Other',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      creatorUsername: data['creatorUsername'] ?? 'A User',
      creatorProfilePic: data['creatorProfilePic'], // Can be null
      fee: (data['fee'] ?? 0.0).toDouble(),
      duration: data['duration'] ?? '',
      coordinates: data['coordinates'] as GeoPoint?, // Correctly read coordinates
      isPrivate: data['isPrivate'] ?? false, // Correctly read isPrivate
      interestedCount: data['interestedCount'] ?? 0,
      isInterested: false, // This is a client-side state
      likedBy: List<String>.from(data['likedBy'] ?? []),
      invitedUsers: List<String>.from(data['invitedUsers'] ?? []),
    );
  }
}
