Usage:
  snabb ipfix probe_rss [options] <config-file>

Available options:
       -h, --help               Display this help message
       -D, --duration <seconds> Duration to run (in seconds).
       -b, --busy-wait          Enable polling for arriving packets.  By default, the system
                                uses sleep(3) during periods of little or no traffic to
                                reduce CPU usage.
       -L, --log-date           Include date and time in log messages. Off by default.
       -j CMD, --jit CMD        Control LuaJIT behavior. Available commands:
                                  -jv=FILE, --jit v=FILE
                                    Write verbose JIT trace output to FILE.
                                  -jdump=OPTS[,FILE] --jit dump=OPTS[,FILE]
                                    Output JIT traces, optionally to a file.
                                  -jp=OPTS[,FILE] --jit p=OPTS[,FILE]
                                    Profile execution with low-overhead sampling.
                                  -jopt=OPT
                                    Sets JIT option OPT.
                                  -jtprof
                                    Profile execution with the traceprof library.
                                 See luajit documentation for more information:
                                   http://luajit.org/running.html
       -d, --debug               Enable developer debug
