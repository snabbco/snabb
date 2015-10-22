return [[
Usage: lisper --control SOCK --punt-interface IF --network-device IPv6

  -c SOCK,  --control SOCK          Control socket
  -p IF,    --punt-interface IF     Punt interface
  -n IF,    --network-device IF     Network device
  -i IPv6,  --local-ip IPv6         Local IP address
  -m MAC,   --local-mac MAC         Local MAC address
  -N IPv6,  --next-hop IPv6         Next hop address
  -h,       --help                  Print usage information

Snabb Switch extension to support interfacing with an external control plane
for establishing L2TPv3 tunnels. The extension is suitable for use with
an external LISP (RFC 6830) controller.

Examples:

  snabb lisper --control ctrl.socket --punt-interface veth0 \
    --network-device 01:00.0 --local-ip 10.0.0.1 --local-mac deadbeefdeadbeef

]]
