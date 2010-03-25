all: install

install:
	install -d $(DESTDIR)/usr/lib/
	install -D -m644 libui.sh $(DESTDIR)/usr/lib/libui.sh
uninstall:
	rm -rf  $(DESTDIR)/usr/lib/libui.sh
