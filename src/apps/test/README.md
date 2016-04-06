# Test Apps

## Match (apps.test.match)

The `Match` app compares packets received on its input port `rx` with those
received on the reference input port `comparator`, and reports mismatches as
well as packets from `comparator` that were not matched.

    DIAGRAM: Match
                  +----------+
                  |          |
           rx ----*          |
                  |   Match  |
    comparator ---*          |
                  |          |
                  +----------+

— Method **Match:errors**

Returns the recorded errors as an array of strings.

### Configuration

The `Match` app accepts a table as its configuration argument. The following
keys are defined:

— Key **fuzzy**

*Optional.* If this key is `true` packets from `rx` that do not match the next
packet from `comparator` are ignored. The default is `false`.
