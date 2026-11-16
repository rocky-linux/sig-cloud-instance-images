#!/usr/bin/env bash
#
# Validate a Rocky container artifact against the requirements of the
# docker-library "oci-import" builder.
#
# Accepts either a published .oci.tar.xz artifact or an already extracted OCI
# layout directory. Exits non-zero if any check fails, so it can gate a build.
#
# See: https://github.com/docker-library/official-images#oci-import

set -uo pipefail

SCRNAME="$(basename "$0")"

# docker-library refuses blobs GitHub would reject. GitHub hard-blocks at 100MiB;
# stay well under so a point release does not silently cross the line.
MAX_BLOB_BYTES=$((95 * 1000 * 1000))

# 8.10 (old kickstart pipeline) shipped ~8 locale files. Anything near the
# thousands means locale filtering regressed again.
MAX_LOCALE_FILES=50

ARCH=""
FILELIST=""
KEEP_WORKDIR=0

usage() {
  cat <<EOF
usage: $SCRNAME [OPTIONS] PATH

  PATH   a .oci.tar.xz artifact, or a directory holding an OCI layout

Options:
  -a, --arch ARCH       expected architecture. Accepts bashbrew names
                        (amd64, arm64v8, ppc64le, s390x, riscv64) or Rocky
                        names (x86_64, aarch64, ...). Inferred from PATH when
                        omitted.
  -m, --max-bytes N     maximum size of any single blob (default: $MAX_BLOB_BYTES)
  -l, --max-locale N    maximum files under usr/share/locale (default: $MAX_LOCALE_FILES)
  -f, --filelist PATH   write the sorted layer file list here (default: alongside
                        PATH as filelist.txt)
  -k, --keep            keep the temporary working directory
  -h, --help

EOF
}

log()  { printf '[%s] :: %s\n' "$(date -Isec)" "$1"; }
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
head2() { printf '\n== %s\n' "$1"; }

FAILURES=0
WARNINGS=0

OPTS=$(getopt -a -n "$SCRNAME" -o a:,m:,l:,f:,k,h \
  -l arch:,max-bytes:,max-locale:,filelist:,keep,help -- "$@") || { usage; exit 2; }
eval set -- "$OPTS"
while :; do
  case "$1" in
    -a | --arch)       ARCH="$2"             ; shift 2 ;;
    -m | --max-bytes)  MAX_BLOB_BYTES="$2"   ; shift 2 ;;
    -l | --max-locale) MAX_LOCALE_FILES="$2" ; shift 2 ;;
    -f | --filelist)   FILELIST="$2"         ; shift 2 ;;
    -k | --keep)       KEEP_WORKDIR=1        ; shift   ;;
    -h | --help)       usage; exit 0 ;;
    --) shift; break ;;
  esac
done

TARGET="${1:-}"
if [[ -z "$TARGET" || ! -e "$TARGET" ]]; then
  usage
  log "No such path: '${TARGET}'"
  exit 2
fi

for dep in jq tar sha256sum gzip; do
  command -v "$dep" >/dev/null 2>&1 || { log "Missing required tool: $dep"; exit 2; }
done

# --- resolve the expected architecture -------------------------------------
# Only the OCI config blob matters to oci-import; a registry manifest list can
# disagree with it, so never infer the answer from one to check the other.
if [[ -z "$ARCH" ]]; then
  case "$TARGET" in
    *x86_64*)  ARCH=amd64   ;;
    *aarch64*) ARCH=arm64v8 ;;
    *ppc64le*) ARCH=ppc64le ;;
    *s390x*)   ARCH=s390x   ;;
    *riscv64*) ARCH=riscv64 ;;
    *) log "Cannot infer architecture from '${TARGET}'; pass --arch"; exit 2 ;;
  esac
fi

case "$ARCH" in
  amd64   | x86_64)  BASHBREW_ARCH=amd64   ; WANT_ARCH=amd64   ; WANT_VARIANT=''   ;;
  arm64v8 | aarch64) BASHBREW_ARCH=arm64v8 ; WANT_ARCH=arm64   ; WANT_VARIANT='v8' ;;
  ppc64le)           BASHBREW_ARCH=ppc64le ; WANT_ARCH=ppc64le ; WANT_VARIANT=''   ;;
  s390x)             BASHBREW_ARCH=s390x   ; WANT_ARCH=s390x   ; WANT_VARIANT=''   ;;
  riscv64)           BASHBREW_ARCH=riscv64 ; WANT_ARCH=riscv64 ; WANT_VARIANT=''   ;;
  *) log "Unsupported architecture: ${ARCH}"; exit 2 ;;
esac

# --- unpack ----------------------------------------------------------------
WORKDIR="$(mktemp -d -t rocky-oci-check.XXXXXXXX)"
cleanup() { [[ "$KEEP_WORKDIR" -eq 1 ]] || rm -rf "$WORKDIR"; }
trap cleanup EXIT

if [[ -d "$TARGET" ]]; then
  LAYOUT="$TARGET"
  # Deliberately not inside the layout: an oci-import branch tree must contain
  # exactly oci-layout, index.json and blobs/, and nothing else.
  [[ -n "$FILELIST" ]] || FILELIST="$PWD/$(basename "${TARGET%/}").filelist.txt"
else
  log "Extracting $(basename "$TARGET")"
  tar -xf "$TARGET" -C "$WORKDIR" || { log "Extraction failed"; exit 2; }
  LAYOUT="$WORKDIR"
  [[ -n "$FILELIST" ]] || FILELIST="$(dirname "$TARGET")/filelist.txt"
fi

printf '%s\n' "Checking $(basename "$TARGET") as ${BASHBREW_ARCH}"

# --- structure -------------------------------------------------------------
head2 "Layout structure"

# Ignore .git so a checked-out branch can be validated in place (Phase 5).
entries="$(cd "$LAYOUT" && ls -A | grep -vx '.git' | sort | tr '\n' ' ')"
if [[ "$entries" == "blobs index.json oci-layout " ]]; then
  pass "top level is exactly: blobs index.json oci-layout"
else
  fail "unexpected top-level contents: ${entries}"
fi

blobsub="$(cd "$LAYOUT/blobs" 2>/dev/null && ls -A | sort | tr '\n' ' ')"
if [[ "$blobsub" == "sha256 " ]]; then
  pass "blobs/ contains only sha256/"
else
  fail "blobs/ contains: ${blobsub:-<missing>}"
fi

# Rocky's oci-layout has no trailing newline, tianon's sample does. Both valid.
if [[ -f "$LAYOUT/oci-layout" ]] \
  && [[ "$(jq -r '.imageLayoutVersion' "$LAYOUT/oci-layout" 2>/dev/null)" == "1.0.0" ]]; then
  pass "oci-layout declares imageLayoutVersion 1.0.0"
else
  fail "oci-layout missing or not imageLayoutVersion 1.0.0"
fi

manifest_count="$(jq -r '.manifests | length' "$LAYOUT/index.json" 2>/dev/null || echo 0)"
if [[ "$manifest_count" == "1" ]]; then
  pass "index.json has exactly one manifest"
else
  fail "index.json has ${manifest_count} manifests, expected 1"
fi

ref_name="$(jq -r '.manifests[0].annotations["org.opencontainers.image.ref.name"] // empty' \
  "$LAYOUT/index.json" 2>/dev/null)"
[[ -n "$ref_name" ]] && log "note: index.json carries ref.name='${ref_name}' (absent from tianon's sample; harmless)"

manifest_digest="$(jq -r '.manifests[0].digest' "$LAYOUT/index.json" 2>/dev/null)"
MANIFEST="$LAYOUT/blobs/sha256/${manifest_digest#sha256:}"
if [[ ! -f "$MANIFEST" ]]; then
  fail "manifest blob ${manifest_digest} is missing; cannot continue"
  exit 1
fi

layer_count="$(jq -r '.layers | length' "$MANIFEST")"
if [[ "$layer_count" == "1" ]]; then
  pass "manifest has exactly one layer"
else
  fail "manifest has ${layer_count} layers, expected 1"
fi

layer_media="$(jq -r '.layers[0].mediaType' "$MANIFEST")"
if [[ "$layer_media" == "application/vnd.oci.image.layer.v1.tar+gzip" ]]; then
  pass "layer mediaType is tar+gzip"
else
  fail "layer mediaType is '${layer_media}'"
fi

# --- blob integrity --------------------------------------------------------
head2 "Blob integrity and size"

referenced="$(mktemp -p "$WORKDIR")"
{
  printf '%s\n' "${manifest_digest#sha256:}"
  jq -r '.config.digest, .layers[].digest' "$MANIFEST" | sed 's/^sha256://'
} | sort -u > "$referenced"

bad_digest=0
oversize=0
while IFS= read -r blob; do
  name="$(basename "$blob")"
  actual="$(sha256sum "$blob" | cut -d' ' -f1)"
  [[ "$actual" == "$name" ]] || { fail "blob ${name:0:16}... content hash is ${actual:0:16}..."; bad_digest=1; }

  size="$(stat -c%s "$blob")"
  if [[ "$size" -ge "$MAX_BLOB_BYTES" ]]; then
    fail "blob ${name:0:16}... is ${size} bytes, over the ${MAX_BLOB_BYTES} limit"
    oversize=1
  elif [[ "$size" -gt $((MAX_BLOB_BYTES / 2)) ]]; then
    log "note: largest blob ${size} bytes, $((MAX_BLOB_BYTES - size)) bytes of headroom"
  fi
done < <(find "$LAYOUT/blobs/sha256" -type f | sort)

[[ "$bad_digest" -eq 0 ]] && pass "every blob's content matches its filename"
[[ "$oversize" -eq 0 ]] && pass "every blob is under ${MAX_BLOB_BYTES} bytes"

present="$(mktemp -p "$WORKDIR")"
find "$LAYOUT/blobs/sha256" -type f -printf '%f\n' | sort -u > "$present"
if orphans="$(comm -13 "$referenced" "$present")" && [[ -z "$orphans" ]]; then
  pass "no unreferenced blobs"
else
  fail "unreferenced blobs present: $(echo "$orphans" | tr '\n' ' ')"
fi

# --- config ----------------------------------------------------------------
head2 "Image config"

config_digest="$(jq -r '.config.digest' "$MANIFEST")"
CONFIG="$LAYOUT/blobs/sha256/${config_digest#sha256:}"
if [[ ! -f "$CONFIG" ]]; then
  fail "config blob is missing; cannot continue"
  exit 1
fi

got_os="$(jq -r '.os // empty' "$CONFIG")"
[[ "$got_os" == "linux" ]] && pass "os is linux" || fail "os is '${got_os}', expected linux"

got_arch="$(jq -r '.architecture // empty' "$CONFIG")"
got_variant="$(jq -r '.variant // empty' "$CONFIG")"
if [[ "$got_arch" == "$WANT_ARCH" && "$got_variant" == "$WANT_VARIANT" ]]; then
  pass "architecture/variant is ${got_arch}${got_variant:+/$got_variant}, correct for ${BASHBREW_ARCH}"
else
  fail "architecture/variant is '${got_arch}${got_variant:+/$got_variant}', expected '${WANT_ARCH}${WANT_VARIANT:+/$WANT_VARIANT}' for ${BASHBREW_ARCH}"
fi

got_cmd="$(jq -c '.config.Cmd // empty' "$CONFIG")"
if [[ "$got_cmd" == '["/bin/bash"]' ]]; then
  pass 'config.Cmd is ["/bin/bash"]'
else
  fail "config.Cmd is ${got_cmd:-<unset>}, expected [\"/bin/bash\"]"
fi

printf '\n  labels:\n'
jq -r '.config.Labels // {} | to_entries[] | "    \(.key)=\(.value)"' "$CONFIG"
printf '\n'

# kiwi defaults to buildah for the oci archive and buildah stamps its own
# version in. Only changeable via kiwi's runtime config (oci/archive_tool:
# umoci), which lives in the build environment rather than the image
# description, so this is a note rather than a gate.
if jq -e '.config.Labels | has("io.buildah.version")' "$CONFIG" >/dev/null 2>&1; then
  warn "label io.buildah.version leaks the build tool; set kiwi's oci/archive_tool to umoci to drop it"
else
  pass "no build-tool labels"
fi

authors="$(jq -r '.config.Labels["org.opencontainers.image.authors"] // empty' "$CONFIG")"
if [[ -z "$authors" ]]; then
  warn "org.opencontainers.image.authors is unset"
else
  for stale in "Neil Hanlon" "Lukas Magauer" "Louis Abel"; do
    [[ "$authors" == *"$stale"* ]] && warn "authors still lists former maintainer '${stale}'"
  done
  [[ "$authors" == *"<"*">"* ]] || warn "authors is not in 'Name <email>' form: '${authors}'"
fi

# --- layer contents --------------------------------------------------------
head2 "Layer contents"

LAYER="$LAYOUT/blobs/sha256/$(jq -r '.layers[0].digest' "$MANIFEST" | sed 's/^sha256://')"
LISTING="$WORKDIR/listing.txt"
if ! tar -tzf "$LAYER" > "$LISTING" 2>/dev/null; then
  fail "layer blob is not readable as a gzipped tar; cannot inspect contents"
  exit 1
fi
sort "$LISTING" -o "$LISTING"
log "layer holds $(wc -l < "$LISTING") entries"

# Paths that must never ship. KIWI build residue, WSL-only config that leaked
# out of the shared overlay, and bootloader config that is meaningless here.
forbidden=(
  '^\.profile$'
  '^\.kconfig$'
  '^image/'
  '^lost\+found'
  '^etc/default/grub$'
  '^etc/wsl\.conf$'
  '^etc/wsl-distribution\.conf$'
  '^var/log/dnf'
  '^var/log/hawkey\.log$'
)
found_forbidden=0
for pattern in "${forbidden[@]}"; do
  if hits="$(grep -E "$pattern" "$LISTING")" && [[ -n "$hits" ]]; then
    while IFS= read -r h; do fail "forbidden path present: ${h}"; done <<< "$hits"
    found_forbidden=1
  fi
done
[[ "$found_forbidden" -eq 0 ]] && pass "no forbidden paths"

# /dev must exist but stay empty; the runtime mounts over it.
if grep -qE '^dev/$' "$LISTING"; then
  dev_entries="$(grep -cE '^dev/.+' "$LISTING")"
  if [[ "$dev_entries" -eq 0 ]]; then
    pass "dev/ exists and is empty"
  else
    fail "dev/ has ${dev_entries} entries, expected none"
  fi
else
  fail "dev/ is missing"
fi

# An empty machine-id is correct for a container: systemd and dbus regenerate it
# per-instance. A populated one would make every container share an identity.
if grep -qE '^etc/machine-id$' "$LISTING"; then
  mid_size="$(tar -tvzf "$LAYER" etc/machine-id 2>/dev/null | awk '{print $3}' | head -1)"
  if [[ "${mid_size:-0}" == "0" ]]; then
    pass "etc/machine-id is present and empty (correct for containers)"
  else
    fail "etc/machine-id is ${mid_size} bytes, expected 0"
  fi
else
  pass "etc/machine-id absent"
fi

locale_files="$(grep -cE '^usr/share/locale/.+[^/]$' "$LISTING")"
if [[ "$locale_files" -le "$MAX_LOCALE_FILES" ]]; then
  pass "usr/share/locale holds ${locale_files} files (limit ${MAX_LOCALE_FILES})"
else
  fail "usr/share/locale holds ${locale_files} files, over the ${MAX_LOCALE_FILES} limit — rpm locale filtering is not in effect"
fi

# --- filelist --------------------------------------------------------------
if cp "$LISTING" "$FILELIST" 2>/dev/null; then
  log "Wrote file list to ${FILELIST}"
else
  warn "could not write file list to ${FILELIST}"
fi

# --- summary ---------------------------------------------------------------
head2 "Summary"
if [[ "$FAILURES" -eq 0 ]]; then
  printf '  %s: \033[32mOK\033[0m (%d warnings)\n\n' "$(basename "$TARGET")" "$WARNINGS"
  exit 0
fi
printf '  %s: \033[31m%d failures\033[0m, %d warnings\n\n' "$(basename "$TARGET")" "$FAILURES" "$WARNINGS"
exit 1
