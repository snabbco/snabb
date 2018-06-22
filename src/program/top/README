Usage:
  top

Interactively display real-time performance statistics for running Snabb
instances on the current machine.

There are two views.  The default view is "interface view", which
focuses on traffic flowing through PCI interfaces.  It gives a summary
of receive and transmit throughput by interface, as well as receive
drops.

The status bar at the bottom of "snabb top" shows the available
commands.  In "interface view", the available commands are:

      q: quit "snabb top"
  SPACE: pause statistics collection
      t: switch to tree view

When paused, "snabb top" allows the user to access past statistics, if
available.  Multi-process snabb instances that use the "ptree" facility
automatically sample all counters and store historical counter values in
"round-robin database" (RRD) files, which are compatible with the
venerable "rrdtool" software package.  "snabb top" will read these RRD
files, if available, and show them when the user skims back in time.

The keys to seek through time, are, when in paused mode:

      {: go back by 60 seconds
      [: go back by 1 second
      ]: go forward by 1 second
      }: go forward by 60 seconds
  SPACE: resume statistics collection

As always, these commands are shown in the status bar when they are
available.  Unpausing "snabb top" will resume real-time display.

Pressing "t" when in interface view will switch to "tree view".  Tree
view is organized by Snabb instance, not by PCI devices.  Also, tree
view shows all counters, instead of just a summary.

In tree view, the user has the same possibility to pause time and skim
back and forwards, with the same key bindings.

As tree view shows all counters for all instances, it can be too much
information.  Sometimes it doesn't fit on a screen.  In that case,
"snabb top" offers two strategies: one, to limit yourself to a
particular Snabb instance by "focussing" that instance; and two, hiding
specific counter subtrees.

To focus an instance will show only that instance, hiding counters from
other Snabb instances.  Use the following keys to select which instance
to focus:

      >: Focus the next instance.
      <: Focus the previous instance.
      u: Cancel any current focus and go back to showing everything.

The "apps", "links", and "engine" subtrees can also take up a lot of
space.  There's good information there, but it's a bit much.  So, in
tree view, there are also keys to show and hide these subtrees.

      a: Hide (or show) apps/ subtrees.
      e: Hide (or show) engine/ subtrees.
      l: Hide (or show) link/ subtrees.

Again, all of these commands are shown in the status bar, when
available.

Finally, it's possible to use `snabb top` to read a snapshot of counters
taken from some other machine.  To take a sample of a machine's counters
and RRD files, do:

  ( cd /var/run; sudo tar cf /tmp/snabb-state-snapshot.tar.gz snabb )

Then copy /tmp/snabb-state-snapshot.tar.gz to a technician, who can unpack it:

  mkdir /tmp/forensics; cd /tmp/forensics; tar xvf snabb-state-snapshot.tar.gz

Then to investigate this snapshot:

  SNABB_SHM_ROOT=/tmp/forensics/snabb snabb top
