import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class InterestButton extends StatelessWidget {
  final bool interested;
  final VoidCallback onPressed;
  final double size;
  final EdgeInsets padding;

  const InterestButton({
    super.key,
    required this.interested,
    required this.onPressed,
    this.size = 24,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;

    // Use platform-specific icons for a native feel and visual consistency
    final IconData icon =
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS)
            ? (interested ? CupertinoIcons.star_fill : CupertinoIcons.star)
            : (interested ? Icons.star : Icons.star_border_outlined); // Using the outlined version for consistency

    final Color color =
        interested ? Colors.yellow.shade600 : Colors.white;

    // ValueKey ensures Flutter doesn't recycle a stale icon during rebuilds
    return IconButton(
      key: ValueKey('interest-$interested'),
      padding: padding,
      icon: Icon(icon, size: size, color: color),
      onPressed: onPressed,
      tooltip: interested ? 'Remove from Saved' : 'Save',
      // Adding a simple background to match the existing UI
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withOpacity(0.3),
      ),
    );
  }
}