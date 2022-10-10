<!--- DO NOT EDIT, this file is generated via 
   sudo ./snabb snsh -e 'require("apps.ipfix.template").templatesMarkdown()' > apps/ipfix/README.templates.md
   --->
   
   ## IPFIX templates (apps.ipfix.template)

- `value=n` means the value stores up to *n* bytes.
- `tcpControlBitsReduced` are the `tcpControlBits` defined in [RFC 5102](https://datatracker.ietf.org/doc/html/rfc5102#section-5.8.7)
- The `dns*` keys are private enterprise extensions courtesy by SWITCH

| Name | Id | Type | Filter | Keys | Values | Required Maps
| --- | --- | --- | --- | --- | --- | ---
| v4 | 256 | v4 | ip | `sourceIPv4Address`, `destinationIPv4Address`, `protocolIdentifier`, `sourceTransportPort`, `destinationTransportPort` | `flowStartMilliseconds`, `flowEndMilliseconds`, `packetDeltaCount`, `octetDeltaCount`, `tcpControlBitsReduced` | 
| v4_DNS | 258 | v4 | ip and udp port 53 | `sourceIPv4Address`, `destinationIPv4Address`, `protocolIdentifier`, `sourceTransportPort`, `destinationTransportPort`, `dnsFlagsCodes`, `dnsQuestionCount`, `dnsAnswerCount`, `dnsQuestionName=64`, `dnsQuestionType`, `dnsQuestionClass`, `dnsAnswerName=64`, `dnsAnswerType`, `dnsAnswerClass`, `dnsAnswerTtl`, `dnsAnswerRdata=64`, `dnsAnswerRdataLen` | `flowStartMilliseconds`, `flowEndMilliseconds`, `packetDeltaCount`, `octetDeltaCount` | 
| v4_HTTP | 257 | v4 | ip and tcp dst port 80 | `sourceIPv4Address`, `destinationIPv4Address`, `protocolIdentifier`, `sourceTransportPort`, `destinationTransportPort` | `flowStartMilliseconds`, `flowEndMilliseconds`, `packetDeltaCount`, `octetDeltaCount`, `tcpControlBitsReduced`, `httpRequestMethod=8`, `httpRequestHost=32`, `httpRequestTarget=64` | 
| v4_extended | 1256 | v4 | ip | `sourceIPv4Address`, `destinationIPv4Address`, `protocolIdentifier`, `sourceTransportPort`, `destinationTransportPort` | `flowStartMilliseconds`, `flowEndMilliseconds`, `packetDeltaCount`, `octetDeltaCount`, `sourceMacAddress`, `postDestinationMacAddress`, `vlanId`, `ipClassOfService`, `bgpSourceAsNumber`, `bgpDestinationAsNumber`, `bgpPrevAdjacentAsNumber`, `bgpNextAdjacentAsNumber`, `tcpControlBitsReduced`, `icmpTypeCodeIPv4`, `ingressInterface`, `egressInterface` | `mac_to_as`, `vlan_to_ifindex`, `pfx4_to_as` 
| v6 | 512 | v6 | ip6 | `sourceIPv6Address`, `destinationIPv6Address`, `protocolIdentifier`, `sourceTransportPort`, `destinationTransportPort` | `flowStartMilliseconds`, `flowEndMilliseconds`, `packetDeltaCount`, `octetDeltaCount`, `tcpControlBitsReduced` | 
| v6_DNS | 514 | v6 | ip6 and udp port 53 | `sourceIPv6Address`, `destinationIPv6Address`, `protocolIdentifier`, `sourceTransportPort`, `destinationTransportPort`, `dnsFlagsCodes`, `dnsQuestionCount`, `dnsAnswerCount`, `dnsQuestionName=64`, `dnsQuestionType`, `dnsQuestionClass`, `dnsAnswerName=64`, `dnsAnswerType`, `dnsAnswerClass`, `dnsAnswerTtl`, `dnsAnswerRdata=64`, `dnsAnswerRdataLen` | `flowStartMilliseconds`, `flowEndMilliseconds`, `packetDeltaCount`, `octetDeltaCount` | 
| v6_HTTP | 513 | v6 | ip6 and tcp dst port 80 | `sourceIPv6Address`, `destinationIPv6Address`, `protocolIdentifier`, `sourceTransportPort`, `destinationTransportPort` | `flowStartMilliseconds`, `flowEndMilliseconds`, `packetDeltaCount`, `octetDeltaCount`, `tcpControlBitsReduced`, `httpRequestMethod=8`, `httpRequestHost=32`, `httpRequestTarget=64` | 
| v6_extended | 1512 | v6 | ip6 | `sourceIPv6Address`, `destinationIPv6Address`, `protocolIdentifier`, `sourceTransportPort`, `destinationTransportPort` | `flowStartMilliseconds`, `flowEndMilliseconds`, `packetDeltaCount`, `octetDeltaCount`, `sourceMacAddress`, `postDestinationMacAddress`, `vlanId`, `ipClassOfService`, `bgpSourceAsNumber`, `bgpDestinationAsNumber`, `bgpNextAdjacentAsNumber`, `bgpPrevAdjacentAsNumber`, `tcpControlBitsReduced`, `icmpTypeCodeIPv6`, `ingressInterface`, `egressInterface` | `mac_to_as`, `vlan_to_ifindex`, `pfx6_to_as` 
