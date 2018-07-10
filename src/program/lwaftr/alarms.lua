module(..., package.seeall)

alarms = {
   [{alarm_type_id='arp-resolution'}] = {
      perceived_severity = 'critical',
      alarm_text =
         'Make sure you can resolve external-interface.next-hop.ip address '..
         'manually.  If it cannot be resolved, consider setting the MAC '..
         'address of the next-hop directly.  To do it so, set '..
         'external-interface.next-hop.mac to the value of the MAC address.',
   },
   [{alarm_type_id='ndp-resolution'}] = {
      perceived_severity = 'critical',
      alarm_text =
         'Make sure you can resolve internal-interface.next-hop.ip address '..
         'manually.  If it cannot be resolved, consider setting the MAC '..
         'address of the next-hop directly.  To do it so, set '..
         'internal-interface.next-hop.mac to the value of the MAC address.',
   },
}
