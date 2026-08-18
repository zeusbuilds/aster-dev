import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.CodeSigner;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.cert.Certificate;
import java.security.cert.CertificateEncodingException;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

/** Verifies complete JAR signing coverage and emits one signer identity. */
public final class AndroidJarSignatureInspector {
  private static final long MAX_ARCHIVE_BYTES = 1024L * 1024L * 1024L;
  private static final long MAX_ENTRY_BYTES = 512L * 1024L * 1024L;
  private static final long MAX_EXPANDED_BYTES = 4L * 1024L * 1024L * 1024L;
  private static final int MAX_ENTRY_COUNT = 100_000;
  private static final int MAX_ENTRY_NAME_LENGTH = 4096;

  private AndroidJarSignatureInspector() {}

  public static void main(String[] arguments) {
    boolean evidenceOnly =
        arguments.length == 2 && arguments[0].equals("--signature-evidence");
    if (!evidenceOnly && arguments.length != 1) {
      fail(
          "usage: AndroidJarSignatureInspector.java "
              + "[--signature-evidence] <archive>");
    }
    Path archive = Path.of(arguments[arguments.length - 1]);
    if (!Files.isRegularFile(archive)) {
      fail("archive does not exist");
    }

    try {
      if (Files.size(archive) > MAX_ARCHIVE_BYTES) {
        throw new SecurityException("archive exceeds the compressed-size limit");
      }
      if (evidenceOnly) {
        inspectSignatureEvidence(archive);
      } else {
        inspect(archive);
      }
    } catch (Exception error) {
      fail("signature verification failed: " + error.getMessage());
    }
  }

  private static void inspect(Path archive)
      throws IOException, NoSuchAlgorithmException, CertificateEncodingException {
    Set<String> entryNames = new HashSet<>();
    Set<String> archiveSigners = new HashSet<>();
    String firstUnsignedEntry = null;
    boolean hasContent = false;
    boolean hasSignedContent = false;
    boolean hasSignatureEvidence = false;
    long expandedBytes = 0;
    int entryCount = 0;

    try (JarFile jar = new JarFile(archive.toFile(), true)) {
      Enumeration<JarEntry> entries = jar.entries();
      while (entries.hasMoreElements()) {
        JarEntry entry = entries.nextElement();
        entryCount++;
        if (entryCount > MAX_ENTRY_COUNT) {
          throw new SecurityException("archive exceeds the entry-count limit");
        }
        validateEntry(entry);
        if (!entryNames.add(entry.getName())) {
          throw new SecurityException("duplicate archive entry " + entry.getName());
        }
        if (entry.isDirectory()) {
          continue;
        }

        expandedBytes =
            checkedTotal(
                expandedBytes,
                consume(jar, entry),
                MAX_EXPANDED_BYTES,
                "archive exceeds the permitted expansion limit");
        if (isManifest(entry.getName())) {
          continue;
        }
        if (isSignatureMetadata(entry.getName())) {
          hasSignatureEvidence = true;
          continue;
        }

        hasContent = true;
        CodeSigner[] signers = entry.getCodeSigners();
        if (signers == null || signers.length == 0) {
          if (firstUnsignedEntry == null) {
            firstUnsignedEntry = entry.getName();
          }
          continue;
        }
        if (signers.length != 1) {
          throw new SecurityException(
              "content entry has " + signers.length + " signers: " + entry.getName());
        }
        hasSignedContent = true;
        String fingerprint = signerFingerprint(signers[0]);
        archiveSigners.add(fingerprint);
        if (archiveSigners.size() != 1) {
          throw new SecurityException("content entries use different signing certificates");
        }
      }
    }

    if (!hasContent) {
      throw new SecurityException("archive contains no inspectable content");
    }
    if (hasSignedContent && firstUnsignedEntry != null) {
      throw new SecurityException(
          "signed archive contains unsigned content entry " + firstUnsignedEntry);
    }
    if (firstUnsignedEntry != null) {
      if (hasSignatureEvidence) {
        throw new SecurityException("unsigned archive retains signature metadata");
      }
      System.out.println("UNSIGNED");
      return;
    }
    if (!hasSignatureEvidence || archiveSigners.size() != 1) {
      throw new SecurityException("signed content has no complete signature metadata");
    }
    System.out.println("SIGNED_SHA256=" + archiveSigners.iterator().next());
  }

  private static void inspectSignatureEvidence(Path archive) throws IOException {
    Set<String> entryNames = new HashSet<>();
    boolean hasSignatureEvidence = false;
    long expandedBytes = 0;
    int entryCount = 0;

    try (JarFile jar = new JarFile(archive.toFile(), false)) {
      Enumeration<JarEntry> entries = jar.entries();
      while (entries.hasMoreElements()) {
        JarEntry entry = entries.nextElement();
        entryCount++;
        if (entryCount > MAX_ENTRY_COUNT) {
          throw new SecurityException("archive exceeds the entry-count limit");
        }
        validateEntry(entry);
        if (!entryNames.add(entry.getName())) {
          throw new SecurityException("duplicate archive entry " + entry.getName());
        }
        if (!entry.isDirectory()) {
          expandedBytes =
              checkedTotal(
                  expandedBytes,
                  consume(jar, entry),
                  MAX_EXPANDED_BYTES,
                  "archive exceeds the permitted expansion limit");
        }
        if (isSignatureMetadata(entry.getName())) {
          hasSignatureEvidence = true;
        }
      }
    }

    System.out.println(hasSignatureEvidence ? "SIGNATURE_EVIDENCE" : "NO_SIGNATURE_EVIDENCE");
  }

  private static void validateEntry(JarEntry entry) {
    String name = entry.getName();
    if (name.isEmpty() || name.length() > MAX_ENTRY_NAME_LENGTH) {
      throw new SecurityException("archive entry has an invalid name length");
    }
    if (name.startsWith("/") || name.indexOf('\\') >= 0) {
      throw new SecurityException("archive entry uses an unsafe path: " + name);
    }
    for (int index = 0; index < name.length(); index++) {
      if (Character.isISOControl(name.charAt(index))) {
        throw new SecurityException("archive entry name contains a control character");
      }
    }
    String path = name.endsWith("/") ? name.substring(0, name.length() - 1) : name;
    if (path.isEmpty()) {
      throw new SecurityException("archive entry uses an empty path");
    }
    for (String segment : path.split("/", -1)) {
      if (segment.isEmpty() || segment.equals(".") || segment.equals("..")) {
        throw new SecurityException("archive entry uses an unsafe path: " + name);
      }
    }
    long size = entry.getSize();
    if (size < 0) {
      throw new SecurityException("archive entry has no declared size: " + name);
    }
    if (size > MAX_ENTRY_BYTES) {
      throw new SecurityException("archive entry exceeds the size limit: " + name);
    }
  }

  private static long consume(JarFile jar, JarEntry entry) throws IOException {
    byte[] buffer = new byte[8192];
    long consumed = 0;
    try (InputStream input = jar.getInputStream(entry)) {
      int count;
      while ((count = input.read(buffer)) != -1) {
        consumed =
            checkedTotal(
                consumed,
                count,
                MAX_ENTRY_BYTES,
                "archive entry exceeds the size limit: " + entry.getName());
        // Reading every byte is what causes JarFile to validate the entry.
      }
    }
    if (consumed != entry.getSize()) {
      throw new SecurityException(
          "archive entry size differs from metadata: " + entry.getName());
    }
    return consumed;
  }

  private static long checkedTotal(long current, long increment, long limit, String message) {
    if (increment < 0 || current > limit - increment) {
      throw new SecurityException(message);
    }
    return current + increment;
  }

  private static String signerFingerprint(CodeSigner signer)
      throws NoSuchAlgorithmException, CertificateEncodingException {
    if (signer.getSignerCertPath().getCertificates().isEmpty()) {
      throw new CertificateEncodingException("signer certificate path is empty");
    }
    Certificate leaf = signer.getSignerCertPath().getCertificates().get(0);
    byte[] digest = MessageDigest.getInstance("SHA-256").digest(leaf.getEncoded());
    StringBuilder encoded = new StringBuilder(digest.length * 2);
    for (byte value : digest) {
      encoded.append(String.format(Locale.ROOT, "%02x", value & 0xff));
    }
    return encoded.toString();
  }

  private static boolean isManifest(String name) {
    return name.toUpperCase(Locale.ROOT).equals("META-INF/MANIFEST.MF");
  }

  private static boolean isSignatureMetadata(String name) {
    String upper = name.toUpperCase(Locale.ROOT);
    if (!upper.startsWith("META-INF/")) {
      return false;
    }
    String leaf = upper.substring("META-INF/".length());
    if (leaf.contains("/")) {
      return false;
    }
    return leaf.startsWith("SIG-")
        || leaf.endsWith(".SF")
        || leaf.endsWith(".RSA")
        || leaf.endsWith(".DSA")
        || leaf.endsWith(".EC");
  }

  private static void fail(String message) {
    System.err.println("Android JAR signature check failed: " + message);
    System.exit(1);
  }
}
