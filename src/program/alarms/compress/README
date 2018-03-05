Usage: snabb alarms compress [OPTION]... ID RESOURCE ALARM-TYPE-ID/ALARM-TYPE-QUALIFIER
Compress status change for all matching alarms.

Available options:
  -s, --schema SCHEMA           YANG data interface to request.
  -r, --revision REVISION       Require a specific revision of the YANG module.
  -f, --format                  Selects output format (yang or xpath). Default: yang.
      --print-default           Forces print out of default values.
  -h, --help                    Displays this message.

Given an instance identifier, a resource, an alarm type identifier an alarm
type qualifier (optional) compresses entries in the alarm list by removing all
but the latest state change for al alarms.  Conditions in the input are
logically ANDed.  If no input condition is given, all alarms are compressed.

Typical usage:

$ sudo ./snabb alarms compress lwaftr nic-v4 arp-resolution

See https://github.com/Igalia/snabb/blob/lwaftr/src/program/alarms/README.md
for full documentation.
