import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Validates and extracts an Android artifact's native-library matrix. */
public final class AndroidNativeLibraryExtractor {
  private static final long MAX_ARCHIVE_BYTES = 1024L * 1024L * 1024L;
  private static final long MAX_ENTRY_BYTES = 512L * 1024L * 1024L;
  private static final long MAX_EXPANDED_BYTES = 4L * 1024L * 1024L * 1024L;
  private static final long MAX_NATIVE_BYTES = 2L * 1024L * 1024L * 1024L;
  private static final int MAX_ENTRY_COUNT = 100_000;
  private static final int MAX_ENTRY_NAME_LENGTH = 4096;
  private static final Set<String> SUPPORTED_ABIS =
      Set.of("arm64-v8a", "x86_64");
  private static final Set<String> REQUIRED_LIBRARIES =
      Set.of("libapp.so", "libflutter.so", "librgb_lightning_node.so", "librgblibuniffi.so");

  private AndroidNativeLibraryExtractor() {}

  public static void main(String[] arguments) {
    if (arguments.length != 4) {
      fail(
          "usage: AndroidNativeLibraryExtractor.java "
              + "<archive> <native-root> <output-directory> <expected-abis-csv>");
    }

    Path archive = Path.of(arguments[0]);
    String nativeRoot = arguments[1];
    Path outputDirectory = Path.of(arguments[2]);
    try {
      int extracted =
          inspectAndExtract(
              archive, nativeRoot, outputDirectory, parseExpectedAbis(arguments[3]));
      System.out.println("EXTRACTED_NATIVE_LIBRARIES=" + extracted);
    } catch (Exception error) {
      fail("archive validation failed: " + error.getMessage());
    }
  }

  private static int inspectAndExtract(
      Path archive, String nativeRoot, Path outputDirectory, Set<String> expectedAbis)
      throws IOException {
    validateInputs(archive, nativeRoot, outputDirectory);

    Set<String> entryNames = new HashSet<>();
    Map<String, Set<String>> librariesByAbi = new HashMap<>();
    List<NativeEntry> nativeEntries = new ArrayList<>();
    long expandedBytes = 0;
    int entryCount = 0;

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

        NativeEntry nativeEntry = parseNativeEntry(entry, nativeRoot, size);
        if (nativeEntry == null) {
          continue;
        }
        if (!expectedAbis.contains(nativeEntry.abi)) {
          throw new SecurityException("unexpected native ABI " + nativeEntry.abi);
        }
        nativeEntries.add(nativeEntry);
        librariesByAbi
            .computeIfAbsent(nativeEntry.abi, ignored -> new TreeSet<>())
            .add(nativeEntry.libraryName);
      }

      if (!librariesByAbi.keySet().equals(expectedAbis)) {
        throw new SecurityException(
            "native ABI set " + new TreeSet<>(librariesByAbi.keySet())
                + " does not match expected " + new TreeSet<>(expectedAbis));
      }
      for (String abi : expectedAbis) {
        Set<String> libraries = librariesByAbi.get(abi);
        if (!libraries.containsAll(REQUIRED_LIBRARIES)) {
          Set<String> missing = new TreeSet<>(REQUIRED_LIBRARIES);
          missing.removeAll(libraries);
          throw new SecurityException(abi + " is missing required libraries " + missing);
        }
      }

      nativeEntries.sort(Comparator.comparing(entry -> entry.archiveEntry.getName()));
      extract(zip, nativeEntries, outputDirectory);
      return nativeEntries.size();
    }
  }

  private static void validateInputs(Path archive, String nativeRoot, Path outputDirectory)
      throws IOException {
    if (!Files.isRegularFile(archive, LinkOption.NOFOLLOW_LINKS)) {
      throw new IllegalArgumentException("archive does not exist or is not a regular file");
    }
    if (Files.size(archive) > MAX_ARCHIVE_BYTES) {
      throw new SecurityException("archive exceeds the compressed-size limit");
    }
    if (!nativeRoot.equals("lib") && !nativeRoot.equals("base/lib")) {
      throw new IllegalArgumentException("native root must be lib or base/lib");
    }
    if (!Files.isDirectory(outputDirectory, LinkOption.NOFOLLOW_LINKS)
        || Files.isSymbolicLink(outputDirectory)) {
      throw new IllegalArgumentException("output must be an existing non-symlink directory");
    }
    try (DirectoryStream<Path> children = Files.newDirectoryStream(outputDirectory)) {
      if (children.iterator().hasNext()) {
        throw new IllegalArgumentException("output directory must be empty");
      }
    }
  }

  private static Set<String> parseExpectedAbis(String encoded) {
    if (encoded.isBlank()) {
      throw new IllegalArgumentException("expected ABI set must not be empty");
    }
    Set<String> expected = new LinkedHashSet<>();
    for (String abi : encoded.split(",", -1)) {
      if (!SUPPORTED_ABIS.contains(abi)) {
        throw new IllegalArgumentException("unsupported expected ABI " + abi);
      }
      if (!expected.add(abi)) {
        throw new IllegalArgumentException("duplicate expected ABI " + abi);
      }
    }
    return expected;
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

  private static NativeEntry parseNativeEntry(
      ZipEntry entry, String nativeRoot, long declaredSize) {
    String name = entry.getName();
    if (name.equals(nativeRoot) || name.equals(nativeRoot + "/")) {
      if (!entry.isDirectory()) {
        throw new SecurityException("native root is not a directory entry");
      }
      return null;
    }
    String prefix = nativeRoot + "/";
    if (!name.startsWith(prefix)) {
      return null;
    }

    String relative = name.substring(prefix.length());
    if (entry.isDirectory()) {
      String directory = relative.substring(0, relative.length() - 1);
      if (!SUPPORTED_ABIS.contains(directory)) {
        throw new SecurityException("unexpected directory beneath native root: " + name);
      }
      return null;
    }

    String[] parts = relative.split("/", -1);
    if (parts.length != 2 || !SUPPORTED_ABIS.contains(parts[0])) {
      throw new SecurityException("malformed native-library path " + name);
    }
    String libraryName = parts[1];
    if (!libraryName.matches("[A-Za-z0-9_+.-]+\\.so")) {
      throw new SecurityException("unsafe native-library name " + libraryName);
    }
    return new NativeEntry(entry, parts[0], libraryName, declaredSize);
  }

  private static void extract(
      ZipFile zip, List<NativeEntry> entries, Path outputDirectory) throws IOException {
    Path outputRoot = outputDirectory.toRealPath(LinkOption.NOFOLLOW_LINKS);
    List<Path> createdPaths = new ArrayList<>();
    long nativeBytes = 0;
    try {
      for (NativeEntry entry : entries) {
        Path abiDirectory = outputRoot.resolve(entry.abi);
        if (!Files.exists(abiDirectory, LinkOption.NOFOLLOW_LINKS)) {
          Files.createDirectory(abiDirectory);
          createdPaths.add(abiDirectory);
        }
        if (!Files.isDirectory(abiDirectory, LinkOption.NOFOLLOW_LINKS)
            || Files.isSymbolicLink(abiDirectory)
            || !abiDirectory.toRealPath(LinkOption.NOFOLLOW_LINKS).getParent().equals(outputRoot)) {
          throw new SecurityException("unsafe extraction directory for ABI " + entry.abi);
        }

        Path target = abiDirectory.resolve(entry.libraryName).normalize();
        if (!target.getParent().equals(abiDirectory)) {
          throw new SecurityException("native-library output escapes its ABI directory");
        }
        createdPaths.add(target);
        long written = copyBounded(zip, entry.archiveEntry, target, nativeBytes);
        nativeBytes = checkedTotal(nativeBytes, written, MAX_NATIVE_BYTES);
        if (written != entry.declaredSize) {
          throw new SecurityException(
              "native-library size differs from archive metadata: "
                  + entry.archiveEntry.getName());
        }
      }
    } catch (IOException | RuntimeException error) {
      for (int index = createdPaths.size() - 1; index >= 0; index--) {
        try {
          Files.deleteIfExists(createdPaths.get(index));
        } catch (IOException cleanupError) {
          error.addSuppressed(cleanupError);
        }
      }
      throw error;
    }
  }

  private static long copyBounded(
      ZipFile zip, ZipEntry entry, Path target, long bytesAlreadyWritten) throws IOException {
    byte[] buffer = new byte[8192];
    long written = 0;
    try (InputStream input = zip.getInputStream(entry);
        OutputStream output =
            Files.newOutputStream(target, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
      int count;
      while ((count = input.read(buffer)) != -1) {
        written = checkedTotal(written, count, MAX_ENTRY_BYTES);
        checkedTotal(bytesAlreadyWritten, written, MAX_NATIVE_BYTES);
        output.write(buffer, 0, count);
      }
    }
    return written;
  }

  private static long checkedTotal(long current, long increment, long limit) {
    if (increment < 0 || current > limit - increment) {
      throw new SecurityException("archive exceeds the permitted expansion limit");
    }
    return current + increment;
  }

  private static void fail(String message) {
    System.err.println("Android native-library extraction failed: " + message);
    System.exit(1);
  }

  private static final class NativeEntry {
    private final ZipEntry archiveEntry;
    private final String abi;
    private final String libraryName;
    private final long declaredSize;

    private NativeEntry(
        ZipEntry archiveEntry, String abi, String libraryName, long declaredSize) {
      this.archiveEntry = archiveEntry;
      this.abi = abi;
      this.libraryName = libraryName;
      this.declaredSize = declaredSize;
    }
  }
}
