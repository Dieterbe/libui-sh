all: install

install:
	install -d $(DESTDIR)/usr/lib/
	install -D -m755 lib-ui.sh $(DESTDIR)/usr/lib/libui.sh
uninstall:
	rm -rf  $(DESTDIR)/usr/lib/libui.sh
