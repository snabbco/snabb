Usage: snabb config get-state [OPTION]... ID PATH
Get the state for a Snabb network function.

Available options:
  -s, --schema SCHEMA        YANG data interface to request.
  -r, --revision REVISION    Require a specific revision of the YANG module.
  -h, --help                 Displays this message.

Given an instance identifier and a schema path, display the current counter
values.

If the --schema argument is not provided, "snabb config" will ask the data
plane for its native schema. The result will be printed on standard output.

Typical usage:

$ snabb config get-state lwaftr /softwire-state/

See https://github.com/Igalia/snabb/blob/lwaftr/src/program/config/README.md
for full documentation.
