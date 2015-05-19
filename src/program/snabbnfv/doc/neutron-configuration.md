# Snabb NFV Configuration with Neutron

(See [Snabb NFV Architecture](architecture.md) and
[Installation](installation.md) for background.)

## Network node

Install and enable the Snabb NFV mechanism driver for Neutron.

## Database node

Install the
[`snabb-sync-master`](https://github.com/SnabbCo/snabbswitch/blob/master/src/designs/neutron/neutron-sync-master)
script. This daemon will snapshot the Neutron MySQL tables and make them
available for sync. The script reads its configuration from the following
environment variables:

| Variable            | Default | Meaning |
| ------------------- | ------- | ------- |
| `DB_USER`           || MySQL database username for accessing Neutron tables|
| `DB_PASSWORD`       || MySQL database password.
| `DB_DUMP_PATH`      || Path where the database sync snapshot should be created.    NOTE: Must be writable by the mysql unix user.
| `DB_HOST`           |`localhost`| MySQL database hostname.
| `DB_PORT`           |`3306`| MySQL database port number.
| `DB_NEUTRON`        |`neutron_ml2`| MySQL database name containing Neutron configuration.
| `DB_NEUTRON_TABLES` |(all relevant)|MySQL tables to synchronized (space-separated list).
| `SYNC_LISTEN_HOST`  |`localhost`| Host/address for this sync master daemon to listen on.
| `SYNC_LISTEN_PORT`  |`9418`|Port number for this sync master daemon to listen on.

Example:

```
DB_USER=mysql
DB_PASSWORD=mysql
DB_DUMP_PATH=/var/snabbswitch/sync-master/neutron
SYNC_LISTEN_HOST=syncmasterhost
```
## Compute node

First ensure that the [Compute node requirements](compute-node-requirements.md)
for hardware and kernel configuration are met.

### Sync agent

Install the [`neutron-sync-agent`](https://github.com/SnabbCo/snabbswitch/blob/master/src/designs/neutron/neutron-sync-agent).
This daemon will download updated Neutron database table snapshots and
translate them into updated configuration files for the local traffic
daemons (below). The sync agent reads its configuration from the
following environment variables:

| Variable            | Default | Meaning |
| ------------------- | ------- | ------- |
| `NEUTRON_DIR`       | `/var/snabbswitch/neutron` | Directory to store Neutron database snapshots. |
| `SNABB_DIR`         | `/var/snabbswitch/networks` | Directory to store configuration files for traffic processes. |
| `NEUTRON2SNABB`     | | Path to the `neutron2snabb` helper program. This program performs the translation of the Neutron database into the relevant configuration file for each traffic process. |
| `SYNC_HOST`         | | Sync master daemon host address. |
| `SYNC_PATH`         | | Path name of the configuration on the SYNC server. (Same as basename of `DB_DUMP_PATH` on the sync master.) |
| `SYNC_INTERVAL`     | 1 (second) | Time interval between synchronization checks (in seconds). |

Example:

```
SYNC_HOST=syncmasterhost
SYNC_PATH=neutron
NEUTRON2SNABB=neutron2snabb # Find with PATH
```

### Traffic processes

Setup one traffic process for each physical port:

```
snabbnfv-traffic 0000:07:00.0 \
                 /var/snabbswitch/network/port0 \
                 /var/snabbswitch/vhost-user-sockets
```

Each traffic process should be started using _numactl_ to be pinned to a
particular NUMA node and CPU. We define a file that describes the mapping
of PCI addresses to NUMA nodes in CPU. The file is in
_/etc/default/snabb-nfv-traffic_. An example content of the file

```
#<PCI-address> <NUMA node> <CPU affinity>
0000:01:00.0   0           0
0000:03:00.0   0           2
0000:05:00.0   0           4
0000:82:00.0   1           12
0000:84:00.0   1           14
0000:86:00.0   1           16
```
