all: install

install:
	install -d $(DESTDIR)/usr/lib/
	install -d $(DESTDIR)/usr/share/libui-sh/docs
	install -D -m644 libui.sh $(DESTDIR)/usr/lib/libui.sh
	install -D -m644 libui-colors.sh $(DESTDIR)/usr/lib/libui-colors.sh
	install -D -m644 README $(DESTDIR)/usr/share/libui-sh/docs
uninstall:
	rm -rf  $(DESTDIR)/usr/lib/libui.sh
	rm -rf  $(DESTDIR)/usr/lib/libui-colors.sh
