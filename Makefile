# Makefile — build helpers for Snappy Nest.
#
# Everyday flow:
#   make build         # swift build (debug)
#   make test          # swift test
#   make run           # build + wrap + run in place (leaves stderr on your terminal)
#   make install       # ./Install/install.sh
#   make uninstall     # ./Install/uninstall.sh
#
# Distribution (requires an Apple Developer ID Application cert):
#   make dmg SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   make notarize DMG=dist/TouchbarPet-<ver>.dmg \\
#       ASC_API_KEY_ID=... ASC_API_KEY_ISSUER_ID=... ASC_API_KEY_PATH=...
#
# NOTE: signed distribution requires Apple Developer Program membership. Local
# `install` builds unsigned .app bundles — right-click → Open on first launch
# to bypass Gatekeeper.

VERSION := 0.1.0
STAGE   := build/stage
DIST    := dist

.PHONY: build test run install uninstall clean dmg notarize

build:
	swift build --product TouchbarPet

test:
	swift test

run: build
	./Install/wrap-as-app.sh .build/debug/TouchbarPet com.local.snappy-nest $(STAGE) TouchbarPet > /dev/null
	$(STAGE)/TouchbarPet.app/Contents/MacOS/TouchbarPet

install:
	./Install/install.sh

uninstall:
	./Install/uninstall.sh

clean:
	rm -rf .build $(STAGE) $(DIST)

# ---- dmg + notarize -------------------------------------------------------

dmg: build
	@if [ -z "$${SIGNING_IDENTITY:-}" ]; then \
		echo "error: SIGNING_IDENTITY must be set" >&2 ; exit 1 ; \
	fi
	mkdir -p $(STAGE) $(DIST)
	./Install/wrap-as-app.sh .build/debug/TouchbarPet com.local.snappy-nest $(STAGE) TouchbarPet > /dev/null
	codesign --deep --force --options runtime \
		--sign "$${SIGNING_IDENTITY}" \
		$(STAGE)/TouchbarPet.app
	rm -f $(DIST)/TouchbarPet-$(VERSION).dmg
	hdiutil create -srcfolder $(STAGE)/TouchbarPet.app \
		-volname "Snappy Nest $(VERSION)" \
		-format UDZO \
		$(DIST)/TouchbarPet-$(VERSION).dmg
	@echo "==> $(DIST)/TouchbarPet-$(VERSION).dmg"

notarize:
	@if [ -z "$${DMG:-}" ]; then echo "usage: make notarize DMG=path/to.dmg ..." >&2; exit 1; fi
	xcrun notarytool submit "$${DMG}" \
		--key "$${ASC_API_KEY_PATH}" \
		--key-id "$${ASC_API_KEY_ID}" \
		--issuer "$${ASC_API_KEY_ISSUER_ID}" \
		--wait
	xcrun stapler staple "$${DMG}"
