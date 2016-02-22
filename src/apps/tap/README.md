# Linux tap app (apps.tap.tap)

The `Tap` app is used to interact with a linux tap device. 

```
config.app(c, "tap", tap.Tap, "Tap345")
--- tap.input and tap.output are the associated links
```

The Tap device should exist with any customisation already applied.
```
ip tuntap add Tap345 mode tap
ip link set up dev Tap345
ip link set address 02:01:02:03:04:08 dev Tap0
```