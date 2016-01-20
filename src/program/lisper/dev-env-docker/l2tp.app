n=$APP_N
p=$LISP_N
[ "$n" ] || exit 1
[ "$p" ] || exit 1
run() {
ip netns exec node$n ./l2tp.lua t0 e0 \
    00:00:00:00:01:$n \
    00:00:00:00:00:$n \
    fd80:00$n:0000:0000:0000:0000:0000:0002 \
    fd80:00$p:0000:0000:0000:0000:0000:0002 \
    000000$n 000000$n
}
start()   { run >/dev/null & }
stop()    { pgrep -f "l2tp.lua .\*\?01:$n " | xargs kill -9; }
restart() { stop; start; }
if [ "$1" ]; then $1; else stop; run; fi
