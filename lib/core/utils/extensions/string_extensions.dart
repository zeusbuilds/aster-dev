/// String extension utilities
extension StringExtensions on String {
  /// Capitalizes first letter
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Capitalizes first letter of each word
  String capitalizeWords() {
    return split(' ').map((word) => word.capitalize()).join(' ');
  }

  /// Truncates string to max length with ellipsis
  String truncate(int maxLength) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}...';
  }

  /// Checks if string is a valid email
  bool get isValidEmail {
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(this);
  }

  /// Checks if string is a valid URL
  bool get isValidUrl {
    return RegExp(
      r'^https?://[^\s/$.?#].[^\s]*$',
      caseSensitive: false,
    ).hasMatch(this);
  }
}

