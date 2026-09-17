BEND_MAIN ?= ../bend2-core/bend2/main.ts
BEND = bun $(BEND_MAIN)
BUILD = build
CC = clang

.PHONY: all native web web-js check check-frames check-inspector check-resize compare ttf clean
all: $(BUILD)/native $(BUILD)/web $(BUILD)/render

$(BUILD):
	mkdir -p $(BUILD)

LIBS = util.bend xml.bend css.bend bin.bend img.bend png.bend jpeg.bend font.bend cover.bend effs/bytes_read.c effs/bytes_read.js

$(BUILD)/native: native.bend inspect.bend effs/inspector_step.c effs/canvas.c state.bend svg.bend $(LIBS) | $(BUILD)
	$(BEND) native.bend -o $@.c
	CLANG_MODULE_CACHE_PATH=$(CURDIR)/$(BUILD)/clang-cache $(CC) -DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules -std=c11 -O3 $@.c -lpthread -lm -o $@

$(BUILD)/web: web.bend inspect.bend state.bend svg.bend effs/frame_send.c $(LIBS) | $(BUILD)
	$(BEND) web.bend -o $@.c
	$(CC) -std=c11 -O3 $@.c -lpthread -lm -lz -o $@

$(BUILD)/render: render.bend state.bend svg.bend $(LIBS) | $(BUILD)
	CLANG_MODULE_CACHE_PATH=$(CURDIR)/$(BUILD)/clang-cache $(BEND) render.bend -o $@

native: $(BUILD)/native
	./$(BUILD)/native --gpu off

web: $(BUILD)/web
	./$(BUILD)/web --gpu off

web-js:
	$(BEND) web.bend

check:
	BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/check.mjs

check-frames:
	BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/frame-transport.mjs
	BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/frame-browser.mjs

check-inspector: $(BUILD)/web
	SVG_SERVER_BACKEND=javascript BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/run-browser-inspector.mjs
	SVG_SERVER_BACKEND=native BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/run-browser-inspector.mjs
	BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/run-native-inspector.mjs

check-resize: $(BUILD)/web
	SVG_SERVER_BACKEND=javascript SVG_BROWSER_TEST=browser-resize.mjs BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/run-browser-camera.mjs
	SVG_SERVER_BACKEND=native SVG_BROWSER_TEST=browser-resize.mjs BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/run-browser-camera.mjs
	BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/run-native-inspector.mjs

compare:
	cd validation && bun install --frozen-lockfile && bunx playwright install chromium firefox
	BEND_MAIN=$(abspath $(BEND_MAIN)) bun validation/compare.mjs
	bun validation/compare-browser.mjs
	bun validation/compare-convolve-firefox.mjs
	bun validation/verify.mjs

ttf: $(BUILD)/render
	bun validation/ttf-parity.mjs

clean:
	rm -rf $(BUILD)
