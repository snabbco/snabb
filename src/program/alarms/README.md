# Alarm management

When you put a network function into production, you will want to
monitor it so that you are sure it is running correctly.  For example,
if you are using the [ARP app](../../apps/ipv4/README.md) to determine
the Ethernet address of the next-hop host, you will want to know if the
ARP app fails to determine this address.  Or perhaps if you are using
the [IPv4 reassembler app](../../apps/ipv4/README.md), you would like to
know when the incoming fragment rate exceeds a threshold.

Both of these cases are examples of *alarms*.  An *alarm* in Snabb
signals an undesirable state that requires corrective action.  Snabb
apps can declare the set of alarms that they might raise, and according
to operational conditions can either raise or clear those alarms as
appropriate.

Of course, a Snabb app is just a sub-component of a Snabb network
function; it is an implementation detail.  An operator needs to know the
set of alarms that a Snabb network function might raise.  The operator
also needs to know the status of those alarms, and indeed the history of
those alarm statuses: when did they change state?  Finally, the operator
needs to be able to perform some book-keeping, marking some alarms as
closed or ignored, and deleting alarm history.  For all of these
purposes, `snabb alarms` is here.

Note that Snabb's alarm facility is modelled on the `ietf-alarms`
internet draft.  For more details, see
https://tools.ietf.org/html/draft-vallin-netmod-alarm-module-02.

## Before starting with alarms

The Snabb alarms facility is built on the same interfaces that [`snabb
config`](../config/README.md) uses.  Only some Snabb data-planes have
enabled `snabb config`; currently in fact it's only the
[lwAFTR](../lwaftr/doc/README.md).  If you are implementing a data-plane
and want to add support for alarms, first you add support for `snabb
config` by using the `lib.ptree` process tree facility.  See the
[`lib.ptree` documentation](../../lib/ptree/README.md) for more.

## Resource state

In the terminology of the [`ietf-alarms` YANG
schema](../../lib/yang/ietf-alarms.yang), the *resource* is the network
function.  It supports some set of alarms.  If the resource detects an
exceptional situation needing corrective action, it raises an alarm.
Once the resource detects that the situation is no longer present, it
clears the alarm.

First, let's start a network function that supports alarms: a simple
lwAFTR synthetic benchmark that doesn't use any hardware devices.

```
$ sudo ./snabb lwaftr bench --name test \
    program/lwaftr/tests/data/icmp_on_fail.conf \
    program/lwaftr/tests/benchdata/ipv{4,6}-0550.pcap
```

This lwAFTR instance is running with the name `test`.  To get a list of
what alarms the `test` instance supports supports, use [`snabb alarms
get-state`](./get-state/README).

```
$ snabb alarms get-state test /
alarms {
  alarm-inventory {
    alarm-type {
      alarm-type-id arp-resolution;
      alarm-type-qualifier '';
      description "ARP app cannot resolve next-hop IP address";
      has-clear true;
      resource 15797;
    }
    alarm-type {
      alarm-type-id bad-ipv6-softwires-matches;
      alarm-type-qualifier '';
      description "IPv6 source address matches no softwire";
      has-clear true;
      resource 15797;
    }
    alarm-type {
      alarm-type-id bad-ipv4-softwires-matches;
      alarm-type-qualifier '';
      description "IPv4 destination address and port matches no softwire";
      has-clear true;
      resource 15797;
    }
    alarm-type {
      alarm-type-id ndp-resolution;
      alarm-type-qualifier '';
      description "NDP app cannot resolve next-hop IPv6 address";
      has-clear true;
      resource 15797;
    }
  }
  alarm-list {
    number-of-alarms 0;
  }
  summary {
  }
}
```

The `/alarms/alarm-inventory` block indicates that there are four
possible alarms that this network function might raise.  The empty
`/alarms/alarm-list` block shows that no alarms have ever been raised;
if they had, the history of when these alarms were raised and cleared
over time would appear here.  Finally, `/alarms/summary` shows the
current alarms that are raised; in the current case, an empty set.

The `resource` entries are unique identifiers of sub-components of a
Snabb instance.  Specifically in the case of a multi-process Snabb,
usually the `resource` components denote separate process identifiers,
though sometimes they can denote separate apps of the same kind within a
process.

## Operator actions

On the one side, Snabb's alarm facility models the state of the
"resource": of the network function itself.  Alarms are a little to-do
list for an operator, though, so the alarms facility also has a
component that keeps track of operator actions.

### Lifecycle management: Marking alarms as done

The [`snabb alarms set-operator state`](./set-operator-state/README)
tool allows an operator to mark an alarm's state.  Available states are:

 * `none`: Initial alarm operator state.  The alarm is not being taken
   care of.
 * `ack`: The alarm is being taken care of, but is not yet resolved.
 * `closed`: Corrective action was successfully undertaken to resolve
   the alarm.
 * `shelved`: The alarm has been ignored.  The alarm will be listed
   under `/alarms/shelved-alarms` instead of under
   `/alarms/alarm-list`.
 * `un-shelved`:  The alarm has been un-ignored, and is back to
   `/alarms/alarm-list`.

The command takes as arguments the resource and the alarm type ID.

```
$ snabb alarms set-operator-state INSTANCE RESOURCE TYPE STATE
```

The *type* may also have a qualifier appended to it after a slash (`/`),
as in `TYPE/QUALIFIER`.  By default there is no qualifier.

Therefore, to ignore an ARP resolution warning on resource 12345 on
Snabb instance `test`, you might do:

```
$ snabb alarms set-operator-state test 12345 arp-resolution shelved
```

### Purge: Delete alarms

When you've marked an alarm as `closed` and you have seen after some
time that things are OK, probably you don't want to see that alarm any
more.  Yet, it still shows up in `/alarms/alarm-list` in the `closed`
state.  The [`snabb alarms purge`](./purge/README) tool exists for this
purpose.  For example:

```
$ snabb alarms purge --by-older-than=5:minutes test all
```

See [`snabb alarms purge --help`](./purge/README) for more information.

### Compress: Getting rid of irrelevant history

Finally, it may be that you want to just delete state changes that don't
describe the current state.  Maybe there was an alarm that was
signalled, you fixed, then it's signalled again.  We want to keep the
current state, but suppress old irrelevant state transitions.  For that,
there is `snabb alarms compress`, which works like `snabb alarms
set-operator-state`:

```
$ snabb alarms compress test 12345 arp-resolution
```

See [`snabb alarms compress --help`](./compress/README) for more information.

### Notifications

Alarm notification are sent by a leader under certain circumstances. There
are 3 types of alarm notifications:

- Alarm notification: sent to report a newly raised alarm, a cleared alarm
or changing the text and/or severity of an existing alarm.

- Alarm inventory changed notification: sent to report that the list of
possible alarms has changed.  This can happen when for example if a new
software module is installed, or a new physical card is inserted.

- Operator action notification: sent to report that an operator acted upon an
alarm.

To listen to these notifications open a connection to a Snabb instance using
the subprogram `alarms listen`.

## How does it work?

The Snabb instance itself should be running in *multi-process mode*,
whereby there is one manager process that shepherds a number of worker
processes.  The workers perform the actual data-plane functionality, are
typically bound to reserved CPU and NUMA nodes, and have soft-real-time
constraints.  The manager process however doesn't have much to do; it
just coordinates the workers.  Workers tell the manager process about
the alarms that they support, and then also signal the manager process
when an alarm changes state.  The manager process collects all of the
alarms and makes them available to `snabb alarms`, over a socket.  See
the [`lib.ptree` documentation](../../lib/ptree/README.md) for full
details.
