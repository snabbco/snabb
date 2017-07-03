Q= @
E= @echo

# For verbose command line output, uncomment these lines:
#Q=
#E= @:

snabb-lwaftr-doc: doc/snabb-lwaftr.pdf doc/snabb-lwaftr.html doc/snabb-lwaftr.epub

doc/snabb-lwaftr.md:
	(cd doc; ./genbook.sh) > $@

doc/snabb-lwaftr.pdf: doc/snabb-lwaftr.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc -S --toc --chapters -o snabb-lwaftr.pdf snabb-lwaftr.md)

doc/snabb-lwaftr.html: doc/snabb-lwaftr.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc --self-contained --css="../../../doc/style.css" -S -s --toc --chapters -o snabb-lwaftr.html snabb-lwaftr.md)

doc/snabb-lwaftr.epub: doc/snabb-lwaftr.md
	$(E) "PANDOC    $@"
	$(Q) (cd doc; pandoc --self-contained --css="../../../doc/style.css" -S -s --toc --chapters -o snabb-lwaftr.epub snabb-lwaftr.md)

CLEAN = doc/snabb-lwaftr.*

clean_object_files:
	@(find . -name "*.o" -exec echo "RM        {}" \; -exec rm -f {} \;)

clean: clean_object_files
	$(E) "RM        $(CLEAN)"
	$(Q)-rm -rf $(CLEAN)

.PHONY: clean_object_files clean
