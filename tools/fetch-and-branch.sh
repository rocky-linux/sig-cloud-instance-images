#!/usr/bin/env bash

version=${1}
type=${2}
arch=${3}
date=${4:-$(date +%Y%m%d)}
revision=${5:-0}

major=${1:0:1}
minor=${1:2:1}
TEMPLATE="library-template"

usage() {
  printf "%s: RELEASE TYPE ARCH [DATE]\n\n" $0
  log "$1"
}

# shellcheck disable=SC2046,1091,1090
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

build-container-manifests() {

  case "$arch" in
    x86_64)
      build_args="--os linux --arch amd64 " ;;
    aarch64)
      build_args="--os linux --arch arm64 --variant v8" ;;
    s390x)
      build_args="--os linux --arch s390x" ;;
    ppc64le)
      build_args="--os linux --arch ppc64le" ;;
    *) echo "invalid arch"; exit;;
  esac

  # don't bother tagging the  intermediary container as we will just capture its shasum
  container_shasum=$(podman build -q $build_args .)
  pRes=$?
  if [[ $pRes -gt 0 ]]; then
    echo "failed to build container. exiting"
    exit $pRes
  fi

  # Manifest tags need one per type (base/minimal/etc), and contain two architectures (for 8, 9 will ultimately have 4+)
  if ! podman manifest exists "$manifest_tag"; then
    podman manifest create "$manifest_tag"
    pRes=$?
    if [[ $pRes -gt 0 ]]; then
      echo "Failed to create manifest"
      exit $pRes 
    fi
  else
    echo "manifest exists. adding will overwrite existing platform tuple in manifest, if exists."
  fi

  podman manifest add $manifest_tag containers-storage:$container_shasum $build_args
  pRes=$?
  if [[ $pRes -gt 0 ]]; then
    echo "Failed to add container image to manifest"
    exit $pRes 
  fi

  echo
  echo "when all images have been added to the manifest, the manifests must be pushed to their locations."
  echo "***Only push the bar MAJOR version tag (8,9) when the OS has been fully released.***"
  echo

}

manifest-push-commands (){
  local destinations=("docker.io/rockylinux/rockylinux" "quay.io/rockylinux/rockylinux")
  local tags=("$version" "${version}.${date}")
  local final_tags=()
  for d in "${destinations[@]}"; do
    for t in "${tags[@]}"; do
      final_tags=(${final_tags[@]} "$d:$t")
    done
  done

  for t in "${final_tags[@]}"; do
    printf "podman manifest push %s %s\n" $manifest_tag $t
  done
}


check-and-download (){
  if has-branch $pattern; then
    usage "Branch ${pattern} already exists. Exiting."
    exit 1
  fi

  log "Creating branch ${pattern}"

  log-cmd git checkout -b "${pattern}" $TEMPLATE

  branch=$(current-branch)
  if [[ "${branch}" != "${pattern}" ]]; then
    log "Not on the proper branch after creation. Exiting for safety."
    exit 127
  fi

  # Clear the history of the branch (Required for Docker Hub Official Images to only have one commit on the branch)
  log-cmd git update-ref -d HEAD

  builddir=$(latest-build)
  if [[ -z "$builddir" ]]; then
    log "Builddir not found. Exiting"
    exit 3
  fi

  log-cmd aws --region us-east-2 --profile resf-peridot-prod s3 sync "s3://resf-empanadas/$builddir" $PWD

  generate-packagelist
  generate-filelist
}

check-and-download
build-container-manifests

git add .
git commit -S -m "Rocky Linux Container Image - $branch"

manifest-push-commands
