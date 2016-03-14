### `pmu`: CPU Performance Monitoring Unit counters

The CPU's PMU (Performance Monitoring Unit) collects information about
specific *performance events* such as cache misses, branch
mispredictions, and utilization of internal CPU resources like
execution units. This module provides an API for counting events with
the PMU.

Hundreds of low-level counters are available. The exact list
depends on CPU model. See pmu_cpu.lua for our definitions.

#### High-level interface

— Function **is_available**

If the PMU hardware is available then return true. Otherwise return
two values: false and a string briefly explaining why. (Cooperation
from the Linux kernel is required to acess the PMU.)

— Function **profile** *function* *[event_list]* *[aux]*

Call *function*, return the result, and print a human-readable report of the performance events that were counted during execution.

— Function **measure** *function* *[event_list]*

Call *function* and return two values: the result and a table of performance event counter tallies.

#### Low-level interface

— Function **setup** *event_list*

Setup the hardware performance counters to track a given list of
events (in addition to the built-in fixed-function counters).
  
 Each event is a Lua string pattern. This could be a full event name:

```
mem_load_uops_retired.l1_hit
```

or a more general pattern that matches several counters:
```
mem_load.*l._hit
```

Return the number of overflowed counters that could not be tracked due
to hardware constraints. These will be the last counters in the list.

Example:

```
setup({"uops_issued.any",
       "uops_retired.all",
       "br_inst_retired.conditional",
       "br_misp_retired.all_branches"}) => 0
```

— Function **new_counter_set**

Return a `counter_set` object that can be used for accumulating
events. The counter_set will be valid only until the next call to
setup().

— Function **switch_to** *counter_set*

Switch to a new set of counters to accumulate events in. Has the
side-effect of committing the current accumulators to the
previous record.

If *counter_set* is nil then do not accumulate events.

— Function **to_table** *counter_set*

Return a table containing the values accumulated in *counter_set*.

Example:

```
to_table(cs) =>
  {
   -- Fixed-function counters
   instructions                 = 133973703,
   cycles                       = 663011188,
   ref-cycles                   = 664029720,
   -- General purpose counters selected with setup()
   uops_issued.any              = 106860997,
   uops_retired.all             = 106844204,
   br_inst_retired.conditional  =  26702830,
   br_misp_retired.all_branches =       419
  }
```

— Function **report** *counter_set* *[aux]*

Print a textual report on the values accumulated in a counter set.
Optionally include auxiliary application-level counters. The ratio of
each event to each auxiliary counter is also reported.

Example:
```
report(my_counter_set, {packet = 26700000, breath = 208593})
```
prints output approximately like:
```
EVENT                                   TOTAL     /packet     /breath
instructions                      133,973,703       5.000     642.000
cycles                            663,011,188      24.000    3178.000
ref-cycles                        664,029,720      24.000    3183.000
uops_issued.any                   106,860,997       4.000     512.000
uops_retired.all                  106,844,204       4.000     512.000
br_inst_retired.conditional        26,702,830       1.000     128.000
br_misp_retired.all_branches              419       0.000       0.000
packet                             26,700,000       1.000     128.000
breath                                208,593       0.008       1.000
```
