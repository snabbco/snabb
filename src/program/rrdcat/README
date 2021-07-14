Usage:
  rrdcat [OPTIONS] <db>

  -h, --help
                             Print usage information.
  -s, --source
                             Select source.
  -i, --interval
                             Select interval.
  -l, --list-contents
                             List contents of <rrd>.

Summarize the data recorded in RRD <db> with a normalized ASCII plot. Skips
(with indication) over zero or unknown data rows. Select CDP source and
interval with --source and --interval respectively; list the available sources
and intervals and other metadata with --list-contents.

Legend:
             /---(timestamp)
            v
  Mon Sep 23 18:41:30 2019 ? <---(unknown data)
                           ?
                           ?
  ... <---(discontinuity)
  Tue Sep 24 17:48:00 2019 [        min:- avg:- max:- <---(zero data)
                           [        min:- avg:- max:-
                           [        min:- avg:- max:-
                           [a       min:- avg:1K max:4K <---(abs. values)
  Tue Sep 24 17:48:30 2019 [ na--m  min:9K avg:21K max:42K
                           [  nam   min:20K avg:28K max:40K
                           [n-a---m min:3K avg:19K max:53K
                            ^ ^   ^
                            | |   \---(maximum)
                            | \---(avgerage)
                            \---(minimum)

Examples:
  snabb rrdcat --interval 30 rxdrop.rrd
  snabb rrdcat --list-contents rxdrop.rrd
