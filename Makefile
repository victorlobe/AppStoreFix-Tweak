TARGET := iphone:clang:6.0:5.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = AppStore itunesstored MobileStore Podcasts iBooks

# Pin Xcode 26.6 (ld-1267): Xcode 27's ld emits armv7 binaries without lazy binding
# (__picsymbolstub5) that crash on iOS 5/6 (SIGILL). Same as Veteris and iCloudMailFix.
# Theos can't handle the space in "Xcode 26.6.app", so go through a space-free symlink.
# Thank you Claude for discovering this after i nearly lost my mind.
XCODE26_APP ?= /Applications/Xcode 26.6.app
XCODE26_LINK := $(CURDIR)/.theos/Xcode26.app
$(shell mkdir -p "$(CURDIR)/.theos" && ln -sfn "$(XCODE26_APP)" "$(XCODE26_LINK)")
export DEVELOPER_DIR := $(XCODE26_LINK)/Contents/Developer
MAKE := $(DEVELOPER_DIR)/usr/bin/make
_ASFX_TC := $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin
TARGET_CC := $(_ASFX_TC)/clang
TARGET_CXX := $(_ASFX_TC)/clang++
TARGET_LD := $(_ASFX_TC)/clang
TARGET_LIPO := $(_ASFX_TC)/lipo
TARGET_STRIP := $(_ASFX_TC)/strip
TARGET_DSYMUTIL := $(_ASFX_TC)/dsymutil
TARGET_CODESIGN_ALLOCATE := $(_ASFX_TC)/codesign_allocate
export TARGET_CC TARGET_CXX TARGET_LD TARGET_LIPO TARGET_STRIP TARGET_DSYMUTIL TARGET_CODESIGN_ALLOCATE

MAKEFLAGS += --output-sync=none

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AppStoreFix

AppStoreFix_FILES = Tweak.x ASFXBootstrapBridge.m ASFXStoreCompatibility.m
AppStoreFix_CFLAGS = -fobjc-arc
AppStoreFix_FRAMEWORKS = Security

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AppStoreFixPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

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
