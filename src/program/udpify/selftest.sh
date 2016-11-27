#!/usr/bin/env bash
#set -u
#set -x
exec 2>selftest.sh.trace
set -x

SKIPPED_CODE=43

if [ -z "$SNABB_TELNET0" ]; then
    export SNABB_TELNET0=5000
    echo "Defaulting to SNABB_TELNET0=$SNABB_TELNET0"
fi

dbg()
{
	echo "$*" >&2
}

# Usage: run_telnet <port> <command> [<sleep>]
# Runs <command> on VM listening on telnet <port>. Waits <sleep> seconds
# for before closing connection. The default of <sleep> is 2.
#1: port, 2: cmd, [3: timeout]
function run_telnet {
    (echo "$2"; sleep ${3:-2}) \
        | telnet localhost $1 2>&1
}

telnet_log=0
#1: outfile, 2: port, 3-: cmd
function run_telnetx {
	tport="$1"
	shift 1

	marker='grzlbrzlhmpldmpl'
	retc="$(mktemp retc.XXXXXXXX)"
	fifo="$(mktemp fifo.XXXXXXXX)"
	rm -f $retc $fifo
	mkfifo $fifo

	( while ! [ -f $retc ]; do sleep 1; done; printf '' >$fifo ) &
	waiter=$!

   ( printf '( %s ) ; echo %s $?\r\n' "$*" "$marker"; cat $fifo ) \
        | telnet localhost $tport | while read -r lx; do
		  ln="$(printf '%s\n' "$lx" | tr -d '\r')"
		  case "$ln" in
		     $marker\ [0-9]*)
			     echo "${ln#* }" >$retc
				  break ;;
		  esac
		  printf '%s\n' "$ln" | tee -a $tout telnet$telnet_log.log >/dev/null
	done
	telnet_log=$((telnet_log+1))
	rc="$(cat $retc)"
	rm -f $retc $fifo
	return $rc
}


function run_telnet2 {
	local marker='grzlbrzl'
	local port="$1"
	shift
   #printf '( %s ) ; echo %s\n' "$*" "$marker" \
   printf "$*\r\n" \
        | telnet localhost $port | while read -r ln; do
		  echo "LINE '$ln'" >&2
		  #echo "$ln"
		  case "$ln" in
		  $marker) echo 'got ze marker' >&2; return 0 ;;
		  esac
	done
	echo 'no marker :(' >&2
	return 1
}

function start_test_env {
    dbg "start_test_env"

    if ! qemu soft esp.sock $SNABB_TELNET0 >qemu.wat 2>&1 ; then
        echo "Could not start qemu 0."; exit 1
    fi

    #sleep 5444

    wait_vm_up $SNABB_TELNET0

#    sleep 10
    run_telnet $SNABB_TELNET0 "systemctl stop dhcpcd.service &>/dev/console" >/dev/null
#    sleep 3
#    run_telnet $SNABB_TELNET0 "ifconfig eth0 inet 0.0.0.0 &>/dev/console" >/dev/null
#    sleep 1
#    run_telnet $SNABB_TELNET0 "ifconfig eth0 down &>/dev/console" >/dev/null
#    sleep 1
#    run_telnet $SNABB_TELNET0 "ifconfig -a &>/dev/console" >/dev/null
#    sleep 1
    run_telnet $SNABB_TELNET0 "ifconfig eth0 down"
     run_telnet $SNABB_TELNET0 "ip -6 neigh flush dev eth0"
     run_telnet $SNABB_TELNET0 "ip -6 neigh add $SRC lladdr ${MAC}01 dev eth0"
     run_telnet $SNABB_TELNET0 "ip -6 addr add $DST/7 dev eth0 &>/dev/console" >/dev/null
    run_telnet $SNABB_TELNET0 "ifconfig eth0 up"
#    sleep 3
	#t=0
    #run_telnet $SNABB_TELNET0 "while true; do ifconfig -a >/dev/console; sleep 15; done &" >/dev/null



#run_telnet $SNABB_TELNET0 "echo 'spdflush; flush;' | setkey -c"
#run_telnet $SNABB_TELNET0 "ip xfrm state add src $SRC dst $DST proto esp spi 0x$(printf '%02x' "$SPI") mode transport replay-window 128 flag esn aead rfc4106\(gcm\(aes\)\) 0x$RKS 96"
#run_telnet $SNABB_TELNET0 "ip xfrm state add src $DST dst $SRC proto esp spi 0x$(printf '%02x' "$SPI") mode transport replay-window 128 flag esn aead rfc4106\(gcm\(aes\)\) 0x$TKS 96"
#run_telnet $SNABB_TELNET0 "ip xfrm policy add src $DST dst $SRC dir out tmpl src $DST dst $SRC proto esp mode transport"
#run_telnet $SNABB_TELNET0 "ip xfrm policy add src $SRC dst $DST dir in tmpl src $SRC dst $DST proto esp mode transport"
run_telnet $SNABB_TELNET0 "ncat -lkuc cat $DPORT &"
#sleep 2
#run_telnet $SNABB_TELNET0 "ifconfig -a &>/dev/console"
#run_telnet $SNABB_TELNET0 "netstat -n -a -p &>/dev/console"
#run_telnet $SNABB_TELNET0 "strace -r -f -p \$(pgrep ncat) &>/dev/console &"
#run_telnet $SNABB_TELNET0 "command -v pgrep &>/dev/console"

	 #if run_telnet telnet$t.out $SNABB_TELNET0 'echo "my pid is $$"'; then
	 #  echo "yesecho!" >&2
	 #else
	 #  echo "nahecho!" >&2
	 #fi
	 #t=$((t+1))
	 #if run_telnet telnet$t.out $SNABB_TELNET0 'ls /'; then
	 #  echo "yesls!" >&2
	 #else
	 #  echo "nahls!" >&2
	 #fi
	 #t=$((t+1))
	 #if run_telnet telnet$t.out $SNABB_TELNET0 'ls /dqwjdwqoi'; then
	 #  echo "yeslsx!" >&2
	 #else
	 #  echo "nahlsx!" >&2
	 #fi
	 #t=$((t+1))
	 #if run_telnet telnet$t.out $SNABB_TELNET0 'madwqhoqw'; then
	 #  echo "yesmissingx!" >&2
	 #else
	 #  echo "nahmissingx!" >&2
	 #fi
	 #t=$((t+1))
	 #run_telnet telnet$t.out $SNABB_TELNET0 'dd if=/dev/urandom of=/dev/null bs=1M count=50 &'
	 #echo "ls: exit code $?" >>telnet$t.out
	 #t=$((t+1))
	 #run_telnet telnet$t.out $SNABB_TELNET0 'ls -la /qwdo'
	 #echo "ls: exit code $?" >>telnet$t.out
	 #t=$((t+1))
	 #run_telnet telnet$t.out $SNABB_TELNET0 ofdiqhwio
	 #echo "missing: exit code $?" >>telnet$t.out
	 #t=$((t+1))
}

# Usage: wait_vm_up <port>
# Blocks until ping to 0::0 suceeds.
function wait_vm_up {
    local timeout_counter=0
    local timeout_max=50
    echo -n "Waiting for VM listening on telnet port $1 to get ready..."
    while ( ! (run_telnet $1 "ping6 -c 1 0::0" | grep "1 received" \
        >/dev/null) ); do
        # Time out eventually.
        if [ $timeout_counter -gt $timeout_max ]; then
            echo " [TIMEOUT]"
            exit 1
        fi
        timeout_counter=$(expr $timeout_counter + 1)
        sleep 2
    done
    echo " [OK]"
}

# Usage: wait_vm_up <port>
# Blocks until ping to 0::0 suceeds.
function wait_vm_up2 {
    dbg "wait_vm_up2"
    local timeout_counter=0
    local timeout_max=2
    echo -n "Waiting for VM listening on telnet port $1 to get ready..."
    while ( ! (run_telnet $1 "w" 2>&1 | tee -a w.log \
        >/dev/null) ); do
	    dbg "in loop"
        # Time out eventually.
        if [ $timeout_counter -gt $timeout_max ]; then
            echo " [TIMEOUT]"
		sleep 31338
            exit 1
        fi
        timeout_counter=$(expr $timeout_counter + 1)
        sleep 2
    done
    echo " [OK]"
}

function assert {
    if [ $2 == "0" ]; then echo "$1 succeded."
    else
        echo "$1 failed."
        echo
        echo "qemu0.log:"
        cat "qemu0.log"
        echo
        echo
        echo "qemu1.log:"
        cat "qemu1.log"
        echo
        echo
        echo "snabb0.log:"
        cat "snabb0.log"
        exit 1
    fi
}

function test_foo {
    echo "=================== TEST FOO =============================";
    assert PING $?
}


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

if ! source program/udpify/test_env/test_env.sh; then
echo "Could not load test_env."; exit 1
fi
./snabb udpify ${MAC}01 ${MAC}00 $SRC $DST $SPORT $DPORT $SPI $TKEY $TSALT $RKEY $RSALT 3 ping &
child=$!
start_test_env


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
run_telnet $SNABB_TELNET0 "$cmd"
#---------------------------------------------------------



#sleep 3
#run_telnet $SNABB_TELNET0 "ps fauxww &>/dev/console"
#run_telnet $SNABB_TELNET0 "ifconfig -a &>/dev/console" >/dev/null
#run_telnet $SNABB_TELNET0 "netstat -rn6 &>/dev/console" >/dev/null
#run_telnet $SNABB_TELNET0 "echo foo | nc -6 -n $SRC $SPORT &>/dev/console" >/dev/null
#sleep 2
#run_telnet $SNABB_TELNET0 "echo foo | nc -6 -n $SRC $SPORT &>/dev/console" >/dev/null
#sleep 2
#run_telnet $SNABB_TELNET0 "echo foo | nc -6 -n $SRC $SPORT &>/dev/console" >/dev/null
#sleep 2
#run_telnet $SNABB_TELNET0 "echo foo | nc -6 -n $SRC $SPORT &>/dev/console" >/dev/null

wait $child
ret=$?
echo "waited"
#sleep 31337

exit $ret
