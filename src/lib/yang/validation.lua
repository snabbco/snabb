module(..., package.seeall)

function cardinality(kw, name, statements, haystack)
   for s, c in pairs(statements) do
      if (c[1] >= 1 and (not haystack[s])) or (#statements[s] < c[1] and #statements[s] > c[2]) then
	 if c[1] == c[2] then
	    error(("Expected %d %s statement(s) in %s:%s"):format(
		  c[1], s, kw, name))
	 else
	    error(
	       ("Expected between %d and %d of %s statement(s) in %s:%s"):format(
		  c[1], c[2], s, kw, name))
	 end
      end
   end
   return true
end

function validate_container(name, src)
   local cardinality = {config={0,1}, description={0,1}, presense={0,1},
			reference={0,1}, status={0,1}, when={0,1}}
   validate_cardinality("container", name, cardinality, src)
end

function validate_uses(name, src)
   local cardinality = {augment={0,1}, description={0,1}, refine={0,1},
			reference={0,1}, status={0,1}, when={0,1}}
   validate_cardinality("uses", name, cardinality, src)
end

function validate_notification(name, src)
   local cardinality = {description={0,1}, refernece={0,1}, status={0,1}}
   validate_cardinality("notification", name, cardinality, src)
end
