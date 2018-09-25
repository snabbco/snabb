### Logger (lib.logger)

The *logger* module implements a rate-limited logging facility with
optional throttling of the logging rate under stress.  It uses
*lib.token_bucket* with the *rdtsc* time-source (if available) for
rate-limiting, which makes it suitable to be called from
critical code with minimal impact on performance.

#### Functions

— Function **new** *config*

Creates an instance of a logger.  The required *config* argument must
be a table with the following keys.

— Key **rate**

*Optional*.  The rate in units of Hz at which the output of log
messages is limited.  The default is 10 Hz.  The maximum burst size
(the number of messages that can be posted back-to-back) is
numerically equal to **rate** (i.e. the maximum number of messages
allowed during an interval of one second).  Messages that exceed the
rate limit are discarded.  The number of discarded messages is
reported periodically, see the **discard_report_rate** configuration
option.

— Key **discard_report_rate**

*Optional*.  The rate in units of Hz at which reporting of the number
of discarded messages is limited.  The default is 0.2 Hz.

— Key **fh**

*Optional*.  The file handle to which log messages are written.  The
default is **io.stdout**.

— Key **flush**

*Optional*. A boolean that indicates wheter **fh** should be flushed
after each write.  The default is **true**.

— Key **module**

*Optional*. An arbitrary string that will be prepended to each log
message to identify the component of the application that generated
the message.  The default is the empty string.

— Key **date**

*Optional*. A boolean that indicates whether each log message should
be prepended by the current date and time according to the format
given by the **date_fmt** configuration option.  The default is
**true**.

— Key **date_fmt**

*Optional*.  A string that defines the format of the time stamp
prepended to each log message if the **date** configuration option is
**true**.  It must be a valid format specifier as expected by the
**os.date** function.  The default is **"%b %d %Y %H:%M:%S "**.

— Key **throttle**

*Optional*.  A boolean that indicates whether automatic throttling of
the logging rate should be enabled.  The default is **true**.

The mechanism decrease the logging rate when the number of discarded
messages exceeds a certain threshold to allow a relatively high
logging rate under normal circumstances while avoiding large amounts
of messages during "logging storms".

Throttling is coupled to the rate-limiting of discard reports as
follows.  Whenever a discard report is logged (according to the
**discard_report_rate** option), the rate of discarded messages since
the last such event is calculated.

If this rate exceeds a configurable multiple, called the _excess_, of
**rate**, the effective rate-limit is decreased by a factor of 2.  The
effective rate-limit is bounded from below by a configurable minimum.

If the rate of discarded messages is below the threshold, the
effective rate-limit is increased by a configurable fraction of
**rate**.  The effective rate is bounded from above by **rate**.

— Key **throttle_config**

*Optional*.  This is a table with the following keys.

  * Key **excess**

    *Optional*.  The threshold for the rate of discarded messages at
    which throttling is applied as detailed above is given by
    **excess** \* **rate**.  The default is 5 (i.e. the default
    threshold is 50 Hz).

  * Key **increment**

    *Optional*.  The fraction of **rate** at which the effective
    rate-limit is increased when the rate of discarded messages is
    below the threshold.  The default is 4, i.e. the effective
    increment of the rate is given by **rate**/4 by default.
  
  * Key **min_rate**

    *Optional*.  The lower bound for the effective rate when
    throttling is in effect.  The default is 0.1 Hz.
  
#### Methods

The object returned by the **new** function provides the following
methods.

— Method **logger:log** *msg*

Print the string *msg* to the logger's file handle.  The string is
prepended by the date and/or the module name according to the
configuration. If any messages have been discarded since the last time
a message has been successfully logged, the number of discarded
messages is logged as well, subject to the rate-limiting given by
**discard_report_rate**.  If the discard report is allowd by that
rate-limit and throttling is enabled, the new effective logging rate
is calculated and applied as well.

If the rate-limit is exceeded, the message is discarded.

Note that *msg* is evaluated before the method is called.  If the
evaluation is expensive (e.g. a concatenation of strings) and the
caller is in a performance-critical section of code, the **can_log**
method should be used to determine whether the message is allowed by
the rate-limiter, e.g.

```Lua
if logger:can_log() then
   logger:log("foo " .. "bar")
end
```

— Method **logger:can_log**

Returns a **true** value if a message can be logged successfully,
**false** otherwise.
