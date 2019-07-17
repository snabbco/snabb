Usage: bench CONF IPV4-IN.PCAP IPV6-IN.PCAP

  -h, --help
                             Print usage information.
  -y, --hydra
                             Hydra mode: emit CSV data in the format expected
                             by the Hydra reports. For instance:

                               benchmark,id,score,unit

                             rather than the default:

                               Time (s),Decap. MPPS,Decap. Gbps,Encap. MPPS,Encap. Gbps
  -b FILENAME, --bench-file FILENAME
                             The file or path name where benchmark data is to
                             be written. A simple filename or relative pathname
                             will be based on the current directory.
  -D DURATION, --duration DURATION
                             Duration in seconds.
  -n NAME, --name NAME       Sets the name for this program, which will be used
                             as the identifier. This must be unique amongst
                             other snabb processes.
  --cpu CPUSET               Run dataplane processes on the given CPUs


Run the lwAFTR with input from IPV4-IN.PCAP and IPV6-IN.PCAP. The bench
command is used to get an idea of the raw speed of the lwaftr without
interaction with NICs, or check the impact of changes on a development
machine that may not have Intel 82599 NICs.  Exit when finished.  This
program is used in the lwAFTR test suite.

CPUSET is a list of CPU ranges.  For example "3-5,7-9", or "3,4,5,7,8,9"
both allow the lwAFTR to run data planes on the given CPUs.

Packets are counted and recorded, and the corresponding incoming and outgoing
packet rates are written to the stdout in CSV format, suitable for passing
to a graphing program. If bench-file is set, output is written to a file
instead of stdout.
