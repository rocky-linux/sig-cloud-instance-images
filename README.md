# sig-cloud-instance-images


Please see the following branches for the container filesystems and Dockerfiles.

* [Rocky-8.5-aarch64](https://github.com/rocky-linux/sig-cloud-instance-images/tree/Rocky-8.5-aarch64)
* [Rocky-8.5-x86_64](https://github.com/rocky-linux/sig-cloud-instance-images/tree/Rocky-8.5-x86_64)
* [Rocky-8.4-aarch64](https://github.com/rocky-linux/sig-cloud-instance-images/tree/Rocky-8.4-aarch64)
* [Rocky-8.4-x86_64](https://github.com/rocky-linux/sig-cloud-instance-images/tree/Rocky-8.4-x86_64)
* [Rocky Linux 8.4 RC1](https://github.com/rocky-linux/sig-cloud-instance-images/tree/Rocky-8.4-rc1-Container)

## Deployment

Rootfs tarballs are built weekly on Sunday at 00:00 UTC. There is not currently automation to auto-create releases, though that is under investigation (see #6).

There are two repositories on Dockerhub.com: the so-called "official" image, and the rockylinux organization. The former is facilitated by Docker, Inc., using information in the github.com/docker-library/official-images repository.

Builds are performed on Rocky Enterprise Software Foundation github runners that are spun up and down on demand for builds, as imagefactory requires bare metal hardware. Work is underway to not have to rely on bare metal installations.

### Updating the official Docker Hub image

Updating the official image is relatively simple, and could probably be automated, but at present it's not a high priority. To update the image, download the latest tested and verified build artifacts for every architecture. Anyone that is a maintainer of this repository (i.e., can merge changes into main) should be considered a maintainer of the official image and therefore allowed to request updates.

Make sure you have a fork of the rocky-linux/sig-cloud-instance-images repository that is checked out on your machine, and 
#### Official Image Update Steps

1. Download build artifacts from the latest passing build for all available architectures. The next steps should be repeated for each architecture.
1. Change to the directory containing the clone of the sig-cloud-instance-images repository.
1. Create a new branch based off the library-template branch named using the template: "Rocky-$MAJOR.$MINOR.$ISO8601DATE-$ARCHITECTURE" e.g, `Rocky-8.5.20220314-x86_64` or `Rocky-8.5.20220314-aarch64`
    ```
    git checkout -b Rocky-8.5.20220314-x86_64 library-template
    ```
1. Remove the history of the branch by dereferencing the current HEAD from the tree. 
   ```
   git update-ref -d HEAD
   ```
1. Unpack the build artifact zip file to the current directory and accept overwriting
   ```
   unzip -d $PWD ~/Downloads/rocky-8.5-docker-x86_64.tar.xz.zip
   ```
1. Generate the packages.txt file using the instructions below. This step will parse the `build.meta` file included in the build artifacts, and write the list of packages out to `packages.txt`.
   ```shell
   xmllint --xpath "//packages/*/@name" <(printf "$(jq '.icicle' < build.meta)\n" | tr -d '\\' | tail -c +2 | head -c -2) | \
                 awk -F\= '{print substr($2,2,length($2)-2)}' | \
                 sort >! packages.txt
   ```
1. Add the files to be tracked by git using `git add .`. Then, check the git repo using `git status`. It should look something like this, having the new build artifacts as ready to be committed.
   ```
   On branch Rocky-8.5.20220314-x86_64

   No commits yet
 
   Changes to be committed:
     (use "git rm --cached <file>..." to unstage)
           new file:   Dockerfile
           new file:   build.meta
           new file:   filelist.txt
           new file:   packages.txt
           new file:   rocky-8.5-docker.tar.xz
   ```
1. Create a commit with a message regarding the changes. Perhaps using tools/pkgdiff.sh to show a list of changed packages from the previous-latest.
1. Push the commit to your fork and open a pull request to merge it as a new branch upstream. If you have commit-level access, this can also be done directly without forking.
1. Note the commit hash (shasum), as it is needed later for requesting the update from Docker.
1. Repeat for every architecture being updated.

#### Open pull request to request update

> :warning: Consult **ALL** the documentation on the docker-hub/official-images README page about the format of the file the official-images repository uses to build and release images.
> * Branches that will be referenced by the official-images repository data **MUST** contain only a single commit. A discrete branch will be created for each distinct image-tag that is released.

Once the branches are prepared, a PR can be created against https://github.com/docker-library/official-images to push the new images out and tag them appropriately. 

1. Fork and clone https://github.com/docker-hub/official-images to your machine. Cd into the directory containing the repository.
1. Create a new branch if preferred, or just commit against the latest master. Ensure your fork is up to date with upstream.
1. Edit the library/rockylinux file and rearrange any tags as needed. The `latest` and `MAJOR` tags (e.g., `8`) should always point to the most recent image, and the most recent image should also be tagged with a unique name containing an ISO8601 datestamp like 8.5.20220314. The MAJOR.MINOR tag **SHOULD NOT** change during a release cycle, and should instead always point to the initial container build post minor release.
1. Commit and create a pull request upstream requesting the change. If the change is a security one, ensure it is marked as such. Instructions for this are included in the README for the docker-hub/official-images repository.


#### Docker Hub Official Images Support

If support is required, or any questions about anything related to official images or our listing there, a great resource is the #docker-library channel on Libera.chat IRC. It's a relatively low traffic channel.

#### Official Image Readme

The readme for the official image is maintained in a separate repository - https://github.com/docker-library/docs. If any information on the README needs to be changed, submit a pull request on that repository.
