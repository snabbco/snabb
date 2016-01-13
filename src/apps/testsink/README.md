# (apps.testsink.testsink)

## The TestSink app
The `TestSink` app is used to aid unit testing. It takes 2 inputs `rx` and `comparator`.
Each packet from `rx` is compared with each packet from `comparator`, when packets differ it's 
logged to `app.errs`. Each packet from `comparator` must have a corresponding packet from `rx`.
`fuzzy` controls whether each packet from `rx` must have a corresponding pcaket from `comparator`.
When `fuzzy = false` it **MUST**, when `fuzzy = true` it **MAY** not. Fuzzy matching is useful when 
'uncontrolled' traffic may be seen, for example IPv6 ND packets when testing pcap eplays on a 
linux Tap device.


```
config.app(c, "tsink", testsink.TestSink, { fuzzy = boolean })
-- tsink.rx and tsink.comparator are the associated links
-- engine.app_table.tsink.errs is a table containing errors
```

## A simple test harness
`ok, errs = TestSink.harness(app, inputpcaps, comparatorpcaps)`
* `app` is an app such as `basic_apps.Tee` or `testsink.TestSink`
* `inputpcaps` is a table of app input names as keys and pcaps as values
* `comparatorpcaps` is a table of app output names as keys and pcaps as values
* A PcapReader is created to feed each input of `app` from `inputpcaps`
* A TestSink is created to compare each app output with the associated pcap from `comparatorpcaps`

The following tests the Tee app
```
   local tee = require("apps.basic.basic_apps").Tee
   local ok, res = harness(tee, { input = "apps/testsink/selftest1.pcap" }, 
      { 
         out = "apps/testsink/selftest1.pcap", 
         out2 = "apps/testsink/selftest1.pcap" 
      })
   assert(ok)
   assert(#res.out == 0)
   assert(#res.out2 == 0)
```