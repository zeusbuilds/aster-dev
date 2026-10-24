import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/shared/feedback/feedback.dart';

final class RecordingHapticFeedbackService implements HapticFeedbackService {
  final intents = <HapticIntent>[];

  @override
  Future<void> trigger(HapticIntent intent) async => intents.add(intent);
}

final class RecordedToast {
  const RecordedToast({
    required this.title,
    required this.variant,
    this.message,
  });

  final String title;
  final String? message;
  final ToastVariant variant;
}

final class RecordingToastPresentationService
    implements ToastPresentationService {
  final messages = <RecordedToast>[];

  @override
  bool show({
    required String title,
    required ToastVariant variant,
    String? message,
    Duration? duration,
  }) {
    messages.add(
      RecordedToast(title: title, message: message, variant: variant),
    );
    return true;
  }

  @override
  void dismissCurrent({int? id}) {}
}

final class MemoryClipboardService implements ClipboardService {
  Completer<void>? readGate;
  String? text;
  AppFailure? readFailure;
  AppFailure? writeFailure;

  @override
  Future<AppResult<String?>> readText() async {
    await readGate?.future;
    final failure = readFailure;
    return failure == null
        ? AppResult.success(text)
        : AppResult.failure(failure);
  }

  @override
  Future<AppResult<void>> writeText(String value) async {
    final failure = writeFailure;
    if (failure != null) return AppResult.failure(failure);
    text = value;
    return const AppResult.success(null);
  }
}

final class RecordingShareService implements ShareService {
  AppResult<ShareDisposition> result = const AppResult.success(
    ShareDisposition.completed,
  );
  String? sharedText;
  String? sharedSubject;
  ShareOrigin? sharedOrigin;

  @override
  Future<AppResult<ShareDisposition>> shareText(
    String text, {
    String? subject,
    ShareOrigin? origin,
  }) async {
    sharedText = text;
    sharedSubject = subject;
    sharedOrigin = origin;
    return result;
  }
}

final class RecordingExternalUriService implements ExternalUriService {
  AppResult<void> result = const AppResult.success(null);
  Uri? openedUri;

  @override
  Future<AppResult<void>> open(Uri uri) async {
    openedUri = uri;
    return result;
  }
}
