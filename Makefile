CONTAINER ?= podman
IMAGE ?= cosmic-deb-builder:trixie
COSMIC_PACKAGES ?= /workspace/packages.txt
BUILD_FLAGS :=
RUN_FLAGS :=

ifeq ($(CONTAINER),podman)
BUILD_FLAGS += --isolation=chroot
RUN_FLAGS += --cgroup-manager=cgroupfs
endif

.PHONY: image build shell clean dirs

image:
	$(CONTAINER) build $(BUILD_FLAGS) -t $(IMAGE) -f Containerfile .

build: dirs
	$(CONTAINER) run $(RUN_FLAGS) --rm -i \
		-v /etc/ssl/certs:/etc/ssl/certs:ro \
		-v $(CURDIR)/out:/out \
		-v $(CURDIR)/cache:/cache \
		-v $(CURDIR):/workspace:ro \
		-e COSMIC_PACKAGES="$(COSMIC_PACKAGES)" \
		$(IMAGE)

shell: dirs
	$(CONTAINER) run $(RUN_FLAGS) --rm -it \
		-v /etc/ssl/certs:/etc/ssl/certs:ro \
		-v $(CURDIR)/out:/out \
		-v $(CURDIR)/cache:/cache \
		-v $(CURDIR):/workspace \
		-e COSMIC_PACKAGES="$(COSMIC_PACKAGES)" \
		--entrypoint /bin/bash \
		$(IMAGE)

clean:
	rm -rf out cache

dirs:
	mkdir -p out cache
	chmod 0777 out cache
