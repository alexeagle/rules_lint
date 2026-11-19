"""Release binary integrity hashes.

This file contents are entirely replaced during release publishing.
The checked in content is only here to allow load() statements in the sources to resolve.
Published values are SHA-256 hex digests generated from go-binaries/*.sha256,
including both the SARIF parser and static Go package driver.
"""

RELEASED_BINARY_INTEGRITY = {
    "gopackagesdriver-darwin_amd64": "...",
    "sarif_parser-darwin_amd64": "...",
    # ...etc
}
