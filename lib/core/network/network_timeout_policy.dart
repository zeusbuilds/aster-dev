/// Explicit deadlines for HTTP transport stages and whole operations.
final class NetworkTimeoutPolicy {
  const NetworkTimeoutPolicy({
    this.connect = const Duration(seconds: 15),
    this.receive = const Duration(seconds: 20),
    this.operation = const Duration(seconds: 45),
  });

  final Duration connect;
  final Duration receive;
  final Duration operation;
}
