SHELL := /bin/bash

USR          := $(shell id -un)
UID          := $(shell id -u)
GID          := $(shell id -g)
HOSTNAME_VAR := $(shell bash -lc 'echo $${USER:0:3}')
IMAGE        := $(USR)/symbfuzz:dev
CONTAINER    := sbf-$(USR)
CMD          :=

HOST_WS       := $(CURDIR)
CONT_WS       := /repo/fuzzers/$(notdir $(CURDIR))
CONT_SYMBFUZZ := $(CONT_WS)

EXAMPLE_VERILOG       ?= examples/counter.v
EXAMPLE_TOP           ?= counter
EXAMPLE_STAMP         ?= $(shell date +%Y%m%d_%H%M%S)
EXAMPLE_OUTPUT_DIR    ?= fuzz_runs/$(EXAMPLE_TOP)_$(EXAMPLE_STAMP)
EXAMPLE_MODE          ?= auto
EXAMPLE_TIMEOUT       ?= 30
EXAMPLE_STALL_CYCLES  ?= 100
EXAMPLE_BMC_MAX_STEPS ?= 20
EXAMPLE_EXTRA_ARGS    ?=

.PHONY: fresh image start enter run run_example kill init build

fresh: kill image start

image:
	docker build \
		-f Dockerfile \
		--build-arg UID=$(UID) \
		--build-arg GID=$(GID) \
		--build-arg USERNAME=$(USR) \
		--build-arg CONT_WS=$(CONT_WS) \
		-t $(IMAGE) .

start:
	mkdir -p $(HOST_WS)
	docker run -d --name $(CONTAINER) \
		-h $(HOSTNAME_VAR) \
		-e CONT_WS=$(CONT_WS) \
		--tty --interactive \
		-v $(HOST_WS):$(CONT_WS) \
		-w $(CONT_WS) \
		$(IMAGE) tail -f /dev/null
	$(MAKE) init
	$(MAKE) build

enter:
	docker exec -it $(CONTAINER) bash -i

run:
	docker exec -it $(CONTAINER) /bin/bash -ic 'cd "$$CONT_WS" && $(CMD)'

run_example:
	@echo "SymbFuzz output directory: $(EXAMPLE_OUTPUT_DIR)"
	docker exec $(CONTAINER) /bin/bash -lc '\
		export CONT_SYMBFUZZ="$(CONT_SYMBFUZZ)" && \
		export EXAMPLE_VERILOG="$(EXAMPLE_VERILOG)" && \
		export EXAMPLE_TOP="$(EXAMPLE_TOP)" && \
		export EXAMPLE_OUTPUT_DIR="$(EXAMPLE_OUTPUT_DIR)" && \
		export EXAMPLE_MODE="$(EXAMPLE_MODE)" && \
		export EXAMPLE_TIMEOUT="$(EXAMPLE_TIMEOUT)" && \
		export EXAMPLE_STALL_CYCLES="$(EXAMPLE_STALL_CYCLES)" && \
		export EXAMPLE_BMC_MAX_STEPS="$(EXAMPLE_BMC_MAX_STEPS)" && \
		export EXAMPLE_EXTRA_ARGS="$(EXAMPLE_EXTRA_ARGS)" && \
		bash "$(CONT_WS)/run.sh" \
	'

kill:
	- docker kill $(CONTAINER) || true
	- docker rm   $(CONTAINER) || true

init:
	docker exec $(CONTAINER) /bin/bash -lc '\
		mkdir -p "$(CONT_WS)" && \
		test -f "$(CONT_SYMBFUZZ)/README.md" || { \
			echo "Missing SymbFuzz checkout at $(CONT_SYMBFUZZ)"; \
			exit 1; \
		} \
	'

build:
	docker exec $(CONTAINER) /bin/bash -lc '\
		export CONT_SYMBFUZZ="$(CONT_SYMBFUZZ)" && \
		bash "$(CONT_WS)/build.sh" \
	'
