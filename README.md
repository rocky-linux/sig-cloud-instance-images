# sig-cloud-instance-images

Source for the `rockylinux` Docker Official Image, plus the second-layer `init`
and `micro` images.

Container images themselves are built by KIWI in Koji from
[rocky-kiwi-descriptions](https://git.resf.org/sig_core/rocky-kiwi-descriptions)
and published to `https://dl.rockylinux.org/pub/rocky/<major>/images/<arch>/`.
This repository holds the published artifacts in per-image branches and the
tooling to get them there.

## Official image

docker-library builds the official image with the `oci-import` builder, which
publishes an OCI layout from a git branch byte for byte. Each branch holds a
single commit containing exactly `oci-layout`, `index.json` and `blobs/`, and is
named `Rocky-<X.Y.YYYYMMDD>-<Variant>-<rocky_arch>`.

Branches are never modified or deleted: commits referenced by current or
historical `library/rockylinux` entries have to stay reachable.

> **Note**
> This repository has over 170 branches, most carrying a ~50MB layer. Always
> fetch one branch at a time (`git fetch origin <branch>`). A bare `git fetch`
> pulls gigabytes.

### Updating

1. Download the published artifacts for every architecture and verify them
   against their `.CHECKSUM` files. Architectures vary by release: 9 ships
   x86_64, aarch64, ppc64le and s390x; 10 adds riscv64.

2. Create a branch per artifact:

   ```
   ./tools/branch-from-oci.sh ~/artifacts/Rocky-*-Container-{Base,Minimal}-*.oci.tar.xz
   ```

   This runs `check-container-image.sh` first and refuses to branch an artifact
   that fails, refuses to touch a branch that already exists on origin, and
   verifies afterwards that the branch is a single parentless commit with no
   blob at or over 95MB.

3. Push the branches, then record them in `tools/manifest.json` and regenerate
   the library file:

   ```
   ./tools/generate-library.sh > library/rockylinux
   ```

4. Open a pull request against
   [docker-library/official-images](https://github.com/docker-library/official-images)
   with that file. Validate it first with
   `bashbrew --library <dir> cat rockylinux` and `bashbrew ... fetch rockylinux`.

Only Base and Minimal are published. Toolbox and UBI are built and branched but
are not in the library file.

### manifest.json

Records branch, commit and architecture per entry. `Builder` is per entry, so
8.10 stays on the classic builder while 9 and 10 use `oci-import`.

`defaultCommit` must be a real commit on `main`: bashbrew rejects the file
without a generic `GitFetch`/`GitCommit` even when every architecture is
overridden.

Tags follow `X.Y.YYYYMMDD`, `X.Y`, `X`, with `-minimal` variants. `latest`
points at the newest major.

### check-container-image.sh

Validates a `.oci.tar.xz` or an extracted layout:

- exactly `oci-layout`, `index.json`, `blobs/sha256/`
- one manifest, one `tar+gzip` layer, every blob's digest matching its filename,
  no unreferenced blobs
- every blob under 95MB (GitHub hard-blocks at 100MiB and Git LFS is not an
  option, since bashbrew fetches plain git objects)
- `os`, `architecture` and `variant` matching the expected arch. Only the config
  blob counts here; a registry manifest list can disagree with it
- `config.Cmd` is `["/bin/bash"]`
- no `.profile`, `.kconfig`, `image/`, `lost+found/`, `etc/default/grub`,
  `etc/wsl*.conf`, `var/log/dnf*` or `var/log/hawkey.log`
- `dev/` present and empty, `etc/machine-id` absent or zero bytes,
  `usr/share/locale` under 50 files

It writes a sorted `filelist.txt`, and exits non-zero on any failure.

## Second-layer images

`Containerfile-init` and `Containerfile-micro` build on the published UBI image
and are pushed to the `rockylinux` Docker Hub organization, not the official
image. `.github/workflows/build-2nd-layer.yml` builds them on push to `main` and
weekly; `ci.yml` builds them for pull requests.

## Support

The official image README lives in
[docker-library/docs](https://github.com/docker-library/docs) under
`rockylinux/`. Edit `content.md`, not the generated `README.md`.

For questions about the official images program, `#docker-library` on
Libera.chat is the best place to ask.
