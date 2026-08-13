import com.android.bundle.Config.BundleConfig;
import com.android.bundle.Config.UncompressNativeLibraries;
import java.io.InputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Verifies the native-library page-alignment request in an Android App Bundle. */
public final class BundleConfigInspector {
  private BundleConfigInspector() {}

  public static void main(String[] arguments) throws Exception {
    if (arguments.length != 1) {
      throw new IllegalArgumentException("Expected exactly one Android App Bundle path");
    }

    try (ZipFile bundle = new ZipFile(arguments[0])) {
      ZipEntry entry = bundle.getEntry("BundleConfig.pb");
      if (entry == null) {
        throw new IllegalStateException("BundleConfig.pb is missing");
      }
      try (InputStream input = bundle.getInputStream(entry)) {
        BundleConfig config = BundleConfig.parseFrom(input);
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
  }
}
