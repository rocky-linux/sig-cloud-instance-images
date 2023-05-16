#!/usr/bin/env bash

version=${1}
type=${2}
date=${3:-$(date +%Y%m%d)}
revision=${4:-0}

major=${1:0:1}
minor=${1:2:1}

usage() {
	printf "%s: RELEASE TYPE [DATE]\n\n" $0
	log "$1"
}

# shellcheck disable=SC2046,1091,1090
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

name="Rocky-${version}.${date}-${type}"

arches=(x86_64 aarch64)
set -x
if [[ $major -ge 9 ]]; then
	arches=(${arches[@]} s390x ppc64le)
fi

case $type in
UBI | Minimal)
	suffix="-${type,,}"
	;;
*)
	suffix=''
	;;
esac

declare -A shasums

for a in "${arches[@]}"; do
	pt="${name}-${a}"
	if has-branch $pt; then
		shasums[$a]="$(git rev-parse $pt)"
	fi
done

cat <<EOF
Tags: ${version}.${date}${suffix}, ${version}${suffix}, ${major}${suffix}
GitFetch: refs/heads/${name}-x86_64
GitCommit: ${shasums[x86_64]}
arm64v8-GitFetch: refs/heads/${name}-aarch64
arm64v8-GitCommit: ${shasums[aarch64]}
s390x-GitFetch: refs/heads/${name}-s390x
s390x-GitCommit: ${shasums[s390x]}
ppc64le-GitFetch: refs/heads/${name}-ppc64le
ppc64le-GitCommit: ${shasums[ppc64le]}
Architectures: amd64, arm64v8, ppc64le, s390x
EOF
