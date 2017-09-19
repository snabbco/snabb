module(..., package.seeall)

local alarms = require("lib.yang.alarms")

alarms.declare_alarm {
   [{resource='nic-v4', alarm_type_id='arp-resolution', alarm_type_qualifier=''}] = {
      perceived_severity = 'critical',
      alarm_text =
         'Make sure you can resolve external-interface.next-hop.ip address '..
         'manually.  If it cannot be resolved, consider setting the MAC '..
         'address of the next-hop directly.  To do it so, set '..
         'external-interface.next-hop.mac to the value of the MAC address.',
   },
}

alarms.declare_alarm {
   [{resource='nic-v6', alarm_type_id='ndp-resolution', alarm_type_qualifier=''}] = {
      perceived_severity = 'critical',
      alarm_text =
         'Make sure you can resolve internal-interface.next-hop.ip address '..
         'manually.  If it cannot be resolved, consider setting the MAC '..
         'address of the next-hop directly.  To do it so, set '..
         'internal-interface.next-hop.mac to the value of the MAC address.',
   },
}
