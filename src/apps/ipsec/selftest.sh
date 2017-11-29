#!/usr/bin/env bash
#set -x

SKIPPED_CODE=43

if [ "$SNABB_IPSEC_SKIP_E2E_TEST" = yes ]; then
    exit $SKIPPED_CODE
fi

if [ -z "$SNABB_TELNET0" ]; then
    export SNABB_TELNET0=5000
    echo "Defaulting to SNABB_TELNET0=$SNABB_TELNET0"
fi

SPI=2953575118

SRC=fc00:feed:face:dead::1
DST=fc00:feed:face:dead::2

IP=$DST
MAC=52:54:01:00:00:

TKEY=d4d61fec2861b3b806d0654eeea02ede
TSALT=df3ddb99
TKS=$TKEY$TSALT

RKEY=c4d61fec2861b3b806d0654eeea02ede
RSALT=cf3ddb99
RKS=$RKEY$RSALT

SPORT=60122
DPORT=60123

if ! source program/snabbnfv/test_env/test_env.sh; then
    echo "Could not load test_env."; exit 1
fi

./snabb snsh apps/ipsec/selftest.lua ${MAC}01 ${MAC}00 $SRC $DST $SPORT $DPORT $SPI $TKEY $TSALT $RKEY $RSALT 3 ping &
snabb_pid=$!

if ! qemu soft esp.sock $SNABB_TELNET0; then
    echo "Could not start qemu."; exit $SKIPPED_CODE
fi

wait_vm_up $SNABB_TELNET0
run_telnet $SNABB_TELNET0 "systemctl stop dhcpcd.service &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ifconfig eth0 down &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ip -6 neigh flush dev eth0 &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ip -6 neigh add $SRC lladdr ${MAC}01 dev eth0 &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ip -6 addr add $DST/7 dev eth0 &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ifconfig eth0 up &>/dev/console" >/dev/null
run_telnet $SNABB_TELNET0 "ncat -lkuc cat $DPORT &>/dev/console &" >/dev/null


#---------------------------------------------------------

#      |-------------key--------------||-SALT-|
#KEY=0x`dd if=/dev/urandom count=32 bs=1 2> /dev/null| xxd -p -c 64`
SPI_ID=0xb00bface
#SPI_ID=0x`dd if=/dev/urandom count=4 bs=1 2> /dev/null| xxd -p -c 8`

SPISTR="spi $SPI_ID"
PROTO="proto esp"

SD_FWD="src $SRC dst $DST"
SD_REV="src $DST dst $SRC"

SDP_FWD="$SD_FWD $PROTO"
SDP_REV="$SD_REV $PROTO"

ID_FWD="$SDP_FWD $SPISTR"
ID_REV="$SDP_REV $SPISTR"

MODE="mode transport"
REPLAY="replay-window 128"
FLAG="flag esn"
RALGO="aead rfc4106\(gcm\(aes\)\) 0x$RKS 96"
TALGO="aead rfc4106\(gcm\(aes\)\) 0x$TKS 96"

cmd="echo 'spdflush; flush;' | setkey -c"
cmd="$cmd; ip xfrm state add   $ID_FWD  $MODE  $REPLAY  $FLAG   $TALGO"
cmd="$cmd; ip xfrm state add   $ID_REV  $MODE  $REPLAY  $FLAG   $RALGO "
cmd="$cmd; ip xfrm policy add   $SD_REV   dir out   tmpl $SDP_REV   $MODE"
cmd="$cmd; ip xfrm policy add   $SD_FWD   dir in    tmpl $SDP_FWD   $MODE"
run_telnet $SNABB_TELNET0 "$cmd &>/dev/console" >/dev/null
#---------------------------------------------------------

wait $snabb_pid
