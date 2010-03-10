all: install

install:
	install -d $(DESTDIR)/usr/lib/
	install -D -m755 lib-ui.sh $(DESTDIR)/usr/lib/lib-ui.sh
uninstall:
	rm -rf  $(DESTDIR)/usr/lib/lib-ui.sh
