local bench = require(script.Parent.benches["query_archetypes.bench"])

task.wait(4)

debug.profilebegin "ECS ARCHETYPES"
for i = 1, 5 do
	bench.Functions.ecs()
end
debug.profileend()
print "ECS ARCHETYPES"

debug.profilebegin "JECS ARCHETYPES"
for i = 1, 5 do
	bench.Functions.jecs()
end
debug.profileend()
print "JECS ARCHETYPES"
