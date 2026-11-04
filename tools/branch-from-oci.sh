#!/usr/bin/env bash
#
# Create the single-commit branch the docker-library oci-import builder expects
# from a published .oci.tar.xz. The branch holds exactly the OCI layout kiwi
# emitted: oci-layout, index.json and blobs/, with no history and no extra files.
#
#   ./branch-from-oci.sh Rocky-9-Container-Base-9.8-20261030.0.x86_64.oci.tar.xz
#
# Branch name follows the convention already used in this repo:
#   Rocky-<X.Y.YYYYMMDD>-<Variant>-<rocky_arch>

set -euo pipefail

SCRNAME="$(basename "$0")"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$REPO/tools/check-container-image.sh"

FORCE=0
DATE_OVERRIDE=""

usage() {
  cat <<EOF
usage: $SCRNAME [OPTIONS] ARTIFACT...

Options:
  -d, --date DATE   commit date (default: artifact mtime)
  -f, --force       replace an existing local branch
  -h, --help
EOF
}

log()  { printf '[%s] :: %s\n' "$(date -Isec)" "$1"; }
die()  { printf 'error: %s\n' "$1" >&2; exit 1; }

# A failed run must not leave a worktree registered against the repo; the next
# run would find the branch checked out and refuse to touch it.
CURRENT_WT=""
cleanup() {
  [[ -n "$CURRENT_WT" ]] || return 0
  git -C "$REPO" worktree remove --force "$CURRENT_WT" >/dev/null 2>&1 || true
  rm -rf "$CURRENT_WT"
  git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  CURRENT_WT=""
}
trap cleanup EXIT

OPTS=$(getopt -a -n "$SCRNAME" -o d:,f,h -l date:,force,help -- "$@") || { usage; exit 2; }
eval set -- "$OPTS"
while :; do
  case "$1" in
    -d | --date)  DATE_OVERRIDE="$2" ; shift 2 ;;
    -f | --force) FORCE=1            ; shift   ;;
    -h | --help)  usage; exit 0 ;;
    --) shift; break ;;
  esac
done

[[ $# -gt 0 ]] || { usage; exit 2; }
[[ -x "$CHECKER" ]] || die "checker not found at $CHECKER"

for artifact in "$@"; do
  [[ -f "$artifact" ]] || die "no such file: $artifact"
  artifact="$(readlink -f "$artifact")"
  name="$(basename "$artifact")"

  # Rocky-9-Container-Base-9.8-20261030.0.x86_64.oci.tar.xz
  if [[ ! "$name" =~ ^Rocky-[0-9]+-Container-([A-Za-z]+)-([0-9]+\.[0-9]+)-([0-9]{8})\.[0-9]+\.([a-z0-9_]+)\.oci\.tar\.xz$ ]]; then
    die "unrecognised artifact name: $name"
  fi
  variant="${BASH_REMATCH[1]}"
  version="${BASH_REMATCH[2]}"
  datestamp="${BASH_REMATCH[3]}"
  arch="${BASH_REMATCH[4]}"

  branch="Rocky-${version}.${datestamp}-${variant}-${arch}"
  commit_date="${DATE_OVERRIDE:-$(date -Iseconds -r "$artifact")}"

  log "=== $name"
  log "    branch ${branch}"

  "$CHECKER" -a "$arch" -f /dev/null "$artifact" >/dev/null 2>&1 \
    || die "$name failed validation; refusing to branch it"
  log "    checker passed"

  if git -C "$REPO" show-ref --quiet "refs/heads/$branch"; then
    [[ "$FORCE" -eq 1 ]] || die "branch $branch already exists (use --force)"
    git -C "$REPO" branch -D "$branch" >/dev/null
  fi
  if [[ -n "$(git -C "$REPO" ls-remote --heads origin "$branch")" ]]; then
    die "branch $branch already exists on origin; refusing to touch it"
  fi

  wt="$(mktemp -d -t oci-branch.XXXXXXXX)"
  CURRENT_WT="$wt"

  git -C "$REPO" worktree add -q --detach "$wt"
  (
    cd "$wt"
    git checkout -q --orphan "$branch"
    git rm -rqf . >/dev/null 2>&1 || true
    git clean -fdxq

    tar -xf "$artifact" -C .

    # .git is the worktree pointer file, not content
    contents="$(ls -A | grep -vx '.git' | sort | tr '\n' ' ')"
    [[ "$contents" == "blobs index.json oci-layout " ]] \
      || die "unexpected archive contents: $contents"

    git add oci-layout index.json blobs
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
      git commit -qm "Rocky ${version} ${variant} ${arch} (${datestamp})"
  )
  cleanup

  count="$(git -C "$REPO" rev-list --count "$branch")"
  parent="$(git -C "$REPO" log --format=%P -1 "$branch")"
  [[ "$count" == "1" ]] || die "$branch has $count commits, expected 1"
  [[ -z "$parent" ]]    || die "$branch has a parent commit"

  big="$(git -C "$REPO" ls-tree -r -l "$branch" | awk '$4 >= 95000000 {print $5" "$4}')"
  [[ -z "$big" ]] || die "$branch contains a blob at or over 95MB: $big"

  log "    $(git -C "$REPO" rev-parse --short "$branch")  1 commit, no parent, all blobs under 95MB"
done
