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

log() {
  printf "[%s] :: %s\n" "$(date -Isec)" "$1"
}

log-cmd() {
  set -x
  command $@
  set +x
}

if [[ -z "$version" || ! "$version" =~ [0-9]+.[0-9]+ ]]; then
  usage "Invalid or empty version"
  exit 1
fi

case "$type" in
  Base|Minimal) ;;
  *) 
    usage "Invalid type"
    exit 1
    ;;
esac



pattern=$(printf "Rocky-%s.%s-%s-%s" "$version" "$date" "$type" "$arch")

has-branch(){
  local res=$(log-cmd git branch --list "$1")
  if [[ -z $res ]]; then
    return 1
  fi
  return 0
}

current-branch() {
  local res=$(log-cmd git branch --show-current)
  ret=0
  if [[ ! -z $res ]]; then
    ret=1
  fi
  echo $res
  return $ret
}

generate-packagelist() {
  log "Generating package list"
  if [[ -f build.meta ]]; then
    log-cmd xmllint --xpath "//packages/*/@name" <(printf "$(jq '.icicle' < build.meta)\n" | tr -d '\\' | tail -c +2 | head -c -2) | \
      awk -F\= '{print substr($2,2,length($2)-2)}' | \
      sort > packages.txt
    return $?
  fi
  log "No build.meta found. Skipping packagelist generation"
  return 1
}

generate-filelist() {
  log "Generating filelist"
  if [[ -f layer.tar.xz ]]; then
    log-cmd tar -tf layer.tar.xz > filelist.txt
    return $?
  fi
  log "No layer.tar.xz found. Skipping filelist generation"
  return 1
}

latest-build() {
 local path=$(printf "s3://resf-empanadas/buildimage-%s-%s/Rocky-%s-Container-%s-%s-%s.%s.%s" $version $arch $major $type $version $date $revision $arch)
 local res=$(log-cmd aws --region us-east-2 --profile resf-peridot-prod s3 ls --recursive "$path" | sort | tail -1 | awk '{print $4}' | sed 's,^\(.*\)/.*$,\1,g')
 echo "$res"
 return 0
}

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
