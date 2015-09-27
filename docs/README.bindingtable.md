Snabb-lwaftr alpha specifies binding tables in text files.

% cat binding.table 
{
 {'127:2:3:4:5:6:7:128', '178.79.150.233', 1, 100, '8:9:a:b:c:d:e:f'},
 {'127:11:12:13:14:15:16:128', '178.79.150.233', 101, 64000},
 {'127:22:33:44:55:66:77:128', '178.79.150.15', 5, 7000},
 {'127:24:35:46:57:68:79:128', '178.79.150.2', 7800, 7900, '1E:1:1:1:1:1:1:af'},
 {'127:14:25:36:47:58:69:128', '178.79.150.3', 4000, 5050, '1E:2:2:2:2:2:2:af'}
}

The format is a lua table, containing more Lua tables.
Each of these subtables (each shown on one line, above) has several parts.

As an example, look at the following entry:
{'127:24:35:46:57:68:79:128', '178.79.150.2', 7800, 7900, '1E:1:1:1:1:1:1:af'}

127:24:35:46:57:68:79:128 is the IPv6 address of a B4.

178.79.150.2 is the IPv4 address of the same B4 (not necessarily unique).

7800 and 7900 are the start and end of the port range on that IPv4 address
that are assigned to that B4.

1E:1:1:1:1:1:1:af is the IPv6 address associated with the lwaftr
for this binding table entry. It is optional, and if it is not specified,
the default configured lwaftr IPv6 address is used.
In this example binding table, the default is used for the first three entries,
and a custom address is specified for the last two entries.

Entries must be comma-separated. Having a comma after the last entry is optional.

The table is a lua data structure, not a line-oriented format, but keeping
one entry per line aids human readability.
