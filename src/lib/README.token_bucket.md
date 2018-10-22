### Token Bucket (lib.token_bucket)

This module implements a [token
bucket](https://en.wikipedia.org/wiki/Token_bucket) for rate-limiting
of arbitrary events.  The bucket is filled with tokens at a constant
rate up to a given maximum called the *burst_size*.  Tokens are added
and removed in integer quantities.  An event can only take place if at
least one token is available.  A burst of back-to-back events is
allowed to happen by consuming all available tokens at a given point
in time.  The maximum size of such a burst is determined by the
capacity of the bucket, hence the name *burst_size*.

The token bucket is updated in a lazy fashion, i.e. only when a
request for tokens cannot be satisfied immediately.

By default, a token bucket uses the `rdtsc` time source via the
[`tsc`](./README.tsc.md) module to minimise overhead.  To override,
the `default_source` parameter of the `tsc` module must be set
to the desired value.

#### Functions

— Function **new** *config*

Creates an instance of a token bucket.  The required *config* argument
must be a table with the following keys.

— Key **rate**

*Required*.  The rate in units of Hz at which tokens are placed in the
bucket as an arbitrary floating point number larger than zero.

— Key **burst_size**

*Optional*.  The maximum number of tokens that can be stored in the
bucket.  The default is **rate** tokens, i.e. the amount of tokens
accumulated over one second rounded up to the next integer.

#### Methods

The object returned by the **new** function provides the following
methods.

— Method **token_bucket:set** [*rate*], [*burst_size*]

Set the rate and burst size to the values *rate* and *burst_size*,
respectively, and fill the bucket to capacity.  If *rate* is `nil`,
the rate remains unchanged.  If *burst_size* is `nil`, the burst size
is set to the number of tokens that will be accumulated over one
second with the new rate (like in the **new** function).

— Method **token_bucket:get**

Returns the current rate and burst size.

— Method **token_bucket:can_take** [*n*]

Returns `true` if at least *n* tokens are available, `false`
otherwise.  If *n* is `nil`, the bucket is checked for a single token.

— Method **token_bucket:take** [*n*]

If at least *n* tokens are available, they are removed from the bucket
and the method returns `true`.  Otherwise, the bucket remains
unchanged and `false` is returned. If *n* is `nil`, the bucket is
checked for a single token.

— Method **token_bucket:take_burst**

Takes all available tokens from the bucket and returns that number.
