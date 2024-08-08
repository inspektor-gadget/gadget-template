TAG := $(shell git describe --tags --always --dirty)
CONTAINER_REPO ?= ghcr.io/changeme-org/changeme-gadget-name
IMAGE_TAG ?= $(TAG)
CLANG_FORMAT ?= clang-format

.PHONY: build
build:
	sudo -E ig image build \
		-t $(CONTAINER_REPO):$(IMAGE_TAG) \
		--update-metadata .

# PARAMS can be used to pass additional parameters locally. For example:
# PARAMS="-o jsonpretty" make run
.PHONY: run
run:
	sudo -E ig run $(CONTAINER_REPO):$(IMAGE_TAG) $$PARAMS

.PHONY: push
push:
	sudo -E ig image push $(CONTAINER_REPO):$(IMAGE_TAG)
	
.PHONY: clang-format
clang-format:
	$(CLANG_FORMAT) -i program.bpf.c
