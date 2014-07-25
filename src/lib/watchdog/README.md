The `lib.watchdog.watchdog` module implements a per-thread watchdog
functionality. Its purpose is to watch and kill processes which fail to
call the watchdog periodically (e.g. hang).

It does so by using `alarm(3)` and `ualarm(3)` to have the OS send a
`SIGALRM` to the process after a specified timeout. Because the process
does not handle the signal it will be killed and exit with status `142`.

Usage is as follows:

    -- Use the watchdog module.
    watchdog = require("lib.watchdog.wachdog")

`set(n)` sets the watchdog timeout to `n` milliseconds. Because
`alarm(3)` is used for timeouts longer than one second values for `n`
greater than 1000 (e.g. a second) will be rounded up to the next second
(e.g. `set(1100)` <=> `set(2000)`).

    -- Set the timeout to 500ms.
    watchdog.set(500)

`reset()` will reset the alarm (or start it if it has not been started
before). Thus now you have 500 milliseconds to reset before the process
will be killed.

    -- Start or reset the timeout.
    watchdog.reset()

Alternatively you can use `stop()` to disable the timeout and prevent the
process to be killed.

    -- Disable the timeout.
    watchdog.stop()

