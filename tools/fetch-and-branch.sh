#!/usr/bin/env bash

version=${1}
type=${2}
arch=${3}
date=${4:-$(date +%Y%m%d)}
revision=${5:-0}
tagdate=${TAGDATE:-date}

major=${version%%.*}
rest=${version#*.}
minor=${rest%%.*}
TEMPLATE="library-template"

usage() {
  printf "%s: RELEASE TYPE ARCH [DATE]\n\n" $0
  log "$1"
}

KIWI=false

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
    riscv64)
      build_args="--os linux --arch riscv64" ;;
    *) echo "invalid arch"; exit;;
  esac

  if [[ -f kiwi.result.json || $KIWI ]]; then
    log "found kiwi image"
    oci="$(find "$PWD" -maxdepth 1 -type f -name '*.oci*')"
    if [[ ! -f "${oci}" ]]; then
      log "could not find OCI image. Aborting"
      exit 2
    fi
    container_shasum="$(tar -tvf $oci | sort -k3 -nr | head -n2 | tail -1 | awk '{print $NF}' | xargs basename)"
    log-cmd podman load -i $oci
  else
    # don't bother tagging the  intermediary container as we will just capture its shasum
    container_shasum="$(podman build -q $build_args .)"
  fi

  image_source="containers-storage:${container_shasum}"
  pRes=$?
  if [[ $pRes -gt 0 ]]; then
    echo "failed to build container. exiting"
    exit $pRes
  fi

  # Manifest tags need one per type (base/minimal/etc), and contain two architectures (for 8, 9 will ultimately have 4+)
  if ! podman manifest exists "$manifest_tag"; then
    log "Creating manifest $manifest_tag"
    log-cmd podman manifest create "$manifest_tag"
    pRes=$?
    if [[ $pRes -gt 0 ]]; then
      echo "Failed to create manifest"
      exit $pRes 
    fi
  else
    echo "manifest exists. adding will overwrite existing platform tuple in manifest, if exists."
  fi

  log "Adding $image_source to $manifest_tag with $build_args"
  log-cmd podman manifest add $manifest_tag $image_source $build_args
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
  local tags=("$version" "${version}.${tagdate}")
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

  case $version in
    8|9)
      log-cmd aws --region us-east-2 --profile peridot-prod s3 sync "s3://resf-empanadas/$builddir" $PWD
      ;;
    *)
      KIWI=true
      until [[ -f "$(latest-build-name)" ]]; do
        log-cmd rsync -av "$builddir" .
        sleep 1;
      done
      ;;
  esac

  generate-packagelist
  generate-filelist

}

rm ./*.oci*
check-and-download
build-container-manifests


# for kiwi images we just want to rename the tar to layer.tar.xz
tarball="$(find "$PWD" -maxdepth 1 -type f -name '*.tar.xz')"
if [[ ! -f "${tarball}" ]]; then
  log "could not find tarball image. Aborting"
  exit 2
else 
  mv $tarball layer.tar.xz
  rm ./*.oci*
fi

git add .
git commit -S -m "Rocky Linux Container Image - $branch"

manifest-push-commands
