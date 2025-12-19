--!native
--!optimize 2

type u24 = number
type u53 = number
type ArchetypeId = number
type Colum = Array<any>

type Map<T, V> = { [T]: V }
type Array<T> = { T }

export type Entity<T = any> = { __T: T }
export type Component<T = any> = { __T: T }

export type Query<T...> = typeof(setmetatable(
	{} :: {
		archetypes: () -> { Archetype },
		with: (...Component) -> Query<T...>,
		without: (...Component) -> Query<T...>,
		iter: () -> () -> (Entity, T...),
	},
	{} :: {
		__iter: () -> () -> (Entity, T...),
	}
))

export type Archetype = {
	entities: { Entity },
	colums: Array<Colum>,
}

export type EntityRecord = {
	archetype: Archetype,
	archetype_row: number,
	dense: u24,
}

export type ComponentMap = {}

export type EntityIndex = {
	dense: Array<u53>,
	sparse: Map<u24, EntityRecord>,
	alive: number,
}

export type World = {}

local ENTITY_MASK = bit32.lshift(1, 24)
local GENERATION_MASK = bit32.lshift(1, 16)
local PAIR_OFFSET = 2 ^ 48

local HI_COMPONENT_ID = 256

local ECS_WILDCARD = HI_COMPONENT_ID + 1
local ECS_CHILDOF = HI_COMPONENT_ID + 2
local ECS_COMPONENT = HI_COMPONENT_ID + 3
local ECS_NAME = HI_COMPONENT_ID + 4
local ECS_REST = ECS_NAME + 1

local NULL_ARRAY = table.freeze {} :: { any }

local function IS_PAIR(e: number): boolean
	return e > PAIR_OFFSET
end

local function ENTITY_ID(e: u53): u24
	return e % ENTITY_MASK
end

local function ENTITY_GENERATION(e: u53): u24
	return e // ENTITY_MASK
end

local function APPEND_GENERATION(id: number, generation: number): u53
	return id + (generation * ENTITY_MASK)
end

local function INCREMENT_GENERATION(e: u53): u53
	if e > ENTITY_MASK then
		local id = ENTITY_ID(e)
		local generation = ENTITY_GENERATION(e)

		local next_gen = generation + 1
		if next_gen >= GENERATION_MASK then
			return id
		end

		return APPEND_GENERATION(id, next_gen)
	end
	return APPEND_GENERATION(e, 1)
end

local function GET_NEW_ENTITY_ID(index: EntityIndex): u53
	local dense_arr = index.dense
	local sparse_arr = index.sparse
	local alive = index.alive
	local count = #sparse_arr

	if alive >= count then
		local next_id = count + 1
		local new_record = { dense = next_id } :: EntityRecord
		table.insert(sparse_arr, new_record)
		table.insert(dense_arr, next_id)
		index.alive = next_id

		return next_id
	end

	alive += 1
	index.alive = alive
	return dense_arr[alive]
end

local function DELETE_ENTITY_ID(index: EntityIndex, id: u24)
	local dense_arr = index.dense
	local sparse_arr = index.sparse
	local alive = index.alive

	local dense_index = sparse_arr[id].dense
	if dense_index ~= alive then
		local last = dense_arr[alive]
		dense_arr[dense_index] = last
	end
	local new_generation = INCREMENT_GENERATION(dense_arr[dense_index])
	dense_arr[alive] = new_generation
	index.alive -= 1
end

local function world()
	local dense_arr = {}
	local sparse_arr = {}
	local component_count = 0

	local entity_index: EntityIndex = {
		dense = dense_arr,
		sparse = sparse_arr,
		alive = 0,
	}

	local function world_entity()
		return GET_NEW_ENTITY_ID(entity_index)
	end

	local function world_set() end

	local function world_add() end

	local function world_component()
		component_count += 1
		return component_count
	end

	-- query

	local function world_query()
		local function query_cached() end

		local function query_with() end

		local function query_without() end

		local function query_build() end

		local function query_archetypes() end

		return {
			query_cached = query_cached,
			query_with = query_with,
			query_without = query_without,
			query_build = query_build,
		}
	end
end

return {
	world = world,
}
