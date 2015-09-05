TOP_SRCDIR:=..
include $(TOP_SRCDIR)/common.mk

all:

clean:

check:
	luajit -l pf.types -e 'pf.types.selftest()'
	luajit -l pf.utils -e 'pf.utils.selftest()'
	luajit -l pf.libpcap -e 'pf.libpcap.selftest()'
	luajit -l pf.bpf -e 'pf.bpf.selftest()'
	luajit -l pf.parse -e 'pf.parse.selftest()'
	luajit -l pf.expand -e 'pf.expand.selftest()'
	luajit -l pf.optimize -e 'pf.optimize.selftest()'
	luajit -l pf.anf -e 'pf.anf.selftest()'
	luajit -l pf.ssa -e 'pf.ssa.selftest()'
	luajit -l pf.backend -e 'pf.backend.selftest()'
	luajit -l pf -e 'pf.selftest()'
