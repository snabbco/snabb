# Pfmatch

Pfmatch is a pattern-matching language for network packets, embedded in
Lua.  It is built on the well-known
[pflang](https://github.com/Igalia/pflua/blob/master/doc/pflang.md)
packet filtering language, using the fast
[pflua](https://github.com/Igalia/pflua/blob/master/README.md) compiler
for LuaJIT

Here's an example of a simple pfmatch program that just divides up
packets depending on whether they are UDP, TCP, or something else:

```lua
match {
   tcp => handle_tcp
   udp => handle_udp
   otherwise => handle_other
}
```

Unlike pflang filters written for such tools as `tcpdump`, a pfmatch
program can dispatch packets to multiple handlers, potentially
destructuring them along the way.  In contrast, a pflang filter can only
say "yes" or "no" on a packet.

Here's a more complicated example that passes all non-IP traffic, drops
all IP traffic that is not going to or coming from certain IP addresses,
and calls a handler on the rest of the traffic.

```lua
match {
   not ip => forward
   ip src 1.2.3.4 => incoming_ip
   ip dst 5.6.7.8 => outgoing_ip
   otherwise => drop
}
```

In the example above, the handlers after the arrows (`=>`) are Lua
functions.  If a handler matches (more on that later), it will be called
with two arguments: the packet data and the length.  You can pass more
arguments by specifying them after the handler.  For example, we could
pass the offset of the start of the IP header by using the [address-of
extension](https://github.com/Igalia/pflua/blob/master/doc/extensions.md):


```lua
match {
   not ip => forward
   ip src 1.2.3.4 => incoming_ip(&ip[0])
   ip dst 5.6.7.8 => outgoing_ip(&ip[0])
   otherwise => drop
}
```

Of course, with pflang you could just match all of the clauses in order:

```lua
not_ip = pf.compile('not ip')
incoming = pf.compile('ip src 1.2.3.4')
outgoing = pf.compile('ip dst 5.6.7.8')

function handle(packet, len)
   if not_ip(packet, len) then return forward(packet, len)
   elseif incoming(packet, len) then return incoming_ip(packet, len)
   elseif outgoing(packet, len) then return outgoing_ip(packet, len)
   else return drop(packet, len) end
end
```

But not only is this tedious, you don't get easy access to the packet
itself, and you're missing out on opportunities for optimization.  For
example, the if the packet fails the `not_ip` check, then we don't need
to check if it's an IP packet in the `incoming` check.  Compiling a
pfmatch program takes advantage of pflua's optimizer to produce optimal
code for all clauses in your match expression.

Pflua compiles the pfmatch expression above into the nice, short code
below:

```lua
local cast = require("ffi").cast
return function(self,P,length)
   if length < 14 then return self.forward(P, len) end
   if cast("uint16_t*", P+12)[0] ~= 8 then return self.forward(P, len) end
   if length < 34 then return self.drop(P, len) end
   if P[23] ~= 6 then return self.drop(P, len) end
   if cast("uint32_t*", P+26)[0] == 67305985 then return self.incoming_ip(P, len, 14) end
   if cast("uint32_t*", P+30)[0] == 134678021 then return self.outgoing_ip(P, len, 14) end
   return self.drop(P, len)
end
```

The result is a pretty good dispatcher.  There are always things to
improve, but it's likely that the compiled Lua above is better than what
you would write by hand, and it will continue to get better as pflua
improves.

When we write filtering code by hand, we inevitably end up writing
_interpreters_ for some kind of filtering language.  Using pflua and
pfmatch expressions, we can instead _compile_ a filter suited directly
for the problem at hand -- and while we're at it, we can forget about
worrying about pesky offsets and bit-shifts.

## Syntax

The grammar of the pfmatch language is below.

```
Program := 'match' Cond
Cond := '{' Clause... '}'
Clause := Test '=>' Dispatch [ClauseTerminator]
Test := 'otherwise' | LogicalExpression
ClauseTerminator := ',' | ';'
Dispatch := Call | Cond
Call := Identifier [ Args ]
Args := '(' [ ArithmeticExpression [ ',' ArithmeticExpression ] ] ')'
```

`LogicalExpression` and `ArithmeticExpression` are embedded productions
of pflang.  `otherwise` is a Test that always matches.

Comments are prefixed by `--` and continue to the end of the line.

## Semantics

Compiling a `Program` produces a `Matcher`.  A `Matcher` is a function
of three arguments: a handlers table, the packet data as a `uint8_t*`,
and the packet length in bytes.

Calling a `Matcher` will either result in a tail call to a member
function of the handlers table, or return `nil` if no dispatch matches.

A `Call` matches if all of the conditions necessary to evaluate the
arithmetic expressions in its arguments are true.  (For example, the
argument of `handle(ip[42])` is only valid if the packet is an IPv4
packet of a sufficient length.)

A `Cond` always matches; once you enter a `Cond`, no clause outside the
Cond will match.  If no clause in the `Cond` matches, the result is
`nil`.

A `Clause` matches if the `Test` on the left-hand-side of the arrow is
true.  If the right-hand-side is a `Call`, the conditions from the
`Args` (if any) are implicitly added to the `Test` on the left.  In this
way it's possible for the `Test` to be true but some condition from the
`Call` to be false, which causes the match to proceed with the next
`Clause`.

Unlike pflang, attempting to access out-of-bounds packet data merely
causes a clause not to match, instead of immediately aborting the
match.

## Using pfmatch

The interface to pfmatch is the `pf.match.compile` function.  In a
[Snabb](https://github.com/SnabbCo/snabbswitch) context, this might look
like:

```lua
local match = require('pf.match')

Filter = {}

function Filter:new(conf)
   local app = {}
   function app.forward(data, len)
      return len
   end
   function app.drop(data, len)
      -- Could truncate packet here and overwrite with ICMP error if
      -- wanted.
      return nil
   end
   function app.incoming_ip(data, len, ip_base)
      -- Munge the packet.  Return len if we resend the packet.
      return len
   end
   function app.outgoing_ip(data, len, ip_base)
      -- Munge the packet.  Return len if we resend the packet.
      return len
   end
   app.match = match.compile([[match {
      not ip => forward
      -- Drop fragmented packets.
      ip[6:2] & 0x3fff != 0 => drop
      ip src 1.2.3.4 => incoming_ip(&ip[0])
      ip dst 5.6.7.8 => outgoing_ip(&ip[0])
      otherwise => drop
   }]])
   return setmetatable(app, {__index=Filter})
end

function Filter:push ()
   local i, o = self.input.input, self.output.output
   while not link.empty() do
      local pkt = link.receive(i)
      local out_len = self:match(pkt.data, pkt.length)
      if out_len then
         pkt.length = out_len
         link.transmit(o, pkt)
      end
   end
end
```

`match.compile` takes two arguments: the string to compile, and an
optional table of options.  An option table may have the following
entries:

 * `dlt`: The link encapsulation, as libpcap would specify it.  Defaults
   to `"EN10MB"`.
 
 * `optimize`: Whether to optimize or not.  Defaults to `true`.

 * `source`: Whether to print out source code instead of returning a
   function.  Defaults to `false`.

 * `subst`: A table of substitutions for the program test.  For example
   if you didn't want to hard-code `1.2.3.4` as the incoming IP, you
   could instead write `$incoming_ip` and pass `{incoming_ip='1.2.3.4'}`
   as the subst table.  Defaults to `false`, indicating no
   substitutions.
