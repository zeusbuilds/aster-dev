# Release diagnostics flow through app-owned, redacted boundaries. Third-party
# Android Log calls can expose implementation details and are never a release
# error-reporting contract.
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
    public static int wtf(...);
}
