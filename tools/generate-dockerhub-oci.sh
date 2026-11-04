#!/usr/bin/env bash
#
# Emit a library/rockylinux stanza set for the oci-import builder.
#
#   ./generate-dockerhub-oci.sh 10.2:20261030 9.8:20261030 > library/rockylinux
#
# Reads branch SHAs out of the local repo, so run branch-from-oci.sh first.
# Entries are emitted in the order given; docker-library convention is newest
# major first.

set -euo pipefail

SCRNAME="$(basename "$0")"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Rocky arch -> bashbrew arch. Order here sets the order in Architectures:.
ARCH_MAP=(x86_64:amd64 aarch64:arm64v8 ppc64le:ppc64le s390x:s390x)
VARIANTS=(Base Minimal)

REMOTE=0
LATEST=""

usage() {
  cat <<EOF
usage: $SCRNAME [OPTIONS] VERSION:DATE...

  VERSION:DATE   e.g. 10.2:20261030

Options:
  -r, --remote       resolve SHAs from origin rather than local branches
  -l, --latest VER   also tag VER as 'latest'
  -h, --help
EOF
}

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

OPTS=$(getopt -a -n "$SCRNAME" -o r,l:,h -l remote,latest:,help -- "$@") || { usage; exit 2; }
eval set -- "$OPTS"
while :; do
  case "$1" in
    -r | --remote) REMOTE=1   ; shift   ;;
    -l | --latest) LATEST="$2"; shift 2 ;;
    -h | --help)   usage; exit 0 ;;
    --) shift; break ;;
  esac
done
[[ $# -gt 0 ]] || { usage; exit 2; }

resolve() {
  local branch="$1"
  if [[ "$REMOTE" -eq 1 ]]; then
    git -C "$REPO" ls-remote --heads origin "$branch" | cut -f1
  else
    git -C "$REPO" rev-parse --verify --quiet "refs/heads/$branch" || true
  fi
}

# The repo default, not whatever happens to be checked out.
default_branch="$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
default_branch="${default_branch#origin/}"
default_branch="${default_branch:-main}"
generic_commit="$(git -C "$REPO" rev-parse "origin/${default_branch}")"

cat <<EOF
Maintainers: Rocky Enterprise Software Foundation <infrastructure@rockylinux.org> (@rocky-linux),
             Brian Clemens <brian@resf.org> (@brianclemens)
GitRepo: https://github.com/rocky-linux/sig-cloud-instance-images.git
Builder: oci-import
File: index.json
# bashbrew needs non-architecture-specific values for these; the per-arch
# entries below are what actually get built
GitFetch: refs/heads/${default_branch}
GitCommit: ${generic_commit}
EOF

for spec in "$@"; do
  version="${spec%%:*}"
  datestamp="${spec##*:}"
  major="${version%%.*}"
  [[ "$version" != "$spec" && -n "$datestamp" ]] || die "bad spec: $spec"

  for variant in "${VARIANTS[@]}"; do
    suffix=""
    [[ "$variant" == "Base" ]] || suffix="-${variant,,}"

    declare -a shas=() arches=()
    for pair in "${ARCH_MAP[@]}"; do
      rocky="${pair%%:*}"; bb="${pair##*:}"
      branch="Rocky-${version}.${datestamp}-${variant}-${rocky}"
      sha="$(resolve "$branch")"
      [[ -n "$sha" ]] || { printf 'warning: no branch %s, skipping arch\n' "$branch" >&2; continue; }
      arches+=("$bb")
      shas+=("${bb}|${branch}|${sha}")
    done
    [[ ${#arches[@]} -gt 0 ]] || die "no branches found for ${version} ${variant}"

    tags="${version}.${datestamp}${suffix}, ${version}${suffix}, ${major}${suffix}"
    [[ "$LATEST" == "$version" && "$variant" == "Base" ]] && tags="${tags}, latest"

    printf '\nTags: %s\n' "$tags"
    printf 'Architectures: %s\n' "$(IFS=,; echo "${arches[*]}" | sed 's/,/, /g')"
    for entry in "${shas[@]}"; do
      IFS='|' read -r bb branch sha <<< "$entry"
      printf '%s-GitFetch: refs/heads/%s\n' "$bb" "$branch"
      printf '%s-GitCommit: %s\n' "$bb" "$sha"
    done
  done
done
