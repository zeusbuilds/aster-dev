import com.android.bundle.Config.BundleConfig;
import com.android.bundle.Config.UncompressNativeLibraries;
import com.google.protobuf.CodedInputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;

/** Verifies page alignment in an already-extracted bundle configuration. */
public final class BundleConfigInspector {
  private static final int MAX_PROTOBUF_BYTES = 16 * 1024 * 1024;

  private BundleConfigInspector() {}

  public static void main(String[] arguments) throws Exception {
    if (arguments.length != 1) {
      throw new IllegalArgumentException("Expected exactly one extracted BundleConfig path");
    }

    Path configPath = requireBoundedProtobuf(Path.of(arguments[0]));
    try (InputStream input = Files.newInputStream(configPath)) {
      CodedInputStream codedInput = CodedInputStream.newInstance(input);
      codedInput.setSizeLimit(MAX_PROTOBUF_BYTES);
      BundleConfig config = BundleConfig.parseFrom(codedInput);
      UncompressNativeLibraries nativeLibraries =
          config.getOptimizations().getUncompressNativeLibraries();
      if (!nativeLibraries.getEnabled()) {
        throw new IllegalStateException("Native-library uncompression is disabled");
      }
      if (nativeLibraries.getAlignment()
          != UncompressNativeLibraries.PageAlignment.PAGE_ALIGNMENT_16K) {
        throw new IllegalStateException(
            "Expected PAGE_ALIGNMENT_16K but found " + nativeLibraries.getAlignment());
      }
      System.out.println("Verified bundle requests PAGE_ALIGNMENT_16K");
    }
  }

  private static Path requireBoundedProtobuf(Path input) throws Exception {
    if (!Files.isRegularFile(input, LinkOption.NOFOLLOW_LINKS)) {
      throw new IllegalArgumentException("BundleConfig input is not a regular file");
    }
    long size = Files.size(input);
    if (size <= 0 || size > MAX_PROTOBUF_BYTES) {
      throw new IllegalArgumentException(
          "BundleConfig protobuf size is outside the permitted range");
    }
    return input;
  }
}
