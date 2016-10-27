Q= @
E= @echo

snabbvmx-doc: doc/snabbvmx.pdf doc/snabbvmx.html doc/snabbvmx.epub

doc/snabbvmx.md:
	(cd doc; ./genbook.sh) > $@

doc/snabbvmx.pdf: doc/snabbvmx.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc -S --toc --chapters -o snabbvmx.pdf snabbvmx.md)

doc/snabbvmx.html: doc/snabbvmx.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc --self-contained --css="../../../doc/style.css" -S -s --toc --chapters -o snabbvmx.html snabbvmx.md)

doc/snabbvmx.epub: doc/snabbvmx.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc --self-contained --css="../../../doc/style.css" -S -s --toc --chapters -o snabbvmx.epub snabbvmx.md)

CLEAN = doc/snabbvmx.*

clean:
	$(E) "RM        $(CLEAN)"
	$(Q)-rm -rf $(CLEAN)
	$(Q) (cd ../../; make clean)

.PHONY: clean
