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
