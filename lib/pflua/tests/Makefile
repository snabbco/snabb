TOP_SRCDIR:=..
include $(TOP_SRCDIR)/common.mk

# Tests where the pure-lua pipeline and/or bpf-lua pipeline diverged from libpcap.
PFLANG_REGRESSION_TESTS := $(wildcard pflang-reg/*)
IR_REGRESSION_TESTS := $(wildcard ir-reg/*.sh)

TEST_SAVEFILE_URL='https://github.com/Igalia/pflua-test/blob/master/savefiles/wingolog.org.pcap?raw=true'
TEST_SAVEFILE=data/wingolog.pcap
PFLUA_QUICKCHECK=$(ABS_TOP_SRCDIR)/tools/pflua-quickcheck

all:
	@true

check:
	$(MAKE) $(TEST_SAVEFILE)
	$(MAKE) regression quickcheck
	./test-matches data
	# Make sure PF_VERBOSE isn't causing crashes
	PF_VERBOSE=1 $(ABS_TOP_SRCDIR)/tools/pflua-compile "ip" >/dev/null 2>&1

$(TEST_SAVEFILE):
	wget --output-document $@ $(TEST_SAVEFILE_URL)

quickcheck:
	$(MAKE) $(TEST_SAVEFILE)
	$(PFLUA_QUICKCHECK) properties/repeatable_randomization
	$(PFLUA_QUICKCHECK) properties/pflua_math_eq_libpcap_math
	$(PFLUA_QUICKCHECK) --iterations=100 properties/pflua_pipelines_match $(TEST_SAVEFILE)
	$(PFLUA_QUICKCHECK) properties/opt_eq_unopt $(TEST_SAVEFILE)
	$(PFLUA_QUICKCHECK) properties/opt_eq_unopt $(TEST_SAVEFILE) test-filters
	$(PFLUA_QUICKCHECK) properties/pipecmp_proto_or_proto $(TEST_SAVEFILE)

regression: pflang_regression_tests ir_regression_tests

ir_regression_tests:
	$(MAKE) $(TEST_SAVEFILE)
	$(MAKE) $(IR_REGRESSION_TESTS)

.PHONY: $(IR_REGRESSION_TESTS)
$(IR_REGRESSION_TESTS):
	./$@

pflang_regression_tests:
	$(MAKE) $(TEST_SAVEFILE)
	$(MAKE) $(PFLANG_REGRESSION_TESTS)

.PHONY: $(PFLANG_REGRESSION_TESTS)
$(PFLANG_REGRESSION_TESTS):
	./$@
.SERIAL: all
