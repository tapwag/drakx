BOOT_IMG = mdkinst_hd.img mdkinst_cdrom.img mdkinst_network.img mdkinst_network_ks.img
BINS = install/install install/local-install install/installinit/init



.PHONY: $(BOOT_IMG) $(FLOPPY_IMG) $(BINS) update_kernel

all: $(BOOT_IMG)
	mkdir /export/images 2>/dev/null ; true
	cp -f $(BOOT_IMG) /export/images

clean:
	rm -rf $(BOOT_IMG) $(BINS) modules vmlinuz

$(BOOT_IMG): $(BINS)
	if [ ! -e modules ]; then $(MAKE) update_kernel; fi
	./make_boot_img $@ $(@:mdkinst_%.img=%)

$(BINS):
	$(MAKE) -C `dirname $@`


update_kernel:
	./update_kernel

$(BOOT_IMG:%=%f): %f: %
	dd if=$< of=/dev/fd0
	xmessage "Floppy done"

# mkisofs -R -b images/mdkinst_cdrom.img -c images/b /tmp/r /mnt/disk/ | cdrecord -v -eject speed=6 dev=1,0 -