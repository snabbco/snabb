The `lib.watchdog.watchdog` module implements a per-thread watchdog
functionality. Its purpose is to watch and kill processes which fail to
call the watchdog periodically (e.g. hang).

It does so by using *alarm(3)* and *ualarm(3)* to have the OS send a
*SIGALRM* to the process after a specified timeout. Because the process
does not handle the signal it will be killed and exit with status *142*.

— Function **watchdog.set** *milliseconds*

Set watchdog timeout to *milliseconds*. Values for *milliseconds* greater
than 1,000 are truncated to the next second. For example:

```
watchdog.set(1100) == watchdog.set(2000)
```

— Function **watchdog.reset**

Starts the timout if the watchdog has not yet been started and resets the
timeout otherwise. If the timeout is reached the process will be killed.


— Function **watchdog.stop**

Disables the timeout.
