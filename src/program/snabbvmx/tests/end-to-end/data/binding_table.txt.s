psid_map {
  10.10.0.0  {psid_length=6, shift=10}
  10.10.0.1  {psid_length=6, shift=10}
  10.10.0.10 {psid_length=6, shift=10}
}
br_addresses {
  2a02:587:f700::100,
}
softwires {
  { ipv4=10.10.0.0, psid=1, b4=2a02:587:f710::400 }
  { ipv4=10.10.0.0, psid=2, b4=2a02:587:f710::410 }
  { ipv4=10.10.0.0, psid=3, b4=2a02:587:f710::420 }
  { ipv4=10.10.0.0, psid=4, b4=2a02:587:f710::430 }
}
