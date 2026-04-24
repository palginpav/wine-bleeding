SHELL := /usr/bin/env bash

PREFIX     ?= /usr/local
DESTDIR    ?=
# Allow callers to override lib and share dirs independently.
# Default: PREFIX/lib and PREFIX/share (FHS-compliant for multi-arch use
# set LIBDIR=$(PREFIX)/lib explicitly to avoid lib64).
LIBDIR     ?= $(PREFIX)/lib
SHAREDIR   ?= $(PREFIX)/share

RUNTIME_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SRC_DIR     := $(RUNTIME_DIR)src
TESTS_DIR   := $(RUNTIME_DIR)tests
VENDOR_BATS := $(TESTS_DIR)/vendor/bats-core/bin/bats

SCHEMA_FILE           := $(RUNTIME_DIR)share/schemas/wb_dist_meta.schema.json
SCHEMA_FILE_PFX       := $(RUNTIME_DIR)share/schemas/wb_runtime.schema.json
SCHEMA_FILE_COMP      := $(RUNTIME_DIR)share/schemas/wb_components.schema.json
SCHEMA_FILE_PPDB      := $(RUNTIME_DIR)share/schemas/wb_ppdb.schema.json
SCHEMA_FILE_PLUGIN    := $(RUNTIME_DIR)share/schemas/wb_runtime_plugin.schema.json
FIXTURE_PLUGIN        := $(TESTS_DIR)/fixtures/runtime-plugins/ge-proton-9-26.json
FIXTURE_DIST          := $(TESTS_DIR)/fixtures/fake-dist
FIXTURE_PP_PREFIX     := $(TESTS_DIR)/fixtures/fake-pp-prefix

PACKAGING_DIR := $(RUNTIME_DIR)packaging

SHELLCHECK_TARGETS := \
  $(SRC_DIR)/wb \
  $(SRC_DIR)/wb-gui \
  $(SRC_DIR)/wb-gui-lib/wb-gui-games.sh \
  $(SRC_DIR)/wb-gui-lib/wb-gui-dialogs.sh \
  $(SRC_DIR)/wb-gui-lib/wb-gui-prefix.sh \
  $(SRC_DIR)/wb-gui-lib/wb-gui-settings.sh \
  $(SRC_DIR)/wb-gui-lib/wb-gui-overlays.sh \
  $(SRC_DIR)/wb-diag \
  $(SRC_DIR)/wb-lib/wb-log.sh \
  $(SRC_DIR)/wb-lib/wb-die.sh \
  $(SRC_DIR)/wb-lib/wb-paths.sh \
  $(SRC_DIR)/wb-lib/wb-config.sh \
  $(SRC_DIR)/wb-lib/wb-json.sh \
  $(SRC_DIR)/wb-lib/wb-lock.sh \
  $(SRC_DIR)/wb-lib/wb-dist.sh \
  $(SRC_DIR)/wb-lib/wb-prefix.sh \
  $(SRC_DIR)/wb-lib/wb-components.sh \
  $(SRC_DIR)/wb-lib/wb-reg.sh \
  $(SRC_DIR)/wb-lib/wb-wineboot.sh \
  $(SRC_DIR)/wb-lib/wb-ppdb.sh \
  $(SRC_DIR)/wb-lib/wb-env.sh \
  $(SRC_DIR)/wb-lib/wb-hooks.sh \
  $(SRC_DIR)/wb-lib/wb-pp-installer.sh \
  $(SRC_DIR)/wb-lib/wb-snapshot.sh \
  $(SRC_DIR)/wb-lib/wb-multibuild.sh \
  $(SRC_DIR)/wb-lib/wb-container.sh \
  $(SRC_DIR)/wb-lib/wb-runtimes.sh \
  $(SRC_DIR)/hooks/reapply.sh \
  $(RUNTIME_DIR)share/compatibilitytools.d/wine-bleeding/wine-bleeding.sh \
  $(RUNTIME_DIR)install.sh \
  $(RUNTIME_DIR)publish-release-integration.sh \
  $(PACKAGING_DIR)/rpm/build.sh \
  $(PACKAGING_DIR)/deb/build.sh \
  $(PACKAGING_DIR)/appimage/build-appimage.sh \
  $(PACKAGING_DIR)/appimage/AppRun \
  $(RUNTIME_DIR)../tools/run-winetricks.sh \
  $(SRC_DIR)/wb-gui-lib/wb-gui-build-env.sh \
  $(RUNTIME_DIR)../tools/build-glslang.sh

FLATPAK_DIR      := $(RUNTIME_DIR)flatpak
FLATPAK_MANIFEST := $(FLATPAK_DIR)/org.wine_bleeding.wb.yaml

.PHONY: test lint install schema-check flatpak-validate flatpak-build \
        dist-rpm dist-deb dist-appimage dist-all

test:
	@# Per-file timeout (WB_TEST_FILE_TIMEOUT_SEC, default 180s) protects the
	@# suite against files that deadlock under the fake-yad harness when real
	@# wb-gui event pipes exit out-of-order (known-flaky files documented in
	@# feedback_bats_invocation.md). Without this, `make test` in CI would
	@# run until GitHub's 6-hour job cap on any hang. `timeout` exit 124
	@# is surfaced as a per-file failure without aborting the whole loop.
	@set -u; \
	if [[ -x "$(VENDOR_BATS)" ]]; then \
	  BATS_BIN="$(VENDOR_BATS)"; echo "Using vendored bats-core at $(VENDOR_BATS)"; \
	elif command -v bats >/dev/null 2>&1; then \
	  BATS_BIN="$$(command -v bats)"; echo "Using system bats on PATH"; \
	else \
	  echo "SKIP: bats-core not found. Run: git submodule update --init -- runtime/tests/vendor/bats-core"; \
	  exit 0; \
	fi; \
	timeout_sec="$${WB_TEST_FILE_TIMEOUT_SEC:-180}"; \
	overall=0; total=0; passed=0; failed=0; timed_out=0; \
	fail_list=""; timeout_list=""; \
	for f in "$(TESTS_DIR)"/*.bats; do \
	  [[ -f "$$f" ]] || continue; \
	  total=$$((total+1)); \
	  name=$$(basename "$$f"); \
	  if timeout --foreground "$$timeout_sec" "$$BATS_BIN" "$$f"; then \
	    passed=$$((passed+1)); \
	  else \
	    rc=$$?; \
	    if [[ "$$rc" -eq 124 ]]; then \
	      timed_out=$$((timed_out+1)); timeout_list="$$timeout_list $$name"; \
	      echo "TIMEOUT ($${timeout_sec}s): $$name"; \
	    else \
	      failed=$$((failed+1)); fail_list="$$fail_list $$name"; \
	    fi; \
	    overall=1; \
	  fi; \
	done; \
	echo ""; \
	echo "bats summary: $$total files, $$passed passed, $$failed failed, $$timed_out timed out"; \
	[[ -n "$$fail_list" ]]    && echo "  failed:  $$fail_list"; \
	[[ -n "$$timeout_list" ]] && echo "  timeout: $$timeout_list"; \
	exit "$$overall"

lint:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
	  echo "SKIP: shellcheck not found on PATH"; \
	  exit 0; \
	else \
	  shellcheck --severity=warning -x --source-path=$(SRC_DIR) $(SHELLCHECK_TARGETS); \
	fi

schema-check:
	@if ! command -v check-jsonschema >/dev/null 2>&1; then \
	  echo "SKIP: check-jsonschema not found (pip install check-jsonschema)"; \
	  exit 0; \
	else \
	  echo "Generating manifest from fixture dist for schema validation..."; \
	  tmp_home=$$(mktemp -d); \
	  mkdir -p "$${tmp_home}/dist"; \
	  cp -a "$(FIXTURE_DIST)" "$${tmp_home}/dist/WINE-BLEEDING-fixture"; \
	  WB_HOME="$${tmp_home}" bash -c " \
	    source $(SRC_DIR)/wb-lib/wb-log.sh 2>/dev/null; \
	    source $(SRC_DIR)/wb-lib/wb-json.sh; \
	    source $(SRC_DIR)/wb-lib/wb-dist.sh; \
	    wb_dist_meta_write '$${tmp_home}/dist/WINE-BLEEDING-fixture' \
	  "; \
	  check-jsonschema --schemafile "$(SCHEMA_FILE)" \
	    "$${tmp_home}/dist/WINE-BLEEDING-fixture/.wb_dist_meta"; \
	  rc=$$?; rm -rf "$${tmp_home}"; exit $$rc || exit $$rc; \
	  echo "Validating wb_runtime.schema.json against generated sentinel fixture..."; \
	  tmp_pfx=$$(mktemp -d); \
	  tmp_home2=$$(mktemp -d); \
	  export WB_HOME="$${tmp_home2}"; \
	  cp -a "$(FIXTURE_PP_PREFIX)/." "$${tmp_pfx}/"; \
	  WB_HOME="$${tmp_home2}" WB_LOG_FILE="$${tmp_home2}/wb.log" bash -c " \
	    source $(SRC_DIR)/wb-lib/wb-log.sh; \
	    source $(SRC_DIR)/wb-lib/wb-json.sh; \
	    source $(SRC_DIR)/wb-lib/wb-lock.sh; \
	    source $(SRC_DIR)/wb-lib/wb-dist.sh; \
	    source $(SRC_DIR)/wb-lib/wb-prefix.sh; \
	    wb_prefix_adopt '$${tmp_pfx}' \
	  "; \
	  check-jsonschema --schemafile "$(SCHEMA_FILE_PFX)" "$${tmp_pfx}/.wb_runtime"; \
	  rc2=$$?; rm -rf "$${tmp_pfx}" "$${tmp_home2}"; \
	  echo "Validating wb_components.schema.json against a minimal components fixture..."; \
	  tmp_comp=$$(mktemp -d); \
	  cat > "$${tmp_comp}/test_manifest.json" <<COMPEOF \
{ \
  "schema": 1, \
  "prefix_path": "/tmp/pfx", \
  "dist_target": "/tmp/dist", \
  "dist_manifest_hash": "", \
  "deployed_utc": "2026-04-18T12:00:00Z", \
  "components": { \
    "dxvk":  {"version": "2.7.1-509", "dll_count": 4, "dll_paths": ["drive_c/windows/system32/d3d11.dll"]}, \
    "vkd3d": {"version": "1.14",       "dll_count": 2, "dll_paths": []}, \
    "nvapi": {"version": "0.7.1",      "dll_count": 2, "dll_paths": []}, \
    "mono":  {"version": "wine-mono-10.1.0", "dll_count": 4, "dll_paths": []}, \
    "icu":   {"version": "68",         "dll_count": 2, "dll_paths": []} \
  } \
} \
COMPEOF \
	  check-jsonschema --schemafile "$(SCHEMA_FILE_COMP)" "$${tmp_comp}/test_manifest.json"; \
	  rc3=$$?; rm -rf "$${tmp_comp}"; \
	  if [[ -f "$(SCHEMA_FILE_PPDB)" ]]; then \
	    echo "Validating wb_ppdb.schema.json against fixture..."; \
	    tmp_ppdb=$$(mktemp -d); \
	    cp "$(TESTS_DIR)/fixtures/ppdb/valid.wb.ppdb" "$${tmp_ppdb}/valid.wb.ppdb"; \
	    check-jsonschema --schemafile "$(SCHEMA_FILE_PPDB)" "$${tmp_ppdb}/valid.wb.ppdb"; \
	    rc4=$$?; rm -rf "$${tmp_ppdb}"; \
	  else \
	    rc4=0; \
	  fi; \
	  if [[ -f "$(SCHEMA_FILE_PLUGIN)" && -f "$(FIXTURE_PLUGIN)" ]]; then \
	    echo "Validating wb_runtime_plugin.schema.json against fixture..."; \
	    check-jsonschema --schemafile "$(SCHEMA_FILE_PLUGIN)" "$(FIXTURE_PLUGIN)"; \
	    rc5=$$?; \
	  else \
	    rc5=0; \
	  fi; \
	  exit $$rc2 || exit $$rc3 || exit $$rc4 || exit $$rc5; \
	fi

install:
	@echo "Installing wine-bleeding-wb to $(DESTDIR)$(PREFIX) (LIBDIR=$(LIBDIR))"
	install -Dm755 $(SRC_DIR)/wb         $(DESTDIR)$(PREFIX)/bin/wb
	install -Dm755 $(SRC_DIR)/wb-diag    $(DESTDIR)$(PREFIX)/bin/wb-diag
	@if test -f $(SRC_DIR)/wb-gui; then \
	  install -Dm755 $(SRC_DIR)/wb-gui   $(DESTDIR)$(PREFIX)/bin/wb-gui; \
	fi
	@for f in $(SRC_DIR)/wb-lib/*.sh; do \
	  install -Dm644 "$$f" "$(DESTDIR)$(LIBDIR)/wine-bleeding/wb-lib/$$(basename $$f)"; \
	done
	@if ls $(SRC_DIR)/wb-gui-lib/*.sh >/dev/null 2>&1; then \
	  for f in $(SRC_DIR)/wb-gui-lib/*.sh; do \
	    install -Dm644 "$$f" "$(DESTDIR)$(LIBDIR)/wine-bleeding/wb-gui-lib/$$(basename $$f)"; \
	  done; \
	fi
	@for f in $(SRC_DIR)/hooks/*.sh; do \
	  install -Dm755 "$$f" "$(DESTDIR)$(LIBDIR)/wine-bleeding/hooks/$$(basename $$f)"; \
	done
	@# Install the libexec helper (wb-lnk-parse.py) — referenced by wb-gui-detection.sh.
	@if test -d $(RUNTIME_DIR)libexec; then \
	  for f in $(RUNTIME_DIR)libexec/*; do \
	    if test -f "$$f"; then \
	      install -Dm755 "$$f" "$(DESTDIR)$(LIBDIR)/wine-bleeding/libexec/$$(basename $$f)"; \
	    fi; \
	  done; \
	fi
	@# Install the Phase B/C/D tool drivers (build-component.sh, fetch-overlay.sh,
	@# run-winetricks.sh) + their shared helper. Sit under $(LIBDIR)/wine-bleeding/tools/
	@# where wb-gui's resolver picks them up.
	@if test -d $(RUNTIME_DIR)../tools; then \
	  for f in $(RUNTIME_DIR)../tools/build-component.sh \
	           $(RUNTIME_DIR)../tools/fetch-overlay.sh \
	           $(RUNTIME_DIR)../tools/run-winetricks.sh \
	           $(RUNTIME_DIR)../tools/full-build.sh \
	           $(RUNTIME_DIR)../tools/build-full-wine-deps.sh \
	           $(RUNTIME_DIR)../tools/configure-wine-full.sh \
	           $(RUNTIME_DIR)../tools/install-wine-icu.sh \
	           $(RUNTIME_DIR)../tools/install-wine-mono.sh; do \
	    if test -x "$$f" || test -r "$$f"; then \
	      install -Dm755 "$$f" "$(DESTDIR)$(LIBDIR)/wine-bleeding/tools/$$(basename $$f)"; \
	    fi; \
	  done; \
	  if test -f $(RUNTIME_DIR)../tools/lib/build-common.sh; then \
	    install -Dm644 $(RUNTIME_DIR)../tools/lib/build-common.sh \
	      $(DESTDIR)$(LIBDIR)/wine-bleeding/tools/lib/build-common.sh; \
	  fi; \
	  if test -f $(RUNTIME_DIR)../tools/build-glslang.sh; then \
	    install -Dm755 $(RUNTIME_DIR)../tools/build-glslang.sh \
	      $(DESTDIR)$(LIBDIR)/wine-bleeding/tools/build-glslang.sh; \
	  fi; \
	fi
	install -Dm644 $(RUNTIME_DIR)share/defaults.conf \
	  $(DESTDIR)$(SHAREDIR)/wine-bleeding/defaults.conf
	@# Install the distro package map (wb-preflight.py data file — read-only).
	@if test -f $(RUNTIME_DIR)share/wb-preflight-packages.json; then \
	  install -Dm644 $(RUNTIME_DIR)share/wb-preflight-packages.json \
	    $(DESTDIR)$(SHAREDIR)/wine-bleeding/wb-preflight-packages.json; \
	fi
	@# Install the managed build-tools seed manifest (wb-tools-manager.py data file).
	@if test -f $(RUNTIME_DIR)share/wb-tools-manager-manifest.json; then \
	  install -Dm644 $(RUNTIME_DIR)share/wb-tools-manager-manifest.json \
	    $(DESTDIR)$(SHAREDIR)/wine-bleeding/wb-tools-manager-manifest.json; \
	fi
	@for f in $(RUNTIME_DIR)share/schemas/*.json; do \
	  install -Dm644 "$$f" "$(DESTDIR)$(SHAREDIR)/wine-bleeding/schemas/$$(basename $$f)"; \
	done
	@if test -f $(RUNTIME_DIR)share/applications/wine-bleeding-wb.desktop; then \
	  install -Dm644 $(RUNTIME_DIR)share/applications/wine-bleeding-wb.desktop \
	    $(DESTDIR)$(SHAREDIR)/applications/wine-bleeding-wb.desktop; \
	fi
	@# Install every icon size + format present in share/icons/hicolor/.
	@# Small sizes (16..128) are critical for title-bar decorations under KWin/
	@# Plasma; without them Plasma downscales from 256 and sometimes falls
	@# back to a placeholder on transient dialogs.
	@for sub in scalable 16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256 512x512 1024x1024; do \
	  for ext in svg png; do \
	    src=$(RUNTIME_DIR)share/icons/hicolor/$$sub/apps/wine-bleeding.$$ext; \
	    if test -f "$$src"; then \
	      install -Dm644 "$$src" \
	        $(DESTDIR)$(SHAREDIR)/icons/hicolor/$$sub/apps/wine-bleeding.$$ext; \
	    fi; \
	  done; \
	done
	@if test -d $(RUNTIME_DIR)share/compatibilitytools.d/wine-bleeding; then \
	  mkdir -p "$(DESTDIR)$(SHAREDIR)/steam/compatibilitytools.d"; \
	  cp -a $(RUNTIME_DIR)share/compatibilitytools.d/wine-bleeding \
	    $(DESTDIR)$(SHAREDIR)/steam/compatibilitytools.d/wine-bleeding; \
	fi
	install -Dm644 $(RUNTIME_DIR)CHANGELOG.md \
	  $(DESTDIR)$(SHAREDIR)/doc/wine-bleeding/CHANGELOG.md
	install -Dm644 $(RUNTIME_DIR)README.md \
	  $(DESTDIR)$(SHAREDIR)/doc/wine-bleeding/README.md
	@# Install the wine-bleeding-wb-build subpackage README (its sole payload file).
	@# Kept at runtime/ (not runtime/packaging/) so it survives the build.sh tarball
	@# staging which excludes the entire packaging/ tree.
	@if test -f $(RUNTIME_DIR)wine-bleeding-wb-build-README; then \
	  install -Dm644 $(RUNTIME_DIR)wine-bleeding-wb-build-README \
	    $(DESTDIR)$(SHAREDIR)/doc/wine-bleeding-wb-build/README; \
	fi
	@echo "Install complete."

dist-rpm:
	@if ! command -v rpmbuild >/dev/null 2>&1; then \
	  echo "SKIP: rpmbuild not found — install rpm-build to build RPMs"; \
	  exit 0; \
	fi
	@bash $(PACKAGING_DIR)/rpm/build.sh

dist-deb:
	@if ! command -v dpkg-buildpackage >/dev/null 2>&1; then \
	  echo "SKIP: dpkg-buildpackage not found — install dpkg-dev to build DEBs"; \
	  exit 0; \
	fi
	@bash $(PACKAGING_DIR)/deb/build.sh || { \
	  echo "SKIP: dist-deb failed (missing build deps — run on Debian/Ubuntu with debhelper installed)"; \
	  exit 0; \
	}

dist-appimage:
	@bash $(PACKAGING_DIR)/appimage/build-appimage.sh

dist-all: dist-rpm dist-deb dist-appimage

# ---------------------------------------------------------------------------
# Flatpak targets (M14)
# These targets skip gracefully if flatpak-builder is not installed.
# flatpak-builder is NOT required for make test or make lint.
# ---------------------------------------------------------------------------

flatpak-validate:
	@if ! command -v python3 >/dev/null 2>&1; then \
	  echo "SKIP: python3 not found; cannot validate YAML manifest"; \
	  exit 0; \
	fi
	@python3 -c "import yaml; yaml.safe_load(open('$(FLATPAK_MANIFEST)'))" && \
	  echo "YAML OK: $(FLATPAK_MANIFEST)"

flatpak-build:
	@if ! command -v flatpak-builder >/dev/null 2>&1; then \
	  echo "SKIP: flatpak-builder not found on PATH"; \
	  exit 0; \
	fi
	flatpak-builder build-dir "$(FLATPAK_MANIFEST)"
