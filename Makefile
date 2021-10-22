ARCH           := $(shell uname -m)
RELEASE_VER    := 8.4

OUTPUT_DIR     := output
LOG_DIR        := logs

KICKSTART_DIR  := kickstarts
KICKSTART_PATH := "${KICKSTART_DIR}/Rocky-8-Container.ks"
BUILDDATE      := $(shell /bin/date +%Y%m%d_%H%M)

.PHONY        := all clean
.DEFAULT_GOAL := rocky-${RELEASE_VER}-docker-${ARCH}.tar.xz


clean:
	rm -frv ${KICKSTART_DIR} ${OUTPUT_DIR}

${KICKSTART_DIR}:
	git clone ssh://git@git.rockylinux.org:22220/rocky/kickstarts.git kickstarts
	cd kickstarts && git checkout r${RELEASE_VER}

${KICKSTART_PATH}: ${KICKSTART_DIR}
	echo cd kickstarts && git pull

rocky-${RELEASE_VER}-docker-${ARCH}.tar.xz: ${KICKSTART_PATH}
	sudo /usr/sbin/livemedia-creator --ks "${KICKSTART_PATH}" --make-tar --no-virt \
		--releasever "${RELEASE_VER}" --project "Rocky Linux ${RELEASE_VER} - ${BUILDDATE}" \
		--resultdir "${OUTPUT_DIR}" --logfile "${LOG_DIR}/build.log"

