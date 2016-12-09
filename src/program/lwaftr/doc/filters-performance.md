# LwAFTR ingress/egress filters and performance

## Summarized results

Having filters, even if they are empty, has a significant negative impact on performance. 

Here are the results for three runs with empty filters:

* No packet loss below 7 Gbps
* Packet loss at 8 Gbps on cooldown on two of the three runs (4.3% and 3.9%).
* Packet loss at 9 Gbps on all three runs (warmup: 0.13%, 14.6%, 14.2%; cooldowns marginally worse)
* Heavy packet loss at 10 Gbps: (10.4-10.6%, 23.2-23.6%, 22.9-23.2%)

Results appear to be approximately the same with one filter. Scaling it up to 800 filters, results are a bit worse; packet loss starts at 7 Gbps, and peak packet loss at 10 Gbps is around 34%.

The load that was applied was 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 Gbps, on each of two interfaces at the same time; the total traffic going into the lwaftr was twice as high, due to their being two (equally loaded) interfaces. The latter half of the load, after it peaks at 10 Gbps per card, is referred to as "cooldown".

## Future improvements

The nature of packet loss with empty filters suggests that the overhead of adding four extra apps to the Snabb app network (one per filter option in the config file) is the critical problem. We could integrate the filters into the lwaftr app itself to side-step this. Alternatively, on an "on-a-stick" configuration that only uses one rather than two cards, the overhead might be small enough to still not matter, even with 800 filters; there was no packet loss (except on cooldown) even with 800 filters at 5 Gbps or 6 Gbps per interface with two interfaces.

# Details of the results and configuration

Setup: bidirectional lwaftr on snabb1, load generation on snabb2. Using Snabb revision 79504183e1acb5673f7eda9d788885ff8c076f39 (lwaftr_starfruit branch, Igalia fork)

## Running the lwaftr (with taskset and numactl)

```
$ cat ~/bin/run-lwaftr

#!/bin/sh
BASEDIR=/home/kbarone/snabbswitch/src/
CONF="`realpath $1`"
cd ${BASEDIR} && sudo numactl -m 0 taskset -c 1 ./snabb lwaftr run --conf ${CONF} --v4-pci 0000:02:00.0 --v6-pci 0000:02:00.1
```

## Load generation

``` 
$ cat run-loadtest 

#!/bin/sh
BASEDIR=/home/kbarone/snabbswitch/src
PCAP4=${BASEDIR}/program/lwaftr/tests/benchdata/ipv4-0550.pcap
PCAP6=${BASEDIR}/program/lwaftr/tests/benchdata/ipv6-0550.pcap
cd ${BASEDIR} && sudo numactl -m 0 taskset -c 1 ./snabb lwaftr loadtest \
  ${PCAP4} v4 v4 0000:02:00.0 \
  ${PCAP6} v6 v6 0000:02:00.1
```

## Binding table

```$ cat binding-table.txt```

```
psid_map {
  178.79.150.1 {psid_length=0}
  178.79.150.2 {psid_length=16}
  178.79.150.3 {psid_length=6}
  178.79.150.15 {psid_length=4, shift=12}
  178.79.150.233 {psid_length=16}
}
br_addresses {
  8:9:a:b:c:d:e:f,
  1E:1:1:1:1:1:1:af,
  1E:2:2:2:2:2:2:af
}
softwires {
  { ipv4=178.79.150.1, b4=127:10:20:30:40:50:60:128 }
  { ipv4=178.79.150.2, psid=7850, b4=127:24:35:46:57:68:79:128, aftr=1 }
  { ipv4=178.79.150.3, psid=4, b4=127:14:25:36:47:58:69:128, aftr=2 }
  { ipv4=178.79.150.15, psid=0, b4=127:22:33:44:55:66:77:128 }
  { ipv4=178.79.150.15, psid=1, b4=127:22:33:44:55:66:77:128 }
  { ipv4=178.79.150.233, psid=80, b4=127:2:3:4:5:6:7:128, aftr=0 }
  { ipv4=178.79.150.233, psid=2300, b4=127:11:12:13:14:15:16:128 }
  { ipv4=178.79.150.233, psid=2700, b4=127:11:12:13:14:15:16:128 }
  { ipv4=178.79.150.233, psid=4660, b4=127:11:12:13:14:15:16:128 }
  { ipv4=178.79.150.233, psid=7850, b4=127:11:12:13:14:15:16:128 }
  { ipv4=178.79.150.233, psid=22788, b4=127:11:12:13:14:15:16:128 }
  { ipv4=178.79.150.233, psid=54192, b4=127:11:12:13:14:15:16:128 }
}
```

# Results

## Baseline (no filters), _run-lwaftr no_filters.conf_

There is only loss at 10 Gbps, and it is only what is logically expected when packets from a saturated link are made larger; with 550 byte packets, it is 6.5%.

This was run three times to verify consistency. All the results were essentially the same; a snippet of the first is below.

```
Applying 9.000000 Gbps of load.
  v4:
    TX 9799649 packets (1.959930 MPPS), 5389806950 bytes (8.999998 Gbps)
    RX 9799649 packets (1.959930 MPPS), 4997820990 bytes (8.372820 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 9799649 packets (1.959930 MPPS), 5389806950 bytes (8.999998 Gbps)
    RX 9799649 packets (1.959930 MPPS), 5781792910 bytes (9.627175 Gbps)
    Loss: 0 packets (0.000000%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888498 packets (2.177700 MPPS), 5988673900 bytes (9.999997 Gbps)
    RX 10888376 packets (2.177675 MPPS), 5553071760 bytes (9.303028 Gbps)
    Loss: 122 packets (0.001120%)
  v6:
    TX 10888498 packets (2.177700 MPPS), 5988673900 bytes (9.999997 Gbps)
    RX 10180061 packets (2.036012 MPPS), 6006235990 bytes (10.000892 Gbps)
    Loss: 708437 packets (6.506288%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888496 packets (2.177699 MPPS), 5988672800 bytes (9.999995 Gbps)
    RX 10888496 packets (2.177699 MPPS), 5553132960 bytes (9.303131 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 10888496 packets (2.177699 MPPS), 5988672800 bytes (9.999995 Gbps)
    RX 10180060 packets (2.036012 MPPS), 6006235400 bytes (10.000891 Gbps)
    Loss: 708436 packets (6.506280%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799647 packets (1.959929 MPPS), 5389805850 bytes (8.999996 Gbps)
    RX 9799647 packets (1.959929 MPPS), 4997819970 bytes (8.372818 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 9799647 packets (1.959929 MPPS), 5389805850 bytes (8.999996 Gbps)
    RX 9799647 packets (1.959929 MPPS), 5781791730 bytes (9.627173 Gbps)
    Loss: 0 packets (0.000000%)
```

## Empty filters, _run-lwaftr empty_filters.conf_

As above, but with the following added to the configuration file:

```
ipv4_ingress_filter = "",
ipv4_egress_filter = "", 
ipv6_ingress_filter = "",
ipv6_egress_filter = "" ,
```

### Results with empty filters

* No packet loss below 7 Gbps
* Packet loss at 8 Gbps on cooldown on two of the three runs (4.3% and 3.9%).
* Packet loss at 9 Gbps on all three runs (warmup: 0.13%,  14.6%, 14.2%; cooldowns marginally worse)
* Heavy packet loss at 10 Gbps: (10.4-10.6%, 23.2-23.6%, 22.9-23.2%)

Results tentatively appear similar whether the empty filters are specified directly or in a file.

### Empty filters, Run 1

```
Applying 8.000000 Gbps of load.
  v4:
    TX 8710795 packets (1.742159 MPPS), 4790937250 bytes (7.999994 Gbps)
    RX 8710795 packets (1.742159 MPPS), 4442505450 bytes (7.442503 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 8710795 packets (1.742159 MPPS), 4790937250 bytes (7.999994 Gbps)
    RX 8710795 packets (1.742159 MPPS), 5139369050 bytes (8.557485 Gbps)
    Loss: 0 packets (0.000000%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799639 packets (1.959928 MPPS), 5389801450 bytes (8.999988 Gbps)
    RX 9786866 packets (1.957373 MPPS), 4991301660 bytes (8.361898 Gbps)
    Loss: 12773 packets (0.130342%)
  v6:
    TX 9799639 packets (1.959928 MPPS), 5389801450 bytes (8.999988 Gbps)
    RX 9786864 packets (1.957373 MPPS), 5774249760 bytes (9.614615 Gbps)
    Loss: 12775 packets (0.130362%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888492 packets (2.177698 MPPS), 5988670600 bytes (9.999991 Gbps)
    RX 9736284 packets (1.947257 MPPS), 4965504840 bytes (8.318681 Gbps)
    Loss: 1152208 packets (10.581888%)
  v6:
    TX 10888492 packets (2.177698 MPPS), 5988670600 bytes (9.999991 Gbps)
    RX 9736283 packets (1.947257 MPPS), 5744406970 bytes (9.564924 Gbps)
    Loss: 1152209 packets (10.581897%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888488 packets (2.177698 MPPS), 5988668400 bytes (9.999987 Gbps)
    RX 9757146 packets (1.951429 MPPS), 4976144460 bytes (8.336506 Gbps)
    Loss: 1131342 packets (10.390258%)
  v6:
    TX 10888488 packets (2.177698 MPPS), 5988668400 bytes (9.999987 Gbps)
    RX 9757156 packets (1.951431 MPPS), 5756722040 bytes (9.585430 Gbps)
    Loss: 1131332 packets (10.390166%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799651 packets (1.959930 MPPS), 5389808050 bytes (8.999999 Gbps)
    RX 9739134 packets (1.947827 MPPS), 4966958340 bytes (8.321116 Gbps)
    Loss: 60517 packets (0.617542%)
  v6:
    TX 9799651 packets (1.959930 MPPS), 5389808050 bytes (8.999999 Gbps)
    RX 9739134 packets (1.947827 MPPS), 5746089060 bytes (9.567725 Gbps)
    Loss: 60517 packets (0.617542%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710791 packets (1.742158 MPPS), 4790935050 bytes (7.999990 Gbps)
    RX 8710791 packets (1.742158 MPPS), 4442503410 bytes (7.442500 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 8710791 packets (1.742158 MPPS), 4790935050 bytes (7.999990 Gbps)
    RX 8710791 packets (1.742158 MPPS), 5139366690 bytes (8.557481 Gbps)
    Loss: 0 packets (0.000000%)
```

### Empty filters, Run 2

```
Applying 8.000000 Gbps of load.
  v4:
    TX 8710801 packets (1.742160 MPPS), 4790940550 bytes (8.000000 Gbps)
    RX 8710801 packets (1.742160 MPPS), 4442508510 bytes (7.442508 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 8710801 packets (1.742160 MPPS), 4790940550 bytes (8.000000 Gbps)
    RX 8710801 packets (1.742160 MPPS), 5139372590 bytes (8.557491 Gbps)
    Loss: 0 packets (0.000000%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799644 packets (1.959929 MPPS), 5389804200 bytes (8.999993 Gbps)
    RX 8372982 packets (1.674596 MPPS), 4270220820 bytes (7.153876 Gbps)
    Loss: 1426662 packets (14.558304%)
  v6:
    TX 9799644 packets (1.959929 MPPS), 5389804200 bytes (8.999993 Gbps)
    RX 8372985 packets (1.674597 MPPS), 4940061150 bytes (8.225620 Gbps)
    Loss: 1426659 packets (14.558274%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888488 packets (2.177698 MPPS), 5988668400 bytes (9.999987 Gbps)
    RX 8352095 packets (1.670419 MPPS), 4259568450 bytes (7.136030 Gbps)
    Loss: 2536393 packets (23.294263%)
  v6:
    TX 10888488 packets (2.177698 MPPS), 5988668400 bytes (9.999987 Gbps)
    RX 8352096 packets (1.670419 MPPS), 4927736640 bytes (8.205099 Gbps)
    Loss: 2536392 packets (23.294254%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888496 packets (2.177699 MPPS), 5988672800 bytes (9.999995 Gbps)
    RX 8316303 packets (1.663261 MPPS), 4241314530 bytes (7.105449 Gbps)
    Loss: 2572193 packets (23.623033%)
  v6:
    TX 10888496 packets (2.177699 MPPS), 5988672800 bytes (9.999995 Gbps)
    RX 8316371 packets (1.663274 MPPS), 4906658890 bytes (8.170003 Gbps)
    Loss: 2572125 packets (23.622408%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799647 packets (1.959929 MPPS), 5389805850 bytes (8.999996 Gbps)
    RX 8355548 packets (1.671110 MPPS), 4261329480 bytes (7.138980 Gbps)
    Loss: 1444099 packets (14.736235%)
  v6:
    TX 9799647 packets (1.959929 MPPS), 5389805850 bytes (8.999996 Gbps)
    RX 8355559 packets (1.671112 MPPS), 4929779810 bytes (8.208501 Gbps)
    Loss: 1444088 packets (14.736123%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710796 packets (1.742159 MPPS), 4790937800 bytes (7.999995 Gbps)
    RX 8334860 packets (1.666972 MPPS), 4250778600 bytes (7.121304 Gbps)
    Loss: 375936 packets (4.315748%)
  v6:
    TX 8710796 packets (1.742159 MPPS), 4790937800 bytes (7.999995 Gbps)
    RX 8334862 packets (1.666972 MPPS), 4917568580 bytes (8.188168 Gbps)
    Loss: 375934 packets (4.315725%)
Applying 7.000000 Gbps of load.
  v4:
    TX 7621951 packets (1.524390 MPPS), 4192073050 bytes (7.000000 Gbps)
    RX 7621951 packets (1.524390 MPPS), 3887195010 bytes (6.512195 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 7621951 packets (1.524390 MPPS), 4192073050 bytes (7.000000 Gbps)
    RX 7621951 packets (1.524390 MPPS), 4496951090 bytes (7.487805 Gbps)
    Loss: 0 packets (0.000000%)
```

### Empty filters, Run 3

```
Applying 8.000000 Gbps of load.
  v4:
    TX 8710798 packets (1.742160 MPPS), 4790938900 bytes (7.999997 Gbps)
    RX 8710798 packets (1.742160 MPPS), 4442506980 bytes (7.442506 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 8710798 packets (1.742160 MPPS), 4790938900 bytes (7.999997 Gbps)
    RX 8710798 packets (1.742160 MPPS), 5139370820 bytes (8.557488 Gbps)
    Loss: 0 packets (0.000000%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799648 packets (1.959930 MPPS), 5389806400 bytes (8.999997 Gbps)
    RX 8409152 packets (1.681830 MPPS), 4288667520 bytes (7.184779 Gbps)
    Loss: 1390496 packets (14.189244%)
  v6:
    TX 9799648 packets (1.959930 MPPS), 5389806400 bytes (8.999997 Gbps)
    RX 8409155 packets (1.681831 MPPS), 4961401450 bytes (8.261154 Gbps)
    Loss: 1390493 packets (14.189214%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888497 packets (2.177699 MPPS), 5988673350 bytes (9.999996 Gbps)
    RX 8360883 packets (1.672177 MPPS), 4264050330 bytes (7.143538 Gbps)
    Loss: 2527614 packets (23.213617%)
  v6:
    TX 10888497 packets (2.177699 MPPS), 5988673350 bytes (9.999996 Gbps)
    RX 8360888 packets (1.672178 MPPS), 4932923920 bytes (8.213736 Gbps)
    Loss: 2527609 packets (23.213571%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888499 packets (2.177700 MPPS), 5988674450 bytes (9.999997 Gbps)
    RX 8396207 packets (1.679241 MPPS), 4282065570 bytes (7.173719 Gbps)
    Loss: 2492292 packets (22.889215%)
  v6:
    TX 10888499 packets (2.177700 MPPS), 5988674450 bytes (9.999997 Gbps)
    RX 8396208 packets (1.679242 MPPS), 4953762720 bytes (8.248435 Gbps)
    Loss: 2492291 packets (22.889206%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799652 packets (1.959930 MPPS), 5389808600 bytes (9.000000 Gbps)
    RX 8399378 packets (1.679876 MPPS), 4283682780 bytes (7.176429 Gbps)
    Loss: 1400274 packets (14.289018%)
  v6:
    TX 9799652 packets (1.959930 MPPS), 5389808600 bytes (9.000000 Gbps)
    RX 8399384 packets (1.679877 MPPS), 4955636560 bytes (8.251555 Gbps)
    Loss: 1400268 packets (14.288956%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710800 packets (1.742160 MPPS), 4790940000 bytes (7.999999 Gbps)
    RX 8369042 packets (1.673808 MPPS), 4268211420 bytes (7.150509 Gbps)
    Loss: 341758 packets (3.923382%)
  v6:
    TX 8710800 packets (1.742160 MPPS), 4790940000 bytes (7.999999 Gbps)
    RX 8369045 packets (1.673809 MPPS), 4937736550 bytes (8.221750 Gbps)
    Loss: 341755 packets (3.923348%)
Applying 7.000000 Gbps of load.
  v4:
    TX 7621951 packets (1.524390 MPPS), 4192073050 bytes (7.000000 Gbps)
    RX 7621951 packets (1.524390 MPPS), 3887195010 bytes (6.512195 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 7621951 packets (1.524390 MPPS), 4192073050 bytes (7.000000 Gbps)
    RX 7621951 packets (1.524390 MPPS), 4496951090 bytes (7.487805 Gbps)
    Loss: 0 packets (0.000000%)
```

### Running empty filters from a file, _run-lwaftr empty_filters_fromfile.conf_

```
$ touch empty.pf

Edit the config file to contain:

ipv4_ingress_filter = <empty.pf,
ipv4_egress_filter = <empty.pf, 
ipv6_ingress_filter = <empty.pf,
ipv6_egress_filter = <empty.pf,
```

```
Applying 8.000000 Gbps of load.
  v4:
    TX 8710797 packets (1.742159 MPPS), 4790938350 bytes (7.999996 Gbps)
    RX 8710797 packets (1.742159 MPPS), 4442506470 bytes (7.442505 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 8710797 packets (1.742159 MPPS), 4790938350 bytes (7.999996 Gbps)
    RX 8710797 packets (1.742159 MPPS), 5139370230 bytes (8.557487 Gbps)
    Loss: 0 packets (0.000000%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799640 packets (1.959928 MPPS), 5389802000 bytes (8.999989 Gbps)
    RX 9654188 packets (1.930838 MPPS), 4923635880 bytes (8.248538 Gbps)
    Loss: 145452 packets (1.484259%)
  v6:
    TX 9799640 packets (1.959928 MPPS), 5389802000 bytes (8.999989 Gbps)
    RX 9654189 packets (1.930838 MPPS), 5695971510 bytes (9.484275 Gbps)
    Loss: 145451 packets (1.484248%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888497 packets (2.177699 MPPS), 5988673350 bytes (9.999996 Gbps)
    RX 9709827 packets (1.941965 MPPS), 4952011770 bytes (8.296076 Gbps)
    Loss: 1178670 packets (10.824910%)
  v6:
    TX 10888497 packets (2.177699 MPPS), 5988673350 bytes (9.999996 Gbps)
    RX 9709838 packets (1.941968 MPPS), 5728804420 bytes (9.538945 Gbps)
    Loss: 1178659 packets (10.824809%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888501 packets (2.177700 MPPS), 5988675550 bytes (9.999999 Gbps)
    RX 9690865 packets (1.938173 MPPS), 4942341150 bytes (8.279875 Gbps)
    Loss: 1197636 packets (10.999090%)
  v6:
    TX 10888501 packets (2.177700 MPPS), 5988675550 bytes (9.999999 Gbps)
    RX 9690859 packets (1.938172 MPPS), 5717606810 bytes (9.520300 Gbps)
    Loss: 1197642 packets (10.999145%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799641 packets (1.959928 MPPS), 5389802550 bytes (8.999990 Gbps)
    RX 9666026 packets (1.933205 MPPS), 4929673260 bytes (8.258653 Gbps)
    Loss: 133615 packets (1.363468%)
  v6:
    TX 9799641 packets (1.959928 MPPS), 5389802550 bytes (8.999990 Gbps)
    RX 9666031 packets (1.933206 MPPS), 5702958290 bytes (9.495909 Gbps)
    Loss: 133610 packets (1.363417%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710799 packets (1.742160 MPPS), 4790939450 bytes (7.999998 Gbps)
    RX 8688293 packets (1.737659 MPPS), 4431029430 bytes (7.423278 Gbps)
    Loss: 22506 packets (0.258369%)
  v6:
    TX 8710799 packets (1.742160 MPPS), 4790939450 bytes (7.999998 Gbps)
    RX 8688290 packets (1.737658 MPPS), 5126091100 bytes (8.535376 Gbps)
    Loss: 22509 packets (0.258403%)
Applying 7.000000 Gbps of load.
  v4:
    TX 7621950 packets (1.524390 MPPS), 4192072500 bytes (6.999999 Gbps)
    RX 7621950 packets (1.524390 MPPS), 3887194500 bytes (6.512194 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 7621950 packets (1.524390 MPPS), 4192072500 bytes (6.999999 Gbps)
    RX 7621950 packets (1.524390 MPPS), 4496950500 bytes (7.487804 Gbps)
    Loss: 0 packets (0.000000%)
```

### One filter per option (4 total), _run-lwaftr single_filters.conf_

The results on one run were similar to with empty filters - actually, slightly better than the best empty filter run, though that is almost certainly noise.

Summary: ramp-up 9 Gbps had 0.6% packet loss, 10 Gpbs had 9.4-9.5% packet loss, cooldown 9 Gbps had 0.03% packet loss, cooldown 8 Gbps had 0.2% packet loss.
That is not a typo; there was ~10 times as much packet loss at 8 Gbps than at 9 Gbps on the cooldown.

Changes to the configuration file:
```
ipv4_ingress_filter = "not src host 192.168.255.0",
ipv4_egress_filter = "not src host 192.168.255.0", 
ipv6_ingress_filter = "not src host 1::ff11",
ipv6_egress_filter = "not src host 1::ff11",
```

```

Applying 8.000000 Gbps of load.
  v4:
    TX 8710801 packets (1.742160 MPPS), 4790940550 bytes (8.000000 Gbps)
    RX 8710801 packets (1.742160 MPPS), 4442508510 bytes (7.442508 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 8710801 packets (1.742160 MPPS), 4790940550 bytes (8.000000 Gbps)
    RX 8710801 packets (1.742160 MPPS), 5139372590 bytes (8.557491 Gbps)
    Loss: 0 packets (0.000000%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799648 packets (1.959930 MPPS), 5389806400 bytes (8.999997 Gbps)
    RX 9741216 packets (1.948243 MPPS), 4968020160 bytes (8.322895 Gbps)
    Loss: 58432 packets (0.596266%)
  v6:
    TX 9799648 packets (1.959930 MPPS), 5389806400 bytes (8.999997 Gbps)
    RX 9741220 packets (1.948244 MPPS), 5747319800 bytes (9.569775 Gbps)
    Loss: 58428 packets (0.596225%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888497 packets (2.177699 MPPS), 5988673350 bytes (9.999996 Gbps)
    RX 9860676 packets (1.972135 MPPS), 5028944760 bytes (8.424962 Gbps)
    Loss: 1027821 packets (9.439512%)
  v6:
    TX 10888497 packets (2.177699 MPPS), 5988673350 bytes (9.999996 Gbps)
    RX 9860679 packets (1.972136 MPPS), 5817800610 bytes (9.687131 Gbps)
    Loss: 1027818 packets (9.439485%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888499 packets (2.177700 MPPS), 5988674450 bytes (9.999997 Gbps)
    RX 9855052 packets (1.971010 MPPS), 5026076520 bytes (8.420156 Gbps)
    Loss: 1033447 packets (9.491180%)
  v6:
    TX 10888499 packets (2.177700 MPPS), 5988674450 bytes (9.999997 Gbps)
    RX 9855050 packets (1.971010 MPPS), 5814479500 bytes (9.681601 Gbps)
    Loss: 1033449 packets (9.491198%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799649 packets (1.959930 MPPS), 5389806950 bytes (8.999998 Gbps)
    RX 9796323 packets (1.959265 MPPS), 4996124730 bytes (8.369978 Gbps)
    Loss: 3326 packets (0.033940%)
  v6:
    TX 9799649 packets (1.959930 MPPS), 5389806950 bytes (8.999998 Gbps)
    RX 9796320 packets (1.959264 MPPS), 5779828800 bytes (9.623905 Gbps)
    Loss: 3329 packets (0.033971%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710802 packets (1.742160 MPPS), 4790941100 bytes (8.000001 Gbps)
    RX 8691281 packets (1.738256 MPPS), 4432553310 bytes (7.425830 Gbps)
    Loss: 19521 packets (0.224101%)
  v6:
    TX 8710802 packets (1.742160 MPPS), 4790941100 bytes (8.000001 Gbps)
    RX 8691279 packets (1.738256 MPPS), 5127854610 bytes (8.538312 Gbps)
    Loss: 19523 packets (0.224124%)
Applying 7.000000 Gbps of load.
  v4:
    TX 7621953 packets (1.524391 MPPS), 4192074150 bytes (7.000002 Gbps)
    RX 7621953 packets (1.524391 MPPS), 3887196030 bytes (6.512197 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 7621953 packets (1.524391 MPPS), 4192074150 bytes (7.000002 Gbps)
    RX 7621953 packets (1.524391 MPPS), 4496952270 bytes (7.487807 Gbps)
    Loss: 0 packets (0.000000%)
```

## Running with 800 filters, _run-lwaftr 00200_filters_fromfile.conf_

This has 200 filters per ingress/egress option, or 800 total.

The filters were generated with the following bash script:
```
for x in {0..99}; do echo "not src host 192.168.255.${x}" >> 00200v4.pf; echo "not ether host 1:2:3:4:5:${x}" >> 00200v4.pf; done
for x in {0..99}; do echo "not src host 1::${x}" >> 00200v6.pf; echo "not ether host 1:2:3:4:5:${x}" >> 00200v6.pf; done
```

The configuration file changes: 
```
ipv4_ingress_filter = <00200v4.pf,
ipv4_egress_filter = <00200v4.pf, 
ipv6_ingress_filter = <00200v6.pf,
ipv6_egress_filter = <00200v6.pf,
```

Results: packet loss starts at 7 Gbps, peaking around 33-34% at 10 Gbps, and reaching 0 again at 4-6 Gbps during the cooldown, depending on the run. Note that this is made noisier by the jit.flush() overhead.

### Run 1, 800 filters

```
Applying 7.000000 Gbps of load.
  v4:
    TX 7621952 packets (1.524390 MPPS), 4192073600 bytes (7.000001 Gbps)
    RX 7616148 packets (1.523230 MPPS), 3884235480 bytes (6.507237 Gbps)
    Loss: 5804 packets (0.076148%)
  v6:
    TX 7621952 packets (1.524390 MPPS), 4192073600 bytes (7.000001 Gbps)
    RX 7616151 packets (1.523230 MPPS), 4493529090 bytes (7.482107 Gbps)
    Loss: 5801 packets (0.076109%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710797 packets (1.742159 MPPS), 4790938350 bytes (7.999996 Gbps)
    RX 7236179 packets (1.447236 MPPS), 3690451290 bytes (6.182591 Gbps)
    Loss: 1474618 packets (16.928623%)
  v6:
    TX 8710797 packets (1.742159 MPPS), 4790938350 bytes (7.999996 Gbps)
    RX 7236185 packets (1.447237 MPPS), 4269349150 bytes (7.108828 Gbps)
    Loss: 1474612 packets (16.928554%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799654 packets (1.959931 MPPS), 5389809700 bytes (9.000002 Gbps)
    RX 7189905 packets (1.437981 MPPS), 3666851550 bytes (6.143055 Gbps)
    Loss: 2609749 packets (26.631032%)
  v6:
    TX 9799654 packets (1.959931 MPPS), 5389809700 bytes (9.000002 Gbps)
    RX 7189907 packets (1.437981 MPPS), 4242045130 bytes (7.063365 Gbps)
    Loss: 2609747 packets (26.631012%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888491 packets (2.177698 MPPS), 5988670050 bytes (9.999990 Gbps)
    RX 7214206 packets (1.442841 MPPS), 3679245060 bytes (6.163818 Gbps)
    Loss: 3674285 packets (33.744667%)
  v6:
    TX 10888491 packets (2.177698 MPPS), 5988670050 bytes (9.999990 Gbps)
    RX 7214203 packets (1.442841 MPPS), 4256379770 bytes (7.087233 Gbps)
    Loss: 3674288 packets (33.744694%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888492 packets (2.177698 MPPS), 5988670600 bytes (9.999991 Gbps)
    RX 7301384 packets (1.460277 MPPS), 3723705840 bytes (6.238302 Gbps)
    Loss: 3587108 packets (32.944029%)
  v6:
    TX 10888492 packets (2.177698 MPPS), 5988670600 bytes (9.999991 Gbps)
    RX 7301383 packets (1.460277 MPPS), 4307815970 bytes (7.172879 Gbps)
    Loss: 3587109 packets (32.944039%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799640 packets (1.959928 MPPS), 5389802000 bytes (8.999989 Gbps)
    RX 7112846 packets (1.422569 MPPS), 3627551460 bytes (6.077216 Gbps)
    Loss: 2686794 packets (27.417272%)
  v6:
    TX 9799640 packets (1.959928 MPPS), 5389802000 bytes (8.999989 Gbps)
    RX 7112846 packets (1.422569 MPPS), 4196579140 bytes (6.987660 Gbps)
    Loss: 2686794 packets (27.417272%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710788 packets (1.742158 MPPS), 4790933400 bytes (7.999988 Gbps)
    RX 7183655 packets (1.436731 MPPS), 3663664050 bytes (6.137715 Gbps)
    Loss: 1527133 packets (17.531514%)
  v6:
    TX 8710788 packets (1.742158 MPPS), 4790933400 bytes (7.999988 Gbps)
    RX 7183660 packets (1.436732 MPPS), 4238359400 bytes (7.057228 Gbps)
    Loss: 1527128 packets (17.531456%)
Applying 7.000000 Gbps of load.
  v4:
    TX 7621945 packets (1.524389 MPPS), 4192069750 bytes (6.999994 Gbps)
    RX 7189769 packets (1.437954 MPPS), 3666782190 bytes (6.142939 Gbps)
    Loss: 432176 packets (5.670154%)
  v6:
    TX 7621945 packets (1.524389 MPPS), 4192069750 bytes (6.999994 Gbps)
    RX 7189822 packets (1.437964 MPPS), 4241994980 bytes (7.063281 Gbps)
    Loss: 432123 packets (5.669458%)
Applying 6.000000 Gbps of load.
  v4:
    TX 6533097 packets (1.306619 MPPS), 3593203350 bytes (5.999996 Gbps)
    RX 6531379 packets (1.306276 MPPS), 3331003290 bytes (5.580410 Gbps)
    Loss: 1718 packets (0.026297%)
  v6:
    TX 6533097 packets (1.306619 MPPS), 3593203350 bytes (5.999996 Gbps)
    RX 6531379 packets (1.306276 MPPS), 3853513610 bytes (6.416427 Gbps)
    Loss: 1718 packets (0.026297%)
Applying 5.000000 Gbps of load.
  v4:
    TX 5444249 packets (1.088850 MPPS), 2994336950 bytes (4.999998 Gbps)
    RX 5419919 packets (1.083984 MPPS), 2764158690 bytes (4.630779 Gbps)
    Loss: 24330 packets (0.446894%)
  v6:
    TX 5444249 packets (1.088850 MPPS), 2994336950 bytes (4.999998 Gbps)
    RX 5419916 packets (1.083983 MPPS), 3197750440 bytes (5.324525 Gbps)
    Loss: 24333 packets (0.446949%)
Applying 4.000000 Gbps of load.
  v4:
    TX 4355399 packets (0.871080 MPPS), 2395469450 bytes (3.999998 Gbps)
    RX 4355399 packets (0.871080 MPPS), 2221253490 bytes (3.721253 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 4355399 packets (0.871080 MPPS), 2395469450 bytes (3.999998 Gbps)
    RX 4355399 packets (0.871080 MPPS), 2569685410 bytes (4.278744 Gbps)
    Loss: 0 packets (0.000000%)
```

### Run 2, 800 filters

```
Applying 6.000000 Gbps of load.
  v4:
    TX 6533098 packets (1.306620 MPPS), 3593203900 bytes (5.999997 Gbps)
    RX 6533098 packets (1.306620 MPPS), 3331879980 bytes (5.581879 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 6533098 packets (1.306620 MPPS), 3593203900 bytes (5.999997 Gbps)
    RX 6533098 packets (1.306620 MPPS), 3854527820 bytes (6.418115 Gbps)
    Loss: 0 packets (0.000000%)
Applying 7.000000 Gbps of load.
  v4:
    TX 7621952 packets (1.524390 MPPS), 4192073600 bytes (7.000001 Gbps)
    RX 7103836 packets (1.420767 MPPS), 3622956360 bytes (6.069517 Gbps)
    Loss: 518116 packets (6.797681%)
  v6:
    TX 7621952 packets (1.524390 MPPS), 4192073600 bytes (7.000001 Gbps)
    RX 7103839 packets (1.420768 MPPS), 4191265010 bytes (6.978811 Gbps)
    Loss: 518113 packets (6.797642%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710805 packets (1.742161 MPPS), 4790942750 bytes (8.000003 Gbps)
    RX 7093638 packets (1.418728 MPPS), 3617755380 bytes (6.060804 Gbps)
    Loss: 1617167 packets (18.565069%)
  v6:
    TX 8710805 packets (1.742161 MPPS), 4790942750 bytes (8.000003 Gbps)
    RX 7093640 packets (1.418728 MPPS), 4185247600 bytes (6.968792 Gbps)
    Loss: 1617165 packets (18.565047%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799647 packets (1.959929 MPPS), 5389805850 bytes (8.999996 Gbps)
    RX 7264710 packets (1.452942 MPPS), 3705002100 bytes (6.206968 Gbps)
    Loss: 2534937 packets (25.867636%)
  v6:
    TX 9799647 packets (1.959929 MPPS), 5389805850 bytes (8.999996 Gbps)
    RX 7264778 packets (1.452956 MPPS), 4286219020 bytes (7.136918 Gbps)
    Loss: 2534869 packets (25.866942%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888504 packets (2.177701 MPPS), 5988677200 bytes (10.000002 Gbps)
    RX 7225050 packets (1.445010 MPPS), 3684775500 bytes (6.173083 Gbps)
    Loss: 3663454 packets (33.645155%)
  v6:
    TX 10888504 packets (2.177701 MPPS), 5988677200 bytes (10.000002 Gbps)
    RX 7225062 packets (1.445012 MPPS), 4262786580 bytes (7.097901 Gbps)
    Loss: 3663442 packets (33.645044%)
Applying 10.000000 Gbps of load.
  v4:
    TX 10888489 packets (2.177698 MPPS), 5988668950 bytes (9.999988 Gbps)
    RX 7191204 packets (1.438241 MPPS), 3667514040 bytes (6.144165 Gbps)
    Loss: 3697285 packets (33.955905%)
  v6:
    TX 10888489 packets (2.177698 MPPS), 5988668950 bytes (9.999988 Gbps)
    RX 7191199 packets (1.438240 MPPS), 4242807410 bytes (7.064634 Gbps)
    Loss: 3697290 packets (33.955951%)
Applying 9.000000 Gbps of load.
  v4:
    TX 9799643 packets (1.959929 MPPS), 5389803650 bytes (8.999992 Gbps)
    RX 7226986 packets (1.445397 MPPS), 3685762860 bytes (6.174737 Gbps)
    Loss: 2572657 packets (26.252558%)
  v6:
    TX 9799643 packets (1.959929 MPPS), 5389803650 bytes (8.999992 Gbps)
    RX 7226990 packets (1.445398 MPPS), 4263924100 bytes (7.099795 Gbps)
    Loss: 2572653 packets (26.252518%)
Applying 8.000000 Gbps of load.
  v4:
    TX 8710795 packets (1.742159 MPPS), 4790937250 bytes (7.999994 Gbps)
    RX 7257542 packets (1.451508 MPPS), 3701346420 bytes (6.200844 Gbps)
    Loss: 1453253 packets (16.683357%)
  v6:
    TX 8710795 packets (1.742159 MPPS), 4790937250 bytes (7.999994 Gbps)
    RX 7257542 packets (1.451508 MPPS), 4281949780 bytes (7.129809 Gbps)
    Loss: 1453253 packets (16.683357%)
Applying 7.000000 Gbps of load.
  v4:
    TX 7621952 packets (1.524390 MPPS), 4192073600 bytes (7.000001 Gbps)
    RX 7244637 packets (1.448927 MPPS), 3694764870 bytes (6.189818 Gbps)
    Loss: 377315 packets (4.950372%)
  v6:
    TX 7621952 packets (1.524390 MPPS), 4192073600 bytes (7.000001 Gbps)
    RX 7244636 packets (1.448927 MPPS), 4274335240 bytes (7.117130 Gbps)
    Loss: 377316 packets (4.950385%)
Applying 6.000000 Gbps of load.
  v4:
    TX 6533101 packets (1.306620 MPPS), 3593205550 bytes (6.000000 Gbps)
    RX 6502374 packets (1.300475 MPPS), 3316210740 bytes (5.555628 Gbps)
    Loss: 30727 packets (0.470328%)
  v6:
    TX 6533101 packets (1.306620 MPPS), 3593205550 bytes (6.000000 Gbps)
    RX 6502374 packets (1.300475 MPPS), 3836400660 bytes (6.387932 Gbps)
    Loss: 30727 packets (0.470328%)
Applying 5.000000 Gbps of load.
  v4:
    TX 5444247 packets (1.088849 MPPS), 2994335850 bytes (4.999996 Gbps)
    RX 5444247 packets (1.088849 MPPS), 2776565970 bytes (4.651565 Gbps)
    Loss: 0 packets (0.000000%)
  v6:
    TX 5444247 packets (1.088849 MPPS), 2994335850 bytes (4.999996 Gbps)
    RX 5444247 packets (1.088849 MPPS), 3212105730 bytes (5.348428 Gbps)
    Loss: 0 packets (0.000000%)
```
