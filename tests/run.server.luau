local bench = require(script.Parent.benches["query.bench"])

task.wait(4)

for i = 1, 10000 do
	bench.Functions.ecs()
end

task.wait(0.1)

for i = 1, 10000 do
	bench.Functions.jecs()
end
