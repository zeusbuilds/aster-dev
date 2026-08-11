import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../errors/errors.dart';

/// Outcome of a platform share sheet that was opened successfully.
enum ShareDisposition { completed, dismissed }

/// Adapter-level result used to inject deterministic share behavior in tests.
enum ShareInvocationOutcome { completed, dismissed, unavailable }

/// Platform-independent geometry used to anchor share UI on large displays.
@immutable
final class ShareOrigin {
  const ShareOrigin({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(width > 0),
       assert(height > 0);

  final double left;
  final double top;
  final double width;
  final double height;

  /// Whether this rectangle can be forwarded to a platform popover safely.
  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width > 0 &&
      height > 0;
}

typedef ShareTextInvoker =
    Future<ShareInvocationOutcome> Function(
      String text,
      String? subject,
      ShareOrigin? origin,
    );

/// System share boundary for non-secret payment requests.
abstract interface class ShareService {
  Future<AppResult<ShareDisposition>> shareText(
    String text, {
    String? subject,
    ShareOrigin? origin,
  });
}

/// `share_plus` adapter kept outside feature presentation code.
final class PlatformShareService implements ShareService {
  PlatformShareService({ShareTextInvoker? invoker})
    : _invoker = invoker ?? _invokePlatformShare;

  static const maximumTextCharacters = 8192;
  static const maximumSubjectCharacters = 160;
  final ShareTextInvoker _invoker;

  @override
  Future<AppResult<ShareDisposition>> shareText(
    String text, {
    String? subject,
    ShareOrigin? origin,
  }) async {
    if (text.trim().isEmpty ||
        text.length > maximumTextCharacters ||
        (subject != null &&
            (subject.trim().isEmpty ||
                subject.length > maximumSubjectCharacters)) ||
        (origin != null && !origin.isValid)) {
      return AppResult.failure(_invalidShareFailure());
    }
    try {
      final outcome = await _invoker(text, subject, origin);
      return switch (outcome) {
        ShareInvocationOutcome.completed => const AppResult.success(
          ShareDisposition.completed,
        ),
        ShareInvocationOutcome.dismissed => const AppResult.success(
          ShareDisposition.dismissed,
        ),
        ShareInvocationOutcome.unavailable => AppResult.failure(
          const AppFailure(
            code: 'share_unavailable',
            kind: AppFailureKind.unavailable,
            userMessage: 'Sharing is unavailable on this device.',
            retryable: false,
          ),
        ),
      };
    } catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'share_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'The payment request could not be shared.',
          retryable: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static AppFailure _invalidShareFailure() => const AppFailure(
    code: 'share_value_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'The payment request could not be shared.',
    retryable: false,
  );

  static Future<ShareInvocationOutcome> _invokePlatformShare(
    String text,
    String? subject,
    ShareOrigin? origin,
  ) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        sharePositionOrigin: origin == null
            ? null
            : Rect.fromLTWH(
                origin.left,
                origin.top,
                origin.width,
                origin.height,
              ),
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => ShareInvocationOutcome.completed,
      ShareResultStatus.dismissed => ShareInvocationOutcome.dismissed,
      ShareResultStatus.unavailable => ShareInvocationOutcome.unavailable,
    };
  }
}
