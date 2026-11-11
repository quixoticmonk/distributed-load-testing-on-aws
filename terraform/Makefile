# Distributed Load Testing on AWS - Terraform build and deploy.
#
# Artifacts (Lambda zips, web console, JMeter bundle) are file targets and are
# prerequisites of plan/apply, so a forgotten build never surfaces as an apply error.
# Lambda bundling mirrors the esbuild command CDK's NodejsFunction runs.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# This folder lives inside the upstream repository, next to source/ and deployment/.
UPSTREAM ?= $(abspath ..)
SRC      := $(UPSTREAM)/source
BUILD    := $(abspath build)
TF_DIR   ?= examples/complete
TF       ?= terraform
ESBUILD  := $(SRC)/infrastructure/node_modules/.bin/esbuild

# Fixed mtime so rebuilt zips hash identically when the bundle content is unchanged.
ZIP_EPOCH := 202001010000

# name => entry file (relative to $(SRC) unless absolute)
LAMBDA_ENTRY_api-services            := api-services/index.ts
LAMBDA_ENTRY_mcp-server              := mcp-server/src/index.ts
LAMBDA_ENTRY_metrics-emitter         := infrastructure/lambda/metrics-emitter/index.ts
LAMBDA_ENTRY_orphan-cleanup          := orphan-cleanup/src/index.ts
LAMBDA_ENTRY_real-time-data-publisher := real-time-data-publisher/src/index.ts
LAMBDA_ENTRY_regional-sync           := regional-sync/src/index.ts
LAMBDA_ENTRY_results-parser          := results-parser/index.js
LAMBDA_ENTRY_sfn-failure-handler     := sfn-failure-handler/src/index.ts
LAMBDA_ENTRY_stabilization-checker   := stabilization-checker/src/index.ts
LAMBDA_ENTRY_start-command           := start-command/src/index.ts
LAMBDA_ENTRY_task-canceler           := task-canceler/src/index.ts
LAMBDA_ENTRY_task-failure-handler    := task-failure-handler/src/index.ts
LAMBDA_ENTRY_task-runner             := task-runner/src/index.ts
LAMBDA_ENTRY_task-status-checker     := task-status-checker/src/index.ts
LAMBDA_ENTRY_test-cleanup            := test-cleanup/src/index.ts
LAMBDA_ENTRY_test-metadata-updater   := test-metadata-updater/src/index.ts
LAMBDA_ENTRY_ops-adapter             := $(abspath ops-adapter/index.js)

LAMBDAS := $(patsubst LAMBDA_ENTRY_%,%,$(filter LAMBDA_ENTRY_%,$(.VARIABLES)))

# api-services bundles @aws-sdk/client-devops-agent (not in the Lambda runtime) and
# leaves the rest of the SDK external, matching source/infrastructure/lib/front-end/api.ts.
API_EXTERNALS := client-cloudformation client-cloudwatch client-cloudwatch-events \
  client-cloudwatch-logs client-dynamodb client-ecs client-lambda client-s3 \
  client-scheduler client-service-quotas client-sfn lib-dynamodb
EXTERNALS_api-services := $(foreach m,$(API_EXTERNALS),--external:@aws-sdk/$(m))
EXTERNALS_DEFAULT      := --external:@aws-sdk/*

LAMBDA_ZIPS   := $(foreach l,$(LAMBDAS),$(BUILD)/lambda/$(l).zip)
WEBUI_STAMP   := $(BUILD)/webui/index.html
JMETER_BUNDLE := $(BUILD)/jmeter/jmeter-bundle.tgz
DEPS_STAMP    := $(BUILD)/.deps-installed
ARTIFACTS     := $(LAMBDA_ZIPS) $(WEBUI_STAMP) $(JMETER_BUNDLE)
PLAN_FILE     := $(TF_DIR)/tfplan

# Reinstall whenever any upstream lockfile changes (root workspace, CDK app, legacy packages).
LOCKFILES := $(UPSTREAM)/package-lock.json $(wildcard $(SRC)/*/package-lock.json)

# Every source file outside node_modules; a change rebuilds the bundles.
SOURCES := $(shell find $(SRC) ops-adapter -path '*/node_modules' -prune -o -path '*/dist' -prune -o \
  -path '*/coverage' -prune -o -type f \( -name '*.ts' -o -name '*.js' -o -name '*.json' \) -print 2>/dev/null)

.PHONY: help deps build lambdas webui jmeter fmt fmt-check validate lint scan test init plan apply destroy output clean

help:
	@echo "Build"
	@echo "  make build      Lambda zips, web console, JMeter bundle into ./build"
	@echo "  make deps       npm installs for upstream (rerun automatically when lockfiles change)"
	@echo "  make lambdas | webui | jmeter   build one artifact group"
	@echo "  make clean      remove ./build"
	@echo "Check (no AWS)"
	@echo "  make fmt | fmt-check | validate | lint | scan | test"
	@echo "Deploy (TF_DIR=$(TF_DIR))"
	@echo "  make plan       build, then save a plan to $(PLAN_FILE)"
	@echo "  make apply      apply the saved plan (fails if missing or stale)"
	@echo "  make destroy    build, then destroy (prompts; AUTO_APPROVE=1 to skip)"
	@echo "  make output     show outputs"

# --- Upstream dependencies ---------------------------------------------------
# Upstream pins node >= 24; bundles target node24 regardless of the local node.
$(DEPS_STAMP): $(LOCKFILES)
	cd $(UPSTREAM) && npm ci --no-audit --no-fund --engine-strict=false
	cd $(SRC)/infrastructure && npm ci --no-audit --no-fund --engine-strict=false
	cd $(SRC) && npm_config_engine_strict=false bash install-legacy.sh
	mkdir -p $(@D) && touch $@

deps: $(DEPS_STAMP)

# --- Lambda bundles ----------------------------------------------------------
$(BUILD)/lambda/%.zip: $(DEPS_STAMP) $(SOURCES)
	@rm -rf $(BUILD)/lambda/$*; mkdir -p $(BUILD)/lambda/$*
	$(ESBUILD) --bundle $(if $(filter /%,$(LAMBDA_ENTRY_$*)),$(LAMBDA_ENTRY_$*),$(SRC)/$(LAMBDA_ENTRY_$*)) \
	  --target=node24 --platform=node --log-level=warning \
	  --outfile=$(BUILD)/lambda/$*/index.js \
	  $(or $(EXTERNALS_$*),$(EXTERNALS_DEFAULT))
	touch -t $(ZIP_EPOCH) $(BUILD)/lambda/$*/index.js
	cd $(BUILD)/lambda/$* && rm -f ../$*.zip && zip -qX ../$*.zip index.js

lambdas: $(LAMBDA_ZIPS)

# --- Web console -------------------------------------------------------------
$(WEBUI_STAMP): $(DEPS_STAMP) $(shell find $(SRC)/webui/src $(SRC)/webui/public -type f 2>/dev/null)
	cd $(SRC)/webui && npm run build
	rm -rf $(BUILD)/webui && mkdir -p $(BUILD)/webui
	cp -R $(SRC)/webui/dist/. $(BUILD)/webui/
	# aws-exports.json is written by Terraform with deployment-specific values.
	rm -f $(BUILD)/webui/aws-exports.json

webui: $(WEBUI_STAMP)

# --- JMeter bundle (needed by JMeter and the default "simple" HTTP test type) -
$(JMETER_BUNDLE): $(UPSTREAM)/jmeter.json
	mkdir -p $(BUILD)/jmeter
	bash -c 'source $(UPSTREAM)/scripts/download-jmeter-bundle.sh && download_jmeter_assets $(BUILD)/jmeter'

jmeter: $(JMETER_BUNDLE)

build: $(ARTIFACTS)

# --- Terraform ---------------------------------------------------------------
# dlt-region declares configuration_aliases, so it validates through examples/ only.
MODULE_DIRS := $(filter-out modules/dlt-region,$(wildcard modules/*)) $(wildcard examples/*)
TEST_DIRS   := $(patsubst %/tests,%,$(wildcard modules/*/tests examples/*/tests))

fmt:
	$(TF) fmt -recursive

fmt-check:
	$(TF) fmt -recursive -check -diff

validate:
	@for d in $(MODULE_DIRS); do \
	  echo "== $$d"; \
	  $(TF) -chdir=$$d init -backend=false -input=false >/dev/null && $(TF) -chdir=$$d validate -no-color || exit 1; \
	done

lint:
	@for d in $(MODULE_DIRS); do \
	  echo "== $$d"; \
	  tflint --chdir=$$d --init >/dev/null && tflint --chdir=$$d || exit 1; \
	done

scan:
	checkov -d modules --framework terraform --quiet --compact --skip-download

# Mocked providers: no AWS credentials, no cost. Needs build artifacts.
test: $(ARTIFACTS)
	@for d in $(TEST_DIRS); do \
	  echo "== $$d"; \
	  $(TF) -chdir=$$d init -backend=false -input=false >/dev/null && $(TF) -chdir=$$d test -no-color || exit 1; \
	done

init:
	$(TF) -chdir=$(TF_DIR) init -input=false

plan: build init
	$(TF) -chdir=$(TF_DIR) plan -input=false -out=tfplan

# Applies only a reviewed, saved plan. No build step here: rebuilding between plan and
# apply would upload artifacts whose hashes differ from the ones recorded in the plan.
apply: init
	@test -f $(PLAN_FILE) || { echo "No saved plan at $(PLAN_FILE). Run 'make plan' and review it first."; exit 1; }
	@stale=$$(find $(ARTIFACTS) $$(find modules $(TF_DIR) -name '*.tf' -o -name '*.tftpl' -o -name '*.tfvars') \
	  -newer $(PLAN_FILE) 2>/dev/null | head -1); \
	  if [ -n "$$stale" ]; then echo "$$stale changed after the plan was saved. Run 'make plan' again."; exit 1; fi
	$(TF) -chdir=$(TF_DIR) apply -input=false tfplan
	rm -f $(PLAN_FILE)

# Destroy still evaluates filebase64sha256() on the artifacts, so they must exist.
# Interactive by default; AUTO_APPROVE=1 for non-interactive runs.
destroy: build init
	$(TF) -chdir=$(TF_DIR) destroy $(if $(filter 1,$(AUTO_APPROVE)),-auto-approve,)

output:
	$(TF) -chdir=$(TF_DIR) output

clean:
	rm -rf $(BUILD)
