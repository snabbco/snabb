n=$APP_N
p=$LISP_N
[ "$n" ] || exit 1
[ "$p" ] || exit 1
run() {
ip netns exec node$n ./l2tp.lua t0 e0 \
    00:00:00:00:01:0$n \
    00:00:00:00:00:0$n \
    fd80:000$n:0000:0000:0000:0000:0000:0002 \
    fd80:000$p:0000:0000:0000:0000:0000:0002 \
    0000000$n 0000000$n
}
start()   { run >/dev/null & }
stop()    { pgrep -f "l2tp.lua .\*\?01:0$n " | xargs kill -9; }
restart() { stop; start; }
if [ "$1" ]; then $1; else stop; run; fi
