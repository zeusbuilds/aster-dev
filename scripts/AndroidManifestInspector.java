import com.android.aapt.Resources.XmlAttribute;
import com.android.aapt.Resources.XmlElement;
import com.android.aapt.Resources.XmlNode;
import com.google.protobuf.CodedInputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;

/** Reads release identity from an already-extracted protobuf manifest. */
public final class AndroidManifestInspector {
  private static final int MAX_PROTOBUF_BYTES = 16 * 1024 * 1024;
  private static final int MAX_MANIFEST_ATTRIBUTES = 1024;
  private static final int MAX_ATTRIBUTE_VALUE_LENGTH = 4096;
  private static final String ANDROID_NAMESPACE =
      "http://schemas.android.com/apk/res/android";

  private AndroidManifestInspector() {}

  public static void main(String[] arguments) throws Exception {
    if (arguments.length != 1) {
      throw new IllegalArgumentException("Expected exactly one extracted manifest path");
    }

    Path manifestPath = requireBoundedProtobuf(Path.of(arguments[0]));
    try (InputStream input = Files.newInputStream(manifestPath)) {
      CodedInputStream codedInput = CodedInputStream.newInstance(input);
      codedInput.setSizeLimit(MAX_PROTOBUF_BYTES);
      XmlNode root = XmlNode.parseFrom(codedInput);
      if (!root.hasElement() || !"manifest".equals(root.getElement().getName())) {
        throw new IllegalStateException("Bundle manifest root is not <manifest>");
      }
      XmlElement manifest = root.getElement();
      emit("ASTER_APPLICATION_ID", requireAttribute(manifest, "", "package"));
      emit(
          "ASTER_VERSION_CODE",
          requireAttribute(manifest, ANDROID_NAMESPACE, "versionCode"));
      emit(
          "ASTER_VERSION_NAME",
          requireAttribute(manifest, ANDROID_NAMESPACE, "versionName"));
    }
  }

  private static Path requireBoundedProtobuf(Path input) throws Exception {
    if (!Files.isRegularFile(input, LinkOption.NOFOLLOW_LINKS)) {
      throw new IllegalArgumentException("Manifest input is not a regular file");
    }
    long size = Files.size(input);
    if (size <= 0 || size > MAX_PROTOBUF_BYTES) {
      throw new IllegalArgumentException("Manifest protobuf size is outside the permitted range");
    }
    return input;
  }

  private static String requireAttribute(
      XmlElement element, String namespaceUri, String name) {
    if (element.getAttributeCount() > MAX_MANIFEST_ATTRIBUTES) {
      throw new IllegalStateException("Bundle manifest has too many attributes");
    }
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
    if (value.length() > MAX_ATTRIBUTE_VALUE_LENGTH) {
      throw new IllegalStateException("Manifest attribute is too long: " + name);
    }
    for (int index = 0; index < value.length(); index++) {
      if (Character.isISOControl(value.charAt(index))) {
        throw new IllegalStateException("Invalid manifest attribute " + name);
      }
    }
    return value;
  }

  private static void emit(String key, String value) {
    System.out.println(key + "=" + value);
  }
}
