SHELL:=/bin/bash

all:
	@echo "Available targets: update-pflua" && false

update-pflua:
	rm -rf pflua
	git clone https://github.com/Igalia/pflua.git pflua.git
	mv pflua.git/src pflua
	cp pflua.git/{AUTHORS,COPYING,LICENSE} pflua
	rm -rf pflua.git
	git add pflua
