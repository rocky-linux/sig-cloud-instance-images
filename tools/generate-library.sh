#!/usr/bin/env bash
# Emit library/rockylinux for docker-library/official-images from
# tools/manifest.json.
#
#   ./generate-library.sh [manifest]
set -euo pipefail

MANIFEST="${1:-$(dirname "${BASH_SOURCE[0]}")/manifest.json}"
[[ -f "$MANIFEST" ]] || { echo "no such manifest: $MANIFEST" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

jq -r '
  def bashbrew:
    { "x86_64": "amd64", "aarch64": "arm64v8", "ppc64le": "ppc64le",
      "s390x": "s390x", "riscv64": "riscv64" }[.];

  "Maintainers: " + (.maintainers | join(",\n             ")),
  "GitRepo: " + .repo,
  # bashbrew rejects the file without these even when every arch is
  # overridden, so point them at a real commit on the default branch
  "GitFetch: refs/heads/" + .defaultBranch,
  "GitCommit: " + .defaultCommit,
  "",

  (.entries[] |
    "Tags: " + (.tags | join(", ")),
    "Architectures: " + ([.arches[].arch | bashbrew] | join(", ")),
    (if .builder then "Builder: " + .builder else empty end),
    (if .file then "File: " + .file else empty end),
    (.arches[] |
      (.arch | bashbrew) as $b |
      $b + "-GitFetch: refs/heads/" + .branch,
      $b + "-GitCommit: " + .commit
    ),
    ""
  )
' "$MANIFEST"
