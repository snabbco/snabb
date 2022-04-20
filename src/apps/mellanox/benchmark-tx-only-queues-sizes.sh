#!/usr/bin/env bash

sizes_fine="64
66
70
74
78
84
90
96
104
114
126
140
156
174
196
222
254
292
338
392
456
534
628
740
874
1034
1226
1456"

sizes_coarse="64
128
256
512
1024"

echo i,workers,queues,pktsize,rate,drop,error
for i in `seq 1 3`; do
    for w in `seq 1 5`; do
        for q in `seq 1 4`; do
            for s in $sizes_coarse; do
                out=$(./snabb snsh apps/mellanox/benchmark.snabb -a b3:00.0 -b b3:00.1 -A 2-6 -B 7-11 \
                        -m source -w $w -q $q -s $s -n 100e6)
                rate=$(echo "$out" | grep "Tx Rate is" | cut -d " " -f 4)
                drop=$(echo "$out" | grep "Tx Drop Rate is" | cut -d " " -f 5)
                error=$(echo "$out" | grep "Tx Error Rate is" | cut -d " " -f 5)
                echo "$i,$w,$q,$s,$rate,$drop,$error"
                #echo $out
            done
        done
    done
done