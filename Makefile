ARCH           = $(shell uname -m)
BUILDDATE      = $(shell /bin/date +%Y%m%d_%H%M)
KICKSTART_DIR  = kickstarts
KICKSTART_PATH = "${KICKSTART_DIR}/Rocky-8-Container.ks"
LOG_DIR        = logs
OUTPUT_DIR     = output
RELEASE_VER    = 8.4
MAJOR          = $(shell v='$(RELEASE_VER)'; echo "$${v%.*}")
TEMPLATE_DIR   = templates
TEMPLATE_PATH  = "${TEMPLATE_DIR}/tdl-${ARCH}.xml"

OUTNAME          := rocky-${RELEASE_VER}-docker-${ARCH}
BASEIMAGE_META   := base_image-$(OUTNAME).meta
TARGETIMAGE_META := target_image-$(OUTNAME).meta

STORAGEDIR       := /var/lib/imagefactory/storage

.PHONY        := all clean setup
.DEFAULT_GOAL := $(OUTNAME).tar.xz

BASEIMAGEUUID   = $(shell awk '$$1=="UUID:"{print $$NF}' $(BASEIMAGE_META))
TARGETIMAGEUUID = $(shell awk '$$1=="UUID:"{print $$NF}' $(TARGETIMAGE_META))

ifneq ($(DEBUG),)
DEBUGPARAM := --debug
endif

# Basic type is just 'container'
TYPE=container
CONTAINER_NAME = rocky-$(MAJOR)-$(TYPE)-$(RELEASE_VER).$(BUILDDATE).$(ARCH)

clean:
	-rm *.meta 

$(KICKSTART_DIR):
	git clone --branch r$(MAJOR) --single-branch https://git.rockylinux.org/rocky/kickstarts.git kickstarts

$(BASEIMAGE_META): $(KICKSTART_DIR)
	sudo imagefactory $(DEBUGPARAM) base_image \
		--parameter offline_icicle true \
		--file-parameter install_script ${KICKSTART_PATH} \
		${TEMPLATE_PATH} \
		| tee -a logs/base_image-$(OUTNAME).out | tail -n4 > $(BASEIMAGE_META) || exit 2

$(TARGETIMAGE_META): $(BASEIMAGE_META)
	sudo imagefactory $(DEBUGPARAM) target_image \
		--id $(BASEIMAGEUUID) \
		--parameter compress xz \
		--parameter repository $(CONTAINER_NAME) \
		docker | tee -a logs/target_image-$(OUTNAME).out | tail -n4 > $(TARGETIMAGE_META) || exit 3

$(OUTNAME).tar.xz: $(TARGETIMAGE_META)
	mkdir out
	ln $(STORAGEDIR)/$(TARGETIMAGEUUID).body out/$(TARGETIMAGEUUID).tar.xz
	tar -Oxf out/$(TARGETIMAGEUUID).tar.xz */layer.tar | xz > out/$(OUTNAME).tar.xz

publish:
	@echo out/$(OUTNAME).tar.xz
