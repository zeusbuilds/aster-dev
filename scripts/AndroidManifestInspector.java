import com.android.aapt.Resources.XmlAttribute;
import com.android.aapt.Resources.XmlElement;
import com.android.aapt.Resources.XmlNode;
import java.io.InputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Reads release identity from an Android App Bundle's protobuf manifest. */
public final class AndroidManifestInspector {
  private static final String ANDROID_NAMESPACE =
      "http://schemas.android.com/apk/res/android";

  private AndroidManifestInspector() {}

  public static void main(String[] arguments) throws Exception {
    if (arguments.length != 1) {
      throw new IllegalArgumentException("Expected exactly one Android App Bundle path");
    }

    try (ZipFile bundle = new ZipFile(arguments[0])) {
      ZipEntry entry = bundle.getEntry("base/manifest/AndroidManifest.xml");
      if (entry == null) {
        throw new IllegalStateException("Base AndroidManifest.xml is missing");
      }
      try (InputStream input = bundle.getInputStream(entry)) {
        XmlNode root = XmlNode.parseFrom(input);
        if (!root.hasElement() || !"manifest".equals(root.getElement().getName())) {
          throw new IllegalStateException("Bundle manifest root is not <manifest>");
        }
        XmlElement manifest = root.getElement();
        emit(
            "UTEXO_APPLICATION_ID",
            requireAttribute(manifest, "", "package"));
        emit(
            "UTEXO_VERSION_CODE",
            requireAttribute(manifest, ANDROID_NAMESPACE, "versionCode"));
        emit(
            "UTEXO_VERSION_NAME",
            requireAttribute(manifest, ANDROID_NAMESPACE, "versionName"));
      }
    }
  }

  private static String requireAttribute(
      XmlElement element, String namespaceUri, String name) {
    String value = null;
    for (XmlAttribute attribute : element.getAttributeList()) {
      if (namespaceUri.equals(attribute.getNamespaceUri()) && name.equals(attribute.getName())) {
        if (value != null) {
          throw new IllegalStateException("Duplicate manifest attribute " + name);
        }
        value = attribute.getValue();
      }
    }
    if (value == null || value.isEmpty()) {
      throw new IllegalStateException("Missing manifest attribute " + name);
    }
    if (value.indexOf('\n') >= 0 || value.indexOf('\r') >= 0) {
      throw new IllegalStateException("Invalid manifest attribute " + name);
    }
    return value;
  }

  private static void emit(String key, String value) {
    System.out.println(key + "=" + value);
  }
}
