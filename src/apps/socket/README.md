# RawSocket App (apps.socket.raw)

The `RawSocket` app is a bridge between Linux network interfaces (`eth0`,
`lo`, etc.) and a Snabb app network. Packets taken from the `rx` port are
transmitted over the selected interface. Packets received on the
interface are put on the `tx` port.

    DIAGRAM: RawSocket
              +-----------+
              |           |
      rx ---->* RawSocket *----> tx
              |           |
              +-----------+

## Configuration

The `RawSocket` app accepts a string as its configuration argument. The
string denotes the interface to bridge to.
