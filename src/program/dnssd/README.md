DNS-SD
------

Implement DNS Service Discovery.

DNS-SD sends a local-link request to the broadcast address 224.0.0.251 port 5353.  The default query is "_service.dns-sd._tcp.local", unless a different query is set in the argument list. If there are any devices or services listening to Multicast DNS request in the network, they will announce their domain-name to 224.0.0.251.  The app listens to mDNS response and prints out A, PTR, SRV and TXT records.

Example:

```
$ sudo ./snabb dnssd --interface wlan0
Capturing packets from interface 'wlan0'
PTR: (name: _services._dns-sd._udp.local; domain-name: _googlecast._tcp)
PTR: (name: _services._dns-sd._udp.local; domain-name: _googlezone._tcp)
PTR: (name: _services._dns-sd._udp.local; domain-name: _spotify-connect._tcp)
```

Further information of _googlecast._tcp.local:

```
$ sudo ./snabb dnssd --interface wlan0 _googlecast._tcp.local
Capturing packets from interface 'wlan0'
Capturing packets from interface 'wlp3s0'
{name: _googlecast._tcp.local; domain_name: Google-Home-65b8d37105107f33691010baf74b84102f103363}
{id=65b8d37105107f33691010baf74b84102f103363;cd=b51a5e1cd4953a7b9f2f49622fdaf97b;rm=104e6110afdaf491f5;ve=05;md=Google Home;ic=/setup/icon.png;fn=Home;ca=2052;st=0;bs=5d3101063a3cdb;nf=1;rs=}
{target: eb9910bed-52310-94a3-b371-c6f3bf10b19e2; port: 8009}
{address: 192.168.86.61}
{name: _googlecast._tcp.local; domain_name: Chromecast-Audio-7cc91fd53d3c64e425b3b86a5107c11074}
{id=7cc91fd53d3c64e425b3b86a5107c11074;cd=224708C2E61AED24676383796588FF7E;rm=8F2EE2757C6626CC;ve=05;md=Chromecast Audio;ic=/setup/icon.png;fn=Jukebox;ca=2052;st=0;bs=4f4105104dcf5a;nf=1;rs=}
{target: 4742e2a5-a6bd-e137-2fa3-1215425bf2f6; port: 8009}
{address: 192.168.86.57}
{name: _googlecast._tcp.local; domain_name: Google-Cast-Group-63419dcd2372412882ac2762a2c58706}
{id=3410642cb-aad1-210210-f148-910fbdf3cdfa2;cd=3410642cb-aad1-210210-f148-910fbdf3cdfa2;rm=8F2EE2757C6626CC;ve=05;md=Google Cast Group;ic=/setup/icon.png;fn=Batcave;ca=2084;st=0;bs=4f4105104dcf5a;nf=1;rs=}
{target: 4742e2a5-a6bd-e137-2fa3-1215425bf2f6; port: 42238}
{address: 192.168.86.57}
```
