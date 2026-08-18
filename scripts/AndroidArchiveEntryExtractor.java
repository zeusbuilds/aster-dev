import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Validates an Android archive and extracts one exact bounded entry. */
public final class AndroidArchiveEntryExtractor {
  private static final long MAX_ARCHIVE_BYTES = 1024L * 1024L * 1024L;
  private static final long MAX_ENTRY_BYTES = 512L * 1024L * 1024L;
  private static final long MAX_EXPANDED_BYTES = 4L * 1024L * 1024L * 1024L;
  private static final long MAX_REQUESTED_ENTRY_BYTES = 16L * 1024L * 1024L;
  private static final int MAX_ENTRY_COUNT = 100_000;
  private static final int MAX_ENTRY_NAME_LENGTH = 4096;

  private AndroidArchiveEntryExtractor() {}

  public static void main(String[] arguments) {
    if (arguments.length != 4) {
      fail(
          "usage: AndroidArchiveEntryExtractor.java "
              + "<archive> <entry-name> <output-file> <maximum-entry-bytes>");
    }

    try {
      long extractedBytes =
          inspectAndExtract(
              Path.of(arguments[0]),
              arguments[1],
              Path.of(arguments[2]),
              parseMaximumEntryBytes(arguments[3]));
      System.out.println("EXTRACTED_ENTRY_BYTES=" + extractedBytes);
    } catch (Exception error) {
      fail("archive validation failed: " + error.getMessage());
    }
  }

  private static long inspectAndExtract(
      Path archive, String requestedName, Path output, long maximumEntryBytes)
      throws IOException {
    Path target = validateInputs(archive, requestedName, output);
    Set<String> entryNames = new HashSet<>();
    ZipEntry requestedEntry = null;
    long expandedBytes = 0;
    int entryCount = 0;
    boolean outputCreated = false;

    try (ZipFile zip = new ZipFile(archive.toFile())) {
      Enumeration<? extends ZipEntry> entries = zip.entries();
      while (entries.hasMoreElements()) {
        ZipEntry entry = entries.nextElement();
        entryCount++;
        if (entryCount > MAX_ENTRY_COUNT) {
          throw new SecurityException("archive exceeds the entry-count limit");
        }

        String name = entry.getName();
        validateEntryName(name);
        if (!entryNames.add(name)) {
          throw new SecurityException("duplicate archive entry " + name);
        }

        long size = entry.getSize();
        if (size < 0) {
          throw new SecurityException("archive entry has no declared size: " + name);
        }
        if (size > MAX_ENTRY_BYTES) {
          throw new SecurityException("archive entry exceeds the size limit: " + name);
        }
        expandedBytes = checkedTotal(expandedBytes, size, MAX_EXPANDED_BYTES);

        if (!name.equals(requestedName)) {
          continue;
        }
        if (entry.isDirectory()) {
          throw new SecurityException("requested archive entry is a directory");
        }
        if (size > maximumEntryBytes) {
          throw new SecurityException("requested archive entry exceeds its size limit");
        }
        requestedEntry = entry;
      }

      if (requestedEntry == null) {
        throw new SecurityException("requested archive entry is missing: " + requestedName);
      }
      long written = copyBounded(zip, requestedEntry, target, maximumEntryBytes);
      outputCreated = true;
      return written;
    } catch (IOException | RuntimeException error) {
      if (outputCreated) {
        deleteOwnedOutput(target, error);
      }
      throw error;
    }
  }

  private static Path validateInputs(Path archive, String requestedName, Path output)
      throws IOException {
    if (!Files.isRegularFile(archive, LinkOption.NOFOLLOW_LINKS)) {
      throw new IllegalArgumentException("archive does not exist or is not a regular file");
    }
    if (Files.size(archive) > MAX_ARCHIVE_BYTES) {
      throw new SecurityException("archive exceeds the compressed-size limit");
    }
    validateEntryName(requestedName);
    if (requestedName.endsWith("/")) {
      throw new IllegalArgumentException("requested archive entry must be a file");
    }

    Path normalizedOutput = output.toAbsolutePath().normalize();
    Path outputParent = normalizedOutput.getParent();
    Path outputName = normalizedOutput.getFileName();
    if (outputParent == null || outputName == null) {
      throw new IllegalArgumentException("output must name a file in an existing directory");
    }
    if (!Files.isDirectory(outputParent, LinkOption.NOFOLLOW_LINKS)
        || Files.isSymbolicLink(outputParent)) {
      throw new IllegalArgumentException("output parent must be an existing non-symlink directory");
    }
    Path realParent = outputParent.toRealPath(LinkOption.NOFOLLOW_LINKS);
    Path target = realParent.resolve(outputName).normalize();
    if (!target.getParent().equals(realParent)) {
      throw new SecurityException("output escapes its parent directory");
    }
    if (Files.exists(target, LinkOption.NOFOLLOW_LINKS) || Files.isSymbolicLink(target)) {
      throw new IllegalArgumentException("output file must not already exist");
    }
    return target;
  }

  private static long parseMaximumEntryBytes(String encoded) {
    final long maximum;
    try {
      maximum = Long.parseLong(encoded);
    } catch (NumberFormatException error) {
      throw new IllegalArgumentException("maximum entry bytes must be an integer", error);
    }
    if (maximum <= 0 || maximum > MAX_REQUESTED_ENTRY_BYTES) {
      throw new IllegalArgumentException(
          "maximum entry bytes must be between 1 and " + MAX_REQUESTED_ENTRY_BYTES);
    }
    return maximum;
  }

  private static void validateEntryName(String name) {
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
  }

  private static long copyBounded(
      ZipFile zip, ZipEntry entry, Path target, long maximumEntryBytes) throws IOException {
    byte[] buffer = new byte[8192];
    long written = 0;
    boolean outputCreated = false;
    try (InputStream input = zip.getInputStream(entry)) {
      OutputStream opened =
          Files.newOutputStream(
              target,
              StandardOpenOption.CREATE_NEW,
              StandardOpenOption.WRITE,
              LinkOption.NOFOLLOW_LINKS);
      outputCreated = true;
      try (OutputStream output = opened) {
        int count;
        while ((count = input.read(buffer)) != -1) {
          written = checkedTotal(written, count, maximumEntryBytes);
          output.write(buffer, 0, count);
        }
      }
      if (written != entry.getSize()) {
        throw new SecurityException("requested entry size differs from archive metadata");
      }
      return written;
    } catch (IOException | RuntimeException error) {
      if (outputCreated) {
        deleteOwnedOutput(target, error);
      }
      throw error;
    }
  }

  private static void deleteOwnedOutput(Path target, Exception error) {
    try {
      Files.deleteIfExists(target);
    } catch (IOException cleanupError) {
      error.addSuppressed(cleanupError);
    }
  }

  private static long checkedTotal(long current, long increment, long limit) {
    if (increment < 0 || current > limit - increment) {
      throw new SecurityException("archive exceeds the permitted expansion limit");
    }
    return current + increment;
  }

  private static void fail(String message) {
    System.err.println("Android archive extraction failed: " + message);
    System.exit(1);
  }
}
