include ../Makefile.config

VERSION=1.28
PRODUCT=$(FAMILY)-rescue

RESCUE = rescue.sqfs

all: $(RESCUE)

install: $(RESCUE)
	install -m644 $< -D $(DESTDIR)$(STAGE2_DEST)/$<

$(RESCUE): list.xml guessmounts rescue-doc make_rescue_img
	DISTRIB_DESCR=$(DISTRIB_DESCR) ./make_rescue_img "$(MKSQUASHFS_ARGS)"

dist-svn:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	mkdir -p $(PRODUCT)-$(VERSION)/tools
	svn export -q -rBASE . $(PRODUCT)-$(VERSION)/rescue
	cp ../Makefile.config $(PRODUCT)-$(VERSION)/
	cp ../tools/install-xml-file-list $(PRODUCT)-$(VERSION)/tools
	cp ../tools/loadkeys $(PRODUCT)-$(VERSION)/tools
	tar cfJ $(PRODUCT)-$(VERSION).tar.xz $(PRODUCT)-$(VERSION)
	rm -rf $(PRODUCT)-$(VERSION)

dist-git:
	@cd ..; git archive --prefix=$(PRODUCT)-$(VERSION)/ HEAD rescue tools/install-xml-file-list Makefile.config | xz >$(PRODUCT)-$(VERSION).tar.xz;

dist: tar

tar:
	rm -rf $(PRODUCT)*.tar* $(PRODUCT)-$(VERSION)
	@if [ -e "../.svn" ]; then \
		$(MAKE) dist-svn; \
	elif [ -e "../.git" ]; then \
		$(MAKE) dist-git; \
	else \
		echo "Unknown SCM (not SVN nor GIT)";\
		exit 1; \
	fi;
	$(info $(PRODUCT)-$(VERSION).tar.xz is ready)

clean: 
	rm -f $(RESCUE) kernel_read_part
