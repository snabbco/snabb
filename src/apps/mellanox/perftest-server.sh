#!/bin/sh

sudo taskset 0010 $HOME/perftest-2.2/raw_ethernet_bw -d mlx4_2 -l 8 --size 64 --server --duration 3
