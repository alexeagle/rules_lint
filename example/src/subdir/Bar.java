package src.subdir;

// Unused imports are suppressed in suppressions.xml, so this should not raise issue.
import java.util.Objects;
import java.io.BufferedInputStream;

public class Bar {
  // Max line length set to 20, so this should raise issue.
  protected void finalize(int a) {}
}
