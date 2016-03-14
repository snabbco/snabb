### `checksum`: IP checksum

The checksum module provides an optimized ones-complement checksum
routine.

— Function **ipsum** *pointer* *length* *initial*

Return the ones-complement checksum for the given region of memory.

*pointer* is a pointer to an array of data to be checksummed. *initial*
is an unsigned 16-bit number in host byte order which is used as
the starting value of the accumulator.  The result is the IP
checksum over the data in host byte order.

The *initial* argument can be used to verify a checksum or to
calculate the checksum in an incremental manner over chunks of
memory.  The synopsis to check whether the checksum over a block of
data is equal to a given value is the following

```
if ipsum(pointer, length, value) == 0 then
  -- checksum correct
else
  -- checksum incorrect
end
```

To chain the calculation of checksums over multiple blocks of data
together to obtain the overall checksum, one needs to pass the
one's complement of the checksum of one block as initial value to
the call of ipsum() for the following block, e.g.

```
local sum1 = ipsum(data1, length1, 0)
local total_sum = ipsum(data2, length2, bit.bnot(sum1))
```

This function takes advantage of SIMD hardware when available.
