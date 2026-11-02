.DEFAULT_GOAL := build
TAG := $(shell git describe --tags --always --dirty)
-include config.mk
CONTAINER_REPO ?=
IMAGE_TAG ?= $(TAG)
CLANG_FORMAT ?= clang-format
IG ?= ig
SUDO ?= sudo
BUILDER_IMAGE ?= ghcr.io/inspektor-gadget/gadget-builder:v0.57.0
SOURCES := $(wildcard program.bpf.c templates/*/program.bpf.c)

.PHONY: initialized
initialized:
	@test -f program.bpf.c -a -f gadget.yaml -a -n "$(CONTAINER_REPO)" || \
		{ echo "Initialize first: bash scripts/init.sh (see README.md)" >&2; exit 1; }

.PHONY: build
build: initialized
	$(SUDO) $(IG) image build \
		--builder-image $(BUILDER_IMAGE) \
		-t $(CONTAINER_REPO):$(IMAGE_TAG) \
		.

# PARAMS can be used to pass additional parameters locally. For example:
# PARAMS="-o jsonpretty" make run
.PHONY: run
run: initialized
	$(SUDO) $(IG) run $(CONTAINER_REPO):$(IMAGE_TAG) $$PARAMS

.PHONY: run-local
run-local: build
	$(SUDO) $(IG) run $(CONTAINER_REPO):$(IMAGE_TAG) --verify-image=false --pull never $$PARAMS

.PHONY: push
push: initialized
	$(SUDO) $(IG) image push $(CONTAINER_REPO):$(IMAGE_TAG)

.PHONY: metadata
metadata: initialized
	$(SUDO) $(IG) image build --builder-image $(BUILDER_IMAGE) \
		-t $(CONTAINER_REPO):$(IMAGE_TAG) --update-metadata .

.PHONY: clang-format
clang-format:
	$(CLANG_FORMAT) -i $(SOURCES)

.PHONY: check
check:
	$(CLANG_FORMAT) --dry-run --Werror $(SOURCES)

.PHONY: test
test:
	@if test -f tests/init.sh; then bash tests/init.sh; else $(MAKE) check; fi
