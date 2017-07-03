Usage: snabb config listen [OPTION]... ID
Open a persistent control channel to a Snabb network function.

Available options:
  -s, --schema SCHEMA        YANG data interface to request.
  -r, --revision REVISION    Require a specific revision of the YANG module.
  -h, --help                 Display this message.
  -c, --socket               Path to unix socket if using.

If the --schema argument is not provided, "snabb config" will ask the
data plane for its native schema.

If the --socket argument is provided, it will accept a single client over the
unix socket. If it has not been provided, it will accept commands over stdin
and display them on stdout.

See https://github.com/Igalia/snabb/blob/lwaftr/src/program/config/README.md
for full documentation.
