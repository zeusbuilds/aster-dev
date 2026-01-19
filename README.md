# Aster

<img src="assets/brand/banner.png" alt="Banner">

Aster - A secure Bitcoin & Layer 2 wallet built with Flutter

## Requirements

- **Flutter**: ^3.22.0
- **Dart SDK**: ^3.9.0

## Getting Started

### Installation

1. Install dependencies:
```bash
flutter pub get
```

2. Generate code (required for freezed, json_serializable, riverpod_generator, etc.):
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Running the App

Run the app on a connected device or emulator:
```bash
flutter run
```

### Development Commands

- **Watch mode for code generation** (auto-regenerates on file changes):
```bash
flutter pub run build_runner watch --delete-conflicting-outputs
```

- **Clean build**:
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

- **Run tests**:
```bash
flutter test
```

## Resources

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
