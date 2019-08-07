#!/usr/bin/env bash

MODE=$1
AEAD=$2

SPI=2953575118

SRC=fc00:feed:face:dead::1
DST=fc00:feed:face:dead::2

TKEY=d4d61fec2861b3b806d0654eeea02ede
TSALT=df3ddb99
RKEY=c4d61fec2861b3b806d0654eeea02ede
RSALT=cf3ddb99
if [ $AEAD = "aes-gcm-16-icv" ]; then
    # Do nothing.
    :
elif [ $AEAD = "aes-256-gcm-16-icv" ]; then
    # Need 256 bit keys.
    TKEY=$TKEY$TKEY
    RKEY=$RKEY$RKEY
else
    echo "Unsupported AEAD: $AEAD"
    exit 1
fi
TKS=$TKEY$TSALT
RKS=$RKEY$RSALT

SPORT=60122
DPORT=60123

if ! source program/snabbnfv/test_env/test_env.sh; then
    echo "Could not load test_env."; exit 1
fi

qemu soft esp.sock $SNABB_TELNET0

apps/ipsec/test-linux-compat.snabb \
   $MODE $AEAD ${MAC}01 $SRC $DST $SPORT $DPORT $SPI $TKEY $TSALT $RKEY $RSALT ping &
snabb_pid=$!

wait_vm_up $SNABB_TELNET0
run_telnet $SNABB_TELNET0 "systemctl stop dhcpcd.service &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ifconfig eth0 down &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ip -6 addr add $DST/7 dev eth0 &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ifconfig eth0 up &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ncat -vvvlkuc cat $DPORT &>/dev/console &" >/dev/null

SPI_ID=0xb00bface

SPISTR="spi $SPI_ID"
PROTO="proto esp"

SD_FWD="src $SRC dst $DST"
SD_REV="src $DST dst $SRC"

SDP_FWD="$SD_FWD $PROTO"
SDP_REV="$SD_REV $PROTO"

ID_FWD="$SDP_FWD $SPISTR"
ID_REV="$SDP_REV $SPISTR"

REPLAY="replay-window 128"
FLAG="flag esn"
#          |aead                   |keymat  |icv bits
RALGO="aead rfc4106\(gcm\(aes\)\)   0x$RKS   128"
TALGO="aead rfc4106\(gcm\(aes\)\)   0x$TKS   128"

cmd="echo 'spdflush; flush;' | setkey -c"
cmd="$cmd; ip xfrm state add   $ID_FWD  mode $MODE  $REPLAY  $FLAG   $TALGO"
cmd="$cmd; ip xfrm state add   $ID_REV  mode $MODE  $REPLAY  $FLAG   $RALGO "
cmd="$cmd; ip xfrm policy add   $SD_REV   dir out   tmpl $SDP_REV   mode $MODE"
cmd="$cmd; ip xfrm policy add   $SD_FWD   dir in    tmpl $SDP_FWD   mode $MODE"
run_telnet $SNABB_TELNET0 "$cmd &>/dev/console" >/dev/null

wait $snabb_pid
