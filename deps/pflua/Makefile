PATH := .:../deps/luajit/usr/local/bin:$(PATH)

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
	luajit -l pf.codegen -e 'pf.codegen.selftest()'
	luajit -l pf -e 'pf.selftest()'

test:
	luajit -l bpf_pflua_ts -e 'bpf_pflua_ts.run()'

test_jit_off:
	luajit -joff -l bpf_pflua_ts -e 'bpf_pflua_ts.run()'

trace:
	luajit -jdump -l bpf_pflua_ts -e 'bpf_pflua_ts.run()'
