# Android build through pixiewood. Meant to run inside the
# cassette-android-build image (build-aux/android/Dockerfile):
#
#   make -f build-aux/android/android.mk android release=1
#
# Outside the container set PIXIEWOOD / ANDROID_STUDIO / ANDROID_SDK.
# Pattern: Matras build-aux/android/android.mk and the Makefile of GeopJr/Tuba.

ANDROID_SDK    ?= $(ANDROID_HOME)
ANDROID_NDK    ?=
ANDROID_STUDIO ?= /work/mini-studio
PIXIEWOOD      ?= /work/pixiewood/pixiewood
release        ?=

AUX          := build-aux/android
MANIFEST     := $(AUX)/space.rirusha.Cassette.xml
PROJECT      := .pixiewood/android
APK_DIR      := $(PROJECT)/app/build/outputs/apk/$(if $(release),release,debug)

.PHONY: android android-blueprints android-subprojects android-prepare android-patch-gtk android-generate android-patch android-build android-sign android-clean

android: android-subprojects android-prepare android-patch-gtk android-generate android-patch android-build

# blueprint-compiler validates against the host's Gtk/Adw typelibs, so the .blp
# files are compiled wherever those are new enough (the host, not the build
# container) and data/meson.build copies the result on Android.
android-blueprints:
	rm -rf $(AUX)/ui
	blueprint-compiler batch-compile $(AUX)/ui data data/ui/*.blp

# Wraps for what pixiewood does not carry itself (libsoup, openssl, json-glib,
# libgee, sqlite3 ...). Copied, not moved: subprojects/ may hold other work.
android-subprojects:
	mkdir -p subprojects/packagefiles
	cp $(AUX)/subprojects/*.wrap subprojects/
	cp $(AUX)/subprojects/packagefiles/* subprojects/packagefiles/

# ANDROID_NDK pins the toolchain; otherwise pixiewood takes the newest under $(ANDROID_SDK)/ndk.
android-prepare:
	$(PIXIEWOOD) prepare $(if $(release),--release,) \
		--sdk=$(ANDROID_SDK) $(if $(ANDROID_NDK),--toolchain=$(ANDROID_NDK),) \
		--android-studio=$(ANDROID_STUDIO) $(MANIFEST)

# Our patches on top of the GTK checkout pixiewood made (subprojects/gtk):
# the Java glue paints the areas under the system bars with colours the app
# provides (gtk_bars_top / gtk_bars_bottom), instead of a hard-coded grey.
# Idempotent: skipped when already applied.
android-patch-gtk:
	@for p in $(AUX)/patches/gtk-*.patch; do \
		if git -C subprojects/gtk apply --reverse --check "$(CURDIR)/$$p" 2>/dev/null; then echo "$$p: already applied"; \
		elif git -C subprojects/gtk apply "$(CURDIR)/$$p"; then echo "$$p: applied"; \
		else echo "$$p: FAILED to apply"; exit 1; fi; \
	done

android-generate:
	$(PIXIEWOOD) generate

# Permissions, application class, service, auth activity and our Java
# sources: none of it has a hook in pixiewood, so the generated project is
# patched in place. `build` does not regenerate it.
android-patch:
	python3 $(AUX)/patch-android-project.py $(PROJECT) $(AUX)

android-build:
	$(PIXIEWOOD) build
	@ls -la $(APK_DIR)/

# pixiewood does not sign. ANDROID_KEYSTORE_LOCATION / ANDROID_KEYSTORE_KEY
# come from the environment.
android-sign:
	mkdir -p apks/
	@for apk in $(APK_DIR)/*.apk; do \
		apksigner sign --ks "$(ANDROID_KEYSTORE_LOCATION)" --ks-pass "env:ANDROID_KEYSTORE_KEY" \
			--in "$$apk" --out "apks/$$(basename "$$apk" | sed 's/-unsigned//')"; \
	done
	@ls -la apks/

android-clean:
	rm -rf .pixiewood
