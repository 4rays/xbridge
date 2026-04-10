PREFIX ?= $(HOME)/.local/bin

.PHONY: build install uninstall

build:
	swift build -c release

install: build
	install -m 755 .build/release/xhammer $(PREFIX)/xhammer
	install -m 755 .build/release/xhammerd $(PREFIX)/xhammerd

uninstall:
	rm -f $(PREFIX)/xhammer $(PREFIX)/xhammerd
