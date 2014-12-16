# RateLimiter App (apps.rate_limiter.rate_limiter)

The `RateLimiter` app implements a
[Token bucket](http://en.wikipedia.org/wiki/Token_bucket) algorithm with a
single bucket dropping non-conforming packets.  It receives packets on
the `input` port and transmits conforming packets to the `output` port.

    DIAGRAM: RateLimiter
               +--------------+
               |              |
    input ---->* RateLimiter  *----> output
               |              |
               +--------------+

— Method **RateLimiter:snapshot**

Returns throughput statistics in form of a table with the following
fields:

* `rx` - Number of packets received
* `tx` - Number of packets transmitted
* `time` - Current time in nanoseconds


## Configuration

The `RateLimiter` app accepts a table as its configuration argument. The
following keys are defined:

— Key **rate**

*Required*. Rate in bytes per second to which throughput should be
limited.

— Key **bucket_capacity**

*Required*. Bucket capacity in bytes. Should be equal or greater than
*rate*. Otherwise the effective rate may be limted.

— Key **initial_capacity**

*Optional*. Initial bucket capacity in bytes. Defaults to
*bucket_capacity*.

## Performance

The `RateLimiter` app is able to process more than 20 Mpps per CPU
core. Refer to its selftest for details.
