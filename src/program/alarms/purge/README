Usage: snabb alarms purge [OPTION]... ID STATE
Adds a new operator-state in an alarm.

Available options:
  -s, --schema SCHEMA           YANG data interface to request.
  -r, --revision REVISION       Require a specific revision of the YANG module.
  -f, --format                  Selects output format (yang or xpath). Default: yang.
      --print-default           Forces print out of default values.
  -h, --help                    Displays this message.

Filtering options:
  --by-severity                 [severity-spec:value].
                                  Severity spec: 'is', 'below', 'above'.
                                  Value: 'indeterminate', 'minor', 'warning', 'major', 'critical'.
  --by-older-than               [age-spec:value].
                                  Age spec: 'seconds', 'minutes', 'hours', 'days', 'weeks'.
                                  Value: integer.
  --by-operator-state-filter    [state:user].
                                  State (optional): 'none', 'ack', 'closed', 'shelved', 'un-shelved'.
                                  User (optional): string.

Given an instance identifier and an alarm state ('any', 'cleared' or 'not-cleared')
remove all alarms that match the filtering options.

Typical usage:

$ sudo ./snabb alarms purge lwaftr any
$ sudo ./snabb alarms purge --by-severity above:minor lwaftr any
$ sudo ./snabb alarms purge --by-older-than minutes:5 lwaftr cleared

See https://github.com/Igalia/snabb/blob/lwaftr/src/program/alarms/README.md
for full documentation.
