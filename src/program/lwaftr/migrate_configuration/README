Usage: migrate-configuration LWAFTR.CONF

Options:
  -h, --help                 Print usage information.
  -f, --from=VERSION         Specify version from which to migrate.

Migrate an old-style configuration and binding table to the new YANG
configuration.  LWAFTR.CONF should be the name of an old lwAFTR
configuration.  Available VERSION values are:

  legacy
    Configuration from pre-v3.0.0 lwAFTR.
  3.0.1
    lwAFTR versions where "container" nodes in schemas are missing
    corresponding nodes in the data unless "presence true" is
    specified.
  3.0.1.1
    lwAFTR development snapshot where "br" fields of softwires were
    0-based instead of 1-based.
  3.2.0
    lwAFTR versions where "br" fields were indexes for the "br-address"
    leaf-list instead of "br-address" IPv6 entries on the softwire.
  2017.07.01
    lwAFTR changes to multiprcoess configuration with the introduction of the
    instance list.

    This change will put place holders "IPv4 PCI Address" and "IPv6 PCI Address"
    where the external and internal PCI addresses of your NICs go respectively.
    This should be changed however when running the lwAFTR with only one
    instance defined a in-memory migration will occur on each run of the lwAFTR
    please refer to program/lwaftr/doc/running.md documentation for further
    information.

The default version is "legacy".

The resulting up-to-date configuration will be printed on standard
output, ready to be saved to a new file.
