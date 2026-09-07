TARGET := iphone:clang:6.0:6.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = AppStore

MAKEFLAGS += --output-sync=none

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AppStoreFix

AppStoreFix_FILES = Tweak.x ASFXBootstrapBridge.m ASFXStoreCompatibility.m
AppStoreFix_CFLAGS = -fobjc-arc
AppStoreFix_FRAMEWORKS = Security

include $(THEOS_MAKE_PATH)/tweak.mk

# ------------------------------- PACKAGE PIPELINES -------------------------------
# Keep the same development/release workflow as the other tweaks.
# Do not indent the ifeq/else/endif directives.
# Force sequential execution so output and package deployment stay ordered.
.NOTPARALLEL: after-stage after-package dev-pipeline release-pipeline
MAKEFLAGS += -j1

ifeq ($(FINALPACKAGE),)
after-package:: dev-pipeline
else
after-package:: release-pipeline
endif

.PHONY: dev-pipeline release-pipeline

dev-pipeline:
	# Mirror progress to stderr so progress is visible with grouped make output.
	@echo "[📌] Starting Build on DEV Pipeline" 1>&2
	# Run the pipeline under a PTY so child tools line-buffer their output.
	@script -q /dev/null /bin/bash -lc 'set -euo pipefail; \
		echo "[ℹ️ ] Locating latest .deb…"; \
		shopt -s nullglob; DEBS=("$(THEOS_PACKAGE_DIR)"/*.deb); \
		DEB=""; for CANDIDATE in "$${DEBS[@]}"; do \
			if [ -z "$$DEB" ] || [ "$$CANDIDATE" -nt "$$DEB" ]; then DEB="$$CANDIDATE"; fi; \
		done; \
		if [ -z "$$DEB" ] || [ ! -f "$$DEB" ]; then echo "[❌] No .deb found in $(THEOS_PACKAGE_DIR)"; exit 1; fi; \
		echo "[ℹ️ ] Found: $$DEB"; \
		BASE="$$(basename "$$DEB" .deb)"; TMP="$${BASE#*_}"; VERSION="$${TMP%_*}"; \
		echo "[ℹ️ ] Version: $$VERSION"; \
		echo "[📦] Git commit (build artifact only)…"; \
		git add -f -- "$$DEB"; \
		if git commit --only -m "Build $$VERSION" -- "$$DEB"; then echo "[✅] Build artifact committed"; else echo "[⚠️ ] Nothing to commit"; fi; \
		DEST="/Volumes/victor/Sites/repo-dev/debs"; \
		echo "[📂] Copy .deb → $$DEST"; \
		mkdir -p "$$DEST"; cp -v "$$DEB" "$$DEST/"; \
		echo "[⚙️ ] Run repo update…"; \
		cd /Volumes/victor/Sites/repo-dev; \
		if [ -x ./Update.sh ]; then ./Update.sh; \
		elif [ -x ./update.sh ]; then ./update.sh; \
		elif [ -f ./Update.sh ]; then /bin/bash ./Update.sh; \
		elif [ -f ./update.sh ]; then /bin/bash ./update.sh; \
		else echo "[⚠️ ] Warning: update script not found"; fi; \
		echo "[✅] Repo update finished"; \
		MSG="Built $$VERSION and updated repo"; \
		echo "[🔔] Notifying macOS…"; \
		/usr/bin/osascript -e "display notification \"$$MSG\" with title \"AppStoreFix Build\" subtitle \"Deployment complete\"" \
		&& echo "[✅] Notification sent" || echo "[⚠️ ] Could not display notification"'

release-pipeline:
	@echo "[📌] Starting Build on RELEASE Pipeline" 1>&2
	@script -q /dev/null /bin/bash -lc 'set -euo pipefail; \
		shopt -s nullglob; DEBS=("$(THEOS_PACKAGE_DIR)"/*.deb); \
		DEB=""; for CANDIDATE in "$${DEBS[@]}"; do \
			if [ -z "$$DEB" ] || [ "$$CANDIDATE" -nt "$$DEB" ]; then DEB="$$CANDIDATE"; fi; \
		done; \
		if [ -z "$$DEB" ] || [ ! -f "$$DEB" ]; then echo "[❌] No .deb found in $(THEOS_PACKAGE_DIR)"; exit 1; fi; \
		BASE="$$(basename "$$DEB" .deb)"; TMP="$${BASE#*_}"; VER="$${TMP%_*}"; \
		echo "[🚀 RELEASE] Built $$DEB (Version: $$VER)"; \
		echo "[ℹ️ ] (Release mode: no deploy; committing build artifact only)"; \
		git add -f -- "$$DEB"; \
		if git commit --only -m "Release $$VER" -- "$$DEB"; then \
			echo "[✅] Git commit: Release $$VER (build artifact only)"; \
		else \
			echo "[⚠️ ] Nothing to commit"; \
		fi;'
