### ipfix probe

The `ipfix probe` program runs an IPFIX meter and exporter on the
packets coming in on an interface.  It can be invoked like so:

```
./snabb ipfix probe [options] <configuration>
```

The configuration is documented in the schema *src/lib/yang/snabb-snabbflow-v1.yang*.

See `./snabb ipfix probe --help` for documentation of the command line options.

Usually you want to run `ipfix probe` using an input interface that
receives a mirror of your "main" traffic flow.

#### Testing

There is a regression test you can run via

```
./snabb snsh -t program.ipfix.tests.test
```

You can also run the same test as an integration test with a third party IPFIX collector (`capd`):

```
program/ipfix/tests/collector-test.sh
```

#### Benchmark

There is a benchmark script to test `ipfix probe` performance. It can be run like so:

```
./snabb snsh program/ipfix/tests/bench.snabb \
    --cpu 6-7 --loadgen-cpu 22-23 \
    --duration 20 --new-flows-freq 450 \
    81:00.0 81:00.1
```

Running the script without arguments will print the available command line options.
