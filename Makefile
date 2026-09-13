BEND_MAIN ?= ../../bend2-core/bend2/main.ts
BEND = bun $(BEND_MAIN)
BUILD = build

.PHONY: all native web web-js check compare ttf clean
all: $(BUILD)/native $(BUILD)/web $(BUILD)/render

$(BUILD):
	mkdir -p $(BUILD)

LIBS = util.bend xml.bend css.bend bin.bend img.bend png.bend jpeg.bend font.bend cover.bend effs/bytes_read.c effs/bytes_read.js

$(BUILD)/native: native.bend state.bend svg.bend $(LIBS) | $(BUILD)
	CLANG_MODULE_CACHE_PATH=$(CURDIR)/$(BUILD)/clang-cache $(BEND) native.bend -o $@

$(BUILD)/web: web.bend state.bend svg.bend $(LIBS) | $(BUILD)
	CLANG_MODULE_CACHE_PATH=$(CURDIR)/$(BUILD)/clang-cache $(BEND) web.bend -o $@

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
