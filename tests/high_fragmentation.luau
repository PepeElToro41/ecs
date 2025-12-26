--!optimize 2
--!native

local testkit = require "./testkit"
local BENCH, START = testkit.benchmark()
local function TITLE(title: string)
	print()
	print(testkit.color.white(title))
end

local jecs = require "./jecs"
local ecs = require "../src/ecs"

type i53 = number

local N = 2 ^ 17

local SEED = os.clock()

do
	TITLE(testkit.color.white_underline "ECS query")
	local ecs_world = ecs.world()
	math.randomseed(SEED)

	local function flip()
		return math.random() >= 0.15
	end

	do
		TITLE "one component in common"

		local function view_bench(
			world: ecs.World,
			A: ecs.Entity,
			B: ecs.Entity,
			C: ecs.Entity,
			D: ecs.Entity,
			E: ecs.Entity,
			F: ecs.Entity,
			G: ecs.Entity,
			H: ecs.Entity
		)
			BENCH("1 component", function()
				for _ in world.query(A).iter() do
				end
			end)

			BENCH("2 component", function()
				for _ in world.query(B, A).iter() do
				end
			end)

			BENCH("4 component", function()
				for _ in world.query(D, C, B, A).iter() do
				end
			end)

			BENCH("8 component", function()
				for _ in world.query(H, G, F, E, D, C, B, A).iter() do
				end
			end)

			local e = world.entity()
			world.set(e, A, true)
			world.set(e, B, true)
			world.set(e, C, true)
			world.set(e, D, true)
			world.set(e, E, true)
			world.set(e, F, true)
			world.set(e, G, true)
			world.set(e, H, true)

			BENCH("Update Data", function()
				for _ = 1, 100 do
					world.set(e, A, false)
					world.set(e, B, false)
					world.set(e, C, false)
					world.set(e, D, false)
					world.set(e, E, false)
					world.set(e, F, false)
					world.set(e, G, false)
					world.set(e, H, false)
				end
			end)
		end

		local D1 = ecs_world.component()
		local D2 = ecs_world.component()
		local D3 = ecs_world.component()
		local D4 = ecs_world.component()
		local D5 = ecs_world.component()
		local D6 = ecs_world.component()
		local D7 = ecs_world.component()
		local D8 = ecs_world.component()

		local function flip()
			return math.random() >= 0.15
		end

		local added = 0
		local archetypes = {}
		for i = 1, 2 ^ 16 - 2 do
			local entity = ecs_world.entity()

			local combination = ""

			if flip() then
				combination ..= "B"
				ecs_world.set(entity, D2, { value = true })
			end
			if flip() then
				combination ..= "C"
				ecs_world.set(entity, D3, { value = true })
			end
			if flip() then
				combination ..= "D"
				ecs_world.set(entity, D4, { value = true })
			end
			if flip() then
				combination ..= "E"
				ecs_world.set(entity, D5, { value = true })
			end
			if flip() then
				combination ..= "F"
				ecs_world.set(entity, D6, { value = true })
			end
			if flip() then
				combination ..= "G"
				ecs_world.set(entity, D7, { value = true })
			end
			if flip() then
				combination ..= "H"
				ecs_world.set(entity, D8, { value = true })
			end

			if #combination == 7 then
				added += 1
				ecs_world.set(entity, D1, { value = true })
			end
			archetypes[combination] = true
		end

		local a = 0
		for _ in archetypes do
			a += 1
		end

		view_bench(ecs_world, D1, D2, D3, D4, D5, D6, D7, D8)
	end

	do
		local function view_bench(n: number)
			BENCH(`matching {n} entities per archetype`, function()
				local world = ecs.world()

				local A = world.component()
				local B = world.component()
				local C = world.component()
				local D = world.component()

				for i = 1, N, n do
					local ct = world.entity()
					for j = 1, n do
						local id = world.entity()
						if flip() then
							world.set(id, A, true)
						end
						if flip() then
							world.set(id, B, true)
						end
						if flip() then
							world.set(id, C, true)
						end
						if flip() then
							world.set(id, D, true)
						end
						world.add(id, ct)
					end
				end

				local q = world.query(A, B).without(C, D)
				START()
				for id in q.iter() do
				end
			end)
		end

		for i = 13, 0, -1 do
			view_bench(2 ^ i)
		end
	end
end

do
	TITLE(testkit.color.white_underline "Jecs query")
	local jecs_world = jecs.world()
	math.randomseed(SEED)

	local function flip()
		return math.random() >= 0.15
	end

	do
		TITLE "one component in common"

		local function view_bench(
			world: jecs.World,
			A: jecs.Component,
			B: jecs.Component,
			C: jecs.Component,
			D: jecs.Component,
			E: jecs.Component,
			F: jecs.Component,
			G: jecs.Component,
			H: jecs.Component
		)
			BENCH("1 component", function()
				for _ in world:query(A) do
				end
			end)

			BENCH("2 component", function()
				for _ in world:query(B, A) do
				end
			end)

			BENCH("4 component", function()
				for _ in world:query(D, C, B, A) do
				end
			end)

			BENCH("8 component", function()
				for _ in world:query(H, G, F, E, D, C, B, A) do
				end
			end)

			local e = world:entity()
			world:set(e, A, true)
			world:set(e, B, true)
			world:set(e, C, true)
			world:set(e, D, true)
			world:set(e, E, true)
			world:set(e, F, true)
			world:set(e, G, true)
			world:set(e, H, true)

			BENCH("Update Data", function()
				for _ = 1, 100 do
					world:set(e, A, false)
					world:set(e, B, false)
					world:set(e, C, false)
					world:set(e, D, false)
					world:set(e, E, false)
					world:set(e, F, false)
					world:set(e, G, false)
					world:set(e, H, false)
				end
			end)
		end

		local D1 = jecs_world:component()
		local D2 = jecs_world:component()
		local D3 = jecs_world:component()
		local D4 = jecs_world:component()
		local D5 = jecs_world:component()
		local D6 = jecs_world:component()
		local D7 = jecs_world:component()
		local D8 = jecs_world:component()

		local added = 0
		local archetypes = {}
		for i = 1, 2 ^ 16 - 2 do
			local entity = jecs_world:entity()

			local combination = ""

			if flip() then
				combination ..= "B"
				jecs_world:set(entity, D2, { value = true })
			end
			if flip() then
				combination ..= "C"
				jecs_world:set(entity, D3, { value = true })
			end
			if flip() then
				combination ..= "D"
				jecs_world:set(entity, D4, { value = true })
			end
			if flip() then
				combination ..= "E"
				jecs_world:set(entity, D5, { value = true })
			end
			if flip() then
				combination ..= "F"
				jecs_world:set(entity, D6, { value = true })
			end
			if flip() then
				combination ..= "G"
				jecs_world:set(entity, D7, { value = true })
			end
			if flip() then
				combination ..= "H"
				jecs_world:set(entity, D8, { value = true })
			end

			if #combination == 7 then
				added += 1
				jecs_world:set(entity, D1, { value = true })
			end
			archetypes[combination] = true
		end

		local a = 0
		for _ in archetypes do
			a += 1
		end

		view_bench(jecs_world, D1, D2, D3, D4, D5, D6, D7, D8)
	end

	local function view_bench(n: number)
		BENCH(`{n} entities per archetype`, function()
			local world = jecs.world()

			local A = world:component()
			local B = world:component()
			local C = world:component()
			local D = world:component()

			for i = 1, N, n do
				local ct = world:entity()
				for j = 1, n do
					local id = world:entity()
					if flip() then
						world:set(id, A, true)
					end
					if flip() then
						world:set(id, B, true)
					end
					if flip() then
						world:set(id, C, true)
					end
					if flip() then
						world:set(id, D, true)
					end
					world:add(id, ct)
				end
			end

			local q = world:query(A, B):without(C, D)
			START()
			for id in q:iter() do
			end
		end)
	end

	for i = 13, 0, -1 do
		view_bench(2 ^ i)
	end
end
