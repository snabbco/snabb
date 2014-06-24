#!/bin/sh

sudo taskset 0020 $HOME/perftest-2.2/raw_ethernet_bw -d mlx4_3 -l 8 --size 64 --client --duration 3 --source_mac f4:52:14:10:16:f0 --dest_mac f4:52:14:10:18:20
