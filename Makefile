PREFIX ?= $(HOME)/.local/bin

.PHONY: build install uninstall

build:
	swift build -c release

install: build
	mkdir -p $(PREFIX) $(PREFIX)/../share/xbridge
	install -m 644 skills/xbridge/SKILL.md $(PREFIX)/../share/xbridge/xbridge-skill.md
	install -m 755 .build/release/xbridge $(PREFIX)/xbridge
	install -m 755 .build/release/xbridged $(PREFIX)/xbridged
	install -m 755 scripts/allow-xcode-access.applescript $(PREFIX)/xbridge-allow

uninstall:
	rm -f $(PREFIX)/xbridge $(PREFIX)/xbridged $(PREFIX)/xbridge-allow
	rm -f $(PREFIX)/../share/xbridge/xbridge-skill.md
