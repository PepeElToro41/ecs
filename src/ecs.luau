--!native
--!optimize 2

type u24 = number
type u53 = number
type ArchetypeId = number
type Bitset = number
type Column = Array<any>

type Map<T, V> = { [T]: V }
type Array<T> = { T }

export type Entity<T = any> = { __T: T }
export type Component<T = any> = { __T: T }

type ArchetypeChangedHook = (source: Archetype, destination: Archetype) -> ()
type SetHook = (entity: Entity, id: Component, value: number) -> ()
type RemovedHook = (entity: Entity, id: Component) -> (() -> ())?

type ArchetypeObserverCallback = (archetype: Archetype) -> ()
type ArchetypeObserver = { match: (archetype: Archetype) -> boolean, callback: ArchetypeObserverCallback }

export type Query<T...> = typeof(setmetatable(
	{} :: {
		with_ids: { Entity },
		without_ids: { Entity },
		terms: { Entity },

		match: (Archetype) -> boolean,
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
	archetype_id: ArchetypeId,
	hash: string,
	alive: boolean,

	entities: { Entity },
	columns: Array<Column>,
	components: Array<u53>,

	columns_map: { [u53]: Column },
	forward_edges: Map<u53, Archetype>,
	backward_edges: Map<u53, Archetype>,
}

export type EntityRecord = {
	archetype: Archetype,
	archetype_row: number,
	dense: u24,

	archetype_changed: { ArchetypeChangedHook }?,
}

export type ComponentRecord = {
	column_index: Map<Archetype, number>,
	id_count: Map<Archetype, number>,

	-- only defined for pair(rel, *)
	pair_records: Map<u53, ComponentRecord>?,

	archetype_count: number,
	flags: Bitset,

	on_added: { SetHook }?,
	on_changed: { SetHook }?,
	on_removed: { RemovedHook }?,
}

export type ComponentsLookup = Map<u53, ComponentRecord>

export type EntityIndex = {
	dense: Array<u53>,
	sparse: Map<u24, EntityRecord>,
	alive: number,
}

export type World = {
	entity_index: EntityIndex,
	components_lookup: Map<u53, ComponentRecord>,
	archetypes_lookup: Map<string, Archetype>,

	archetypes: Map<ArchetypeId, Archetype>,
	ROOT_ARCHETYPE: Archetype,

	archetype_activation_observers: Map<u53, { ArchetypeObserver }>,
	archetype_deactivation_observers: Map<u53, { ArchetypeObserver }>,

	entity: () -> Entity,
	component: <T>() -> Component<T>,

	has: (entity: Entity, id: Component) -> boolean,
	get: & (<A>(Entity, Component<A>) -> A)
		& (<A, B>(Entity, Component<A>, Component<A>) -> (A, B))
		& (<A, B, C>(World, Entity, Component<A>, Component<A>, Component<A>) -> (A, B, C))
		& (<A, B, C, D>(Entity, Component<A>, Component<B>, Component<C>, Component<D>) -> (A, B, C, D)),

	set: <T>(entity: Entity, id: Component<T>, data: T) -> (),
	add: (entity: Entity, id: Component) -> (),
	remove: (entity: Entity, id: Component) -> (),

	query: (() -> Query<nil>)
		& (<A>(Component<A>) -> Query<A>)
		& (<A, B>(Component<A>, Component<B>) -> Query<A, B>)
		& (<A, B, C>(Component<A>, Component<B>, Component<C>) -> Query<A, B, C>)
		& (<A, B, C, D>(Component<A>, Component<B>, Component<C>, Component<D>) -> Query<A, B, C, D>)
		& (<A, B, C, D, E>(
			Component<A>,
			Component<B>,
			Component<C>,
			Component<D>,
			Component<E>
		) -> Query<A, B, C, D, E>)
		& (<A, B, C, D, E, F>(
			Component<A>,
			Component<B>,
			Component<C>,
			Component<D>,
			Component<E>,
			Component<F>
		) -> Query<A, B, C, D, E, F>)
		& (<A, B, C, D, E, F, G>(
			Component<A>,
			Component<B>,
			Component<C>,
			Component<D>,
			Component<E>,
			Component<F>,
			Component<G>
		) -> Query<A, B, C, D, E, F, G>)
		& (<A, B, C, D, E, F, G, H>(
			Component<A>,
			Component<B>,
			Component<C>,
			Component<D>,
			Component<E>,
			Component<F>,
			Component<G>,
			Component<H>,
			...Component<any>
		) -> Query<A, B, C, D, E, F, G, H>),
}

local preregistered_count = 0
local preregistered_components: Map<u24, true> = {}

local MAX_COMPONENT_ID = _G.ECS_MAX_COMPONENT_ID or 256

local ENTITY_MASK = bit32.lshift(1, 24)
local GENERATION_MASK = bit32.lshift(1, 16)
local PAIR_OFFSET = 2 ^ 48

local RANGE_PAGE_SIZE = 2 ^ 12

local ECS_WILDCARD = MAX_COMPONENT_ID + 1
local ECS_CHILDOF = MAX_COMPONENT_ID + 2
local ECS_NAME = MAX_COMPONENT_ID + 3
local ECS_COMPONENT = MAX_COMPONENT_ID + 4
local ECS_REST = MAX_COMPONENT_ID + 5

local IS_COMPONENT_FLAG = bit32.lshift(1, 0)

local NULL_ARRAY = table.freeze {} :: { any }

local function NOOP() end

local function IS_PAIR(e: number): boolean
	return e > PAIR_OFFSET
end

local function PAIR_FIRST(id: u53): u24
	return (id - PAIR_OFFSET) // ENTITY_MASK
end

local function PAIR_SECOND(id: u53): u24
	return (id - PAIR_OFFSET) % ENTITY_MASK
end

local function ECS_PAIR(first: u24, second: u24): u53
	first %= ENTITY_MASK
	second %= ENTITY_MASK

	return second + (first * ENTITY_MASK) + PAIR_OFFSET
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

local function HASH_IDS(ids: { u53 })
	return table.concat(ids, "-")
end

local function FIND_INSERT(ids: { u53 }, added: u53)
	for i, id in ids do
		if id == added then
			return -1
		end
		if id > added then
			return i
		end
	end
	return #ids + 1
end

local CHECK_FLAG = bit32.btest

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

local function FIRE_SET_HOOKS(hooks: { SetHook }, entity: u53, id: u53, data: any)
	for _, hook in hooks do
		hook(entity :: any, id :: any, data)
	end
end

local function FIRE_REMOVE_HOOKS(hooks: { RemovedHook }, entity: u53, id: u53)
	local post_removed_callbacks: { () -> () }? = nil

	for _, hook in hooks do
		local post_removed = hook(entity :: any, id :: any)
		if post_removed then
			if post_removed_callbacks then
				table.insert(post_removed_callbacks, post_removed)
			else
				post_removed_callbacks = { post_removed }
			end
		end
	end

	return post_removed_callbacks
end

local function PREREGISTER_COMPONENT()
	local id = MAX_COMPONENT_ID - preregistered_count
	preregistered_count += 1
	preregistered_components[id] = true
	return id
end

local function PREREGISTER_TAG()
	local id = MAX_COMPONENT_ID - preregistered_count
	preregistered_count += 1
	return id
end

local function query_new(world: World, ...: u53): Query<any>
	local archetype_activation_observers = world.archetype_activation_observers
	local archetype_deactivation_observers = world.archetype_deactivation_observers
	local components_lookup = world.components_lookup

	local terms = { ... }
	local with_ids = { ... }
	local without_ids: { number }? = nil

	local compatible_archetypes: { Archetype } = nil :: any
	local compatible_archetypes_map: { [ArchetypeId]: number } = {}

	local is_cached = false

	local function find_compatible_archetypes(): { Archetype }
		local best_record: ComponentRecord? = nil
		local best_record_count = math.huge

		for _, id in with_ids do
			local record = components_lookup[id]
			if not record then
				continue
			end
			local archetype_count = record.archetype_count
			if archetype_count < best_record_count then
				best_record = record
				best_record_count = archetype_count
			end
		end
		local compatible: { Archetype } = {}

		if best_record == nil then
			return compatible
		end

		for archetype in best_record.column_index do
			if not archetype.alive then
				continue
			end

			local columns_map = archetype.columns_map
			local skip = false
			for _, component in with_ids do
				if not columns_map[component] then
					skip = true
					break
				end
			end
			if skip then
				continue
			end

			if without_ids then
				for _, component in without_ids do
					if columns_map[component] then
						skip = true
						break
					end
				end
			end
			if skip then
				continue
			end

			table.insert(compatible, archetype)
		end
		return compatible
	end

	local function query_match(archetype: Archetype)
		local columns_map = archetype.columns_map

		for _, id in with_ids do
			if not columns_map[id] then
				return false
			end
		end
		if without_ids then
			for _, id in without_ids do
				if columns_map[id] then
					return false
				end
			end
		end

		return true
	end

	local function query_with(...: u53)
		local ids = { ... }
		table.move(ids, 1, #ids, #with_ids + 1, with_ids)
	end

	local function query_without(...: u53)
		local ids = { ... }
		if without_ids then
			table.move(ids, 1, #ids, #without_ids + 1, without_ids)
		else
			without_ids = ids
		end
	end

	local function query_archetypes(): { Archetype }
		if not compatible_archetypes then
			local matched = find_compatible_archetypes()
			compatible_archetypes = matched
			return matched
		end
		return compatible_archetypes
	end

	local function query_cached()
		if is_cached then
			return
		end
		is_cached = true

		-- forcing the archetypes to recompute from scratch
		compatible_archetypes = find_compatible_archetypes()
		local observe_id = with_ids[1]

		for index, archetype in compatible_archetypes do
			compatible_archetypes_map[archetype.archetype_id] = index
		end

		local function activation_observer_callback(archetype: Archetype)
			local index = #compatible_archetypes + 1
			compatible_archetypes[index] = archetype
			compatible_archetypes_map[archetype.archetype_id] = index
		end

		local function deactivation_observer_callback(archetype: Archetype)
			local archetype_id = archetype.archetype_id
			local row = compatible_archetypes_map[archetype_id]

			local last_row = #compatible_archetypes
			local last_archetype = compatible_archetypes[last_row]

			compatible_archetypes[row] = last_archetype
			compatible_archetypes[last_row] = nil

			compatible_archetypes_map[archetype_id] = nil
			compatible_archetypes_map[last_archetype.archetype_id] = row
		end

		local activation_observer: ArchetypeObserver = {
			match = query_match,
			callback = activation_observer_callback,
		}
		local deactivation_observer: ArchetypeObserver = {
			match = query_match,
			callback = deactivation_observer_callback,
		}

		local activation_observers = archetype_activation_observers[observe_id]
		if activation_observers then
			table.insert(activation_observers, activation_observer)
		else
			archetype_activation_observers[observe_id] = { activation_observer }
		end

		local deactivation_observers = archetype_deactivation_observers[observe_id]
		if deactivation_observers then
			table.insert(deactivation_observers, deactivation_observer)
		else
			archetype_deactivation_observers[observe_id] = { deactivation_observer }
		end
	end

	local A, B, C, D, E, F, G, H, I = unpack(terms)

	local a: Column, b: Column, c: Column, d: Column
	local e: Column, f: Column, g: Column, h: Column

	local iter_archetype_index = 1
	local iter_archetype: Archetype
	local iter_columns_map: { [u53]: Column }

	local iter_entities: { Entity }
	local iter_entity_index = 0

	local query_iter_next

	local function query_iter()
		iter_archetype_index = 1
		compatible_archetypes = query_archetypes()
		iter_archetype = compatible_archetypes[iter_archetype_index]

		if not iter_archetype then
			return NOOP
		end
		iter_entities = iter_archetype.entities
		iter_entity_index = #iter_entities

		iter_columns_map = iter_archetype.columns_map

		if not A then
		elseif not B then
			a = iter_columns_map[A]
		elseif not C then
			a = iter_columns_map[A]
			b = iter_columns_map[B]
		elseif not D then
			a = iter_columns_map[A]
			b = iter_columns_map[B]
			c = iter_columns_map[C]
		elseif not E then
			a = iter_columns_map[A]
			b = iter_columns_map[B]
			c = iter_columns_map[C]
			d = iter_columns_map[D]
		elseif not F then
			a = iter_columns_map[A]
			b = iter_columns_map[B]
			c = iter_columns_map[C]
			d = iter_columns_map[D]
			e = iter_columns_map[E]
		elseif not G then
			a = iter_columns_map[A]
			b = iter_columns_map[B]
			c = iter_columns_map[C]
			d = iter_columns_map[D]
			e = iter_columns_map[E]
			f = iter_columns_map[F]
		elseif not H then
			a = iter_columns_map[A]
			b = iter_columns_map[B]
			c = iter_columns_map[C]
			d = iter_columns_map[D]
			e = iter_columns_map[E]
			f = iter_columns_map[F]
			g = iter_columns_map[G]
		else
			a = iter_columns_map[A]
			b = iter_columns_map[B]
			c = iter_columns_map[C]
			d = iter_columns_map[D]
			e = iter_columns_map[E]
			f = iter_columns_map[F]
			g = iter_columns_map[G]
			h = iter_columns_map[H]
		end

		return query_iter_next
	end

	if not A then
		function query_iter_next(): Entity
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil :: any
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
			end
			iter_entity_index -= 1
			return entity
		end
	elseif not B then
		function query_iter_next(): (Entity, any)
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil :: any
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			return entity, a[row]
		end
	elseif not C then
		function query_iter_next(): (Entity, any, any)
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil :: any
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
				b = iter_columns_map[B]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			return entity, a[row], b[row]
		end
	elseif not D then
		function query_iter_next(): (Entity, any, any, any)
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil :: any
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
				b = iter_columns_map[B]
				c = iter_columns_map[C]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			return entity, a[row], b[row], c[row]
		end
	elseif not E then
		function query_iter_next(): (Entity, any, any, any, any)
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil :: any
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
				b = iter_columns_map[B]
				c = iter_columns_map[C]
				d = iter_columns_map[D]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			return entity, a[row], b[row], c[row], d[row]
		end
	elseif not F then
		function query_iter_next(): (Entity, any, any, any, any, any)
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil :: any
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
				b = iter_columns_map[B]
				c = iter_columns_map[C]
				d = iter_columns_map[D]
				e = iter_columns_map[E]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			return entity, a[row], b[row], c[row], d[row], e[row]
		end
	elseif not G then
		function query_iter_next(): Entity?
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
				b = iter_columns_map[B]
				c = iter_columns_map[C]
				d = iter_columns_map[D]
				e = iter_columns_map[E]
				f = iter_columns_map[F]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			return entity, a[row], b[row], c[row], d[row], e[row], f[row]
		end
	elseif not H then
		function query_iter_next(): Entity?
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
				b = iter_columns_map[B]
				c = iter_columns_map[C]
				d = iter_columns_map[D]
				e = iter_columns_map[E]
				f = iter_columns_map[F]
				g = iter_columns_map[G]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			return entity, a[row], b[row], c[row], d[row], e[row], f[row], g[row]
		end
	elseif not I then
		function query_iter_next(): Entity?
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
				b = iter_columns_map[B]
				c = iter_columns_map[C]
				d = iter_columns_map[D]
				e = iter_columns_map[E]
				f = iter_columns_map[F]
				g = iter_columns_map[G]
				h = iter_columns_map[H]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			return entity, a[row], b[row], c[row], d[row], e[row], f[row], g[row], h[row]
		end
	else
		local rest = {}
		local terms_count = #terms

		function query_iter_next(): Entity?
			local entity = iter_entities[iter_entity_index]
			while entity == nil do
				iter_archetype_index += 1
				iter_archetype = compatible_archetypes[iter_archetype_index]
				if not iter_archetype then
					return nil
				end

				iter_entities = iter_archetype.entities
				iter_entity_index = #iter_entities
				if iter_entity_index == 0 then
					continue
				end
				entity = iter_entities[iter_entity_index]
				iter_columns_map = iter_archetype.columns_map

				a = iter_columns_map[A]
				b = iter_columns_map[B]
				c = iter_columns_map[C]
				d = iter_columns_map[D]
				e = iter_columns_map[E]
				f = iter_columns_map[F]
				g = iter_columns_map[G]
				h = iter_columns_map[H]
			end
			local row = iter_entity_index
			iter_entity_index -= 1

			for i = 9, terms_count do
				rest[i - 8] = iter_columns_map[terms[i]][row]
			end

			return entity, a[row], b[row], c[row], d[row], e[row], f[row], g[row], h[row], unpack(rest)
		end
	end

	local query = {
		with_ids = with_ids,
		without_ids = without_ids,
		terms = terms,

		cached = query_cached,
		match = query_match,
		archetypes = query_archetypes,
		with = query_with,
		without = query_without,
		iter = query_iter,
	}

	return query :: any
end

local function query_build(world: World) end

local function world_new()
	local dense_arr = {}
	local sparse_arr = {}

	local archetypes_count = 1
	local archetypes: Map<ArchetypeId, Archetype> = {}
	local archetypes_lookup: Map<string, Archetype> = {}

	local component_count = 0
	local components_lookup: ComponentsLookup = table.create(ECS_REST)

	local archetype_activation_observers: Map<u53, { ArchetypeObserver }> = {}
	local archetype_deactivation_observers: Map<u53, { ArchetypeObserver }> = {}

	local entity_index: EntityIndex = {
		dense = dense_arr,
		sparse = sparse_arr,
		alive = 0,
	}

	local ROOT_ARCHETYPE: Archetype = {
		archetype_id = archetypes_count,
		hash = "",

		entities = {},
		columns = {},
		components = {},

		columns_map = {},
		forward_edges = {},
		backward_edges = {},
	}
	archetypes[1] = ROOT_ARCHETYPE
	archetypes_lookup[""] = ROOT_ARCHETYPE

	local function get_entity_record(entity: u53): EntityRecord?
		return sparse_arr[ENTITY_ID(entity)]
	end

	local function get_entity_record_alive(entity: u53): EntityRecord?
		local record = sparse_arr[ENTITY_ID(entity)]
		if record == nil then
			return nil
		end
		local dense = record.dense
		if record.dense > entity_index.alive then
			error "attempted to use a dead entity"
		end
		local dense_id = dense_arr[dense]
		if dense_id ~= entity then
			error "attempted to use an entity with a different generation"
		end
		return record
	end

	local function get_new_entity_id(): u53
		local alive = entity_index.alive
		local count = #sparse_arr

		if alive >= count then
			local next_id = count + 1
			local new_record = {
				dense = next_id,
				archetype = ROOT_ARCHETYPE,
			} :: EntityRecord
			table.insert(sparse_arr, new_record)
			table.insert(dense_arr, next_id)
			entity_index.alive = next_id

			return next_id
		end

		alive += 1
		entity_index.alive = alive
		return dense_arr[alive]
	end

	local function delete_entity_id(id: u24)
		local alive = entity_index.alive

		local dense_index = sparse_arr[id].dense
		if dense_index ~= alive then
			local last = dense_arr[alive]
			dense_arr[dense_index] = last
		end
		local new_generation = INCREMENT_GENERATION(dense_arr[dense_index])
		dense_arr[alive] = new_generation
		entity_index.alive -= 1
	end

	local function fetch(columns: { [u53]: Column }, id: u53, row: number)
		local column = columns[id]
		if not column then
			return nil
		end
		return column[row]
	end

	local function world_has(entity: u53, id: u53)
		local record = get_entity_record_alive(entity)
		if not record then
			return false
		end

		local archetype = record.archetype
		return archetype.columns_map[id] ~= nil
	end

	local function world_get(entity: u53, a: u53, b: u53, c: u53, d: u53, e: u53, ...): any
		local record = get_entity_record_alive(entity)
		if not record then
			return nil
		end

		local archetype = record.archetype
		local columns_map = archetype.columns_map
		local row = record.archetype_row

		if not b then
			return fetch(columns_map, a, row)
		elseif not c then
			return fetch(columns_map, a, row), fetch(columns_map, b, row)
		elseif not d then
			return fetch(columns_map, a, row), fetch(columns_map, b, row), fetch(columns_map, c, row)
		elseif not e then
			return fetch(columns_map, a, row),
				fetch(columns_map, b, row),
				fetch(columns_map, c, row),
				fetch(columns_map, d, row)
		else
			local rest = { ... }
			for index, id in rest do
				rest[index] = fetch(columns_map, id, row)
			end

			return fetch(columns_map, a, row),
				fetch(columns_map, b, row),
				fetch(columns_map, c, row),
				fetch(columns_map, d, row),
				fetch(columns_map, e, row),
				unpack(rest)
		end
	end

	local function component_record_create(id: u53)
		local is_component = world_has(id, ECS_COMPONENT) or (preregistered_components[id] or false)

		local record: ComponentRecord = {
			column_index = {},
			id_count = {},
			pair_records = nil,

			archetype_count = 0,
			flags = bit32.bor((is_component and IS_COMPONENT_FLAG) or 0),
		}

		components_lookup[id] = record
		return record
	end

	local function component_record_ensure(id: u53)
		local record = components_lookup[id]
		if record then
			return record
		end

		return component_record_create(id)
	end

	local function fire_activated_archetype(archetype: Archetype)
		local columns_map = archetype.columns_map
		for id in columns_map do
			local observers = archetype_activation_observers[id]
			if not observers then
				continue
			end
			for _, observer in observers do
				if observer.match(archetype) then
					observer.callback(archetype)
				end
			end
		end
	end

	local function fire_deactivated_archetype(archetype: Archetype)
		local columns_map = archetype.columns_map
		for id in columns_map do
			local observers = archetype_deactivation_observers[id]
			if not observers then
				continue
			end
			for _, observer in observers do
				if observer.match(archetype) then
					observer.callback(archetype)
				end
			end
		end
	end

	local function archetype_append_to_record(record: ComponentRecord, archetype: Archetype, index: number): boolean
		local column_index = record.column_index
		local id_count = record.id_count

		if not column_index[archetype] then
			column_index[archetype] = index
			id_count[archetype] = 1
			return true
		else
			id_count[archetype] += 1
			return false
		end
	end

	local function archetype_move_column_rows(
		source: Archetype,
		destination: Archetype,
		source_row: number,
		destination_row: number,
		last_row: number
	)
		local source_columns = source.columns

		if source_row == last_row then
			for index, column in source_columns do
				if column == NULL_ARRAY then
					continue
				end

				local destination_column = destination.columns_map[source.components[index]]
				if destination_column then
					destination_column[destination_row] = column[source_row]
				end

				column[last_row] = nil
			end
		else
			for index, column in source_columns do
				if column == NULL_ARRAY then
					continue
				end

				local destination_column = destination.columns_map[source.components[index]]
				if destination_column then
					destination_column[destination_row] = column[source_row]
				end

				column[source_row] = column[last_row]
				column[last_row] = nil
			end
		end
	end

	local function archetype_insert_entity(entity: u53, record: EntityRecord, archetype: Archetype): number
		local entities = archetype.entities
		local last_row = #entities
		local assign_row = last_row + 1

		entities[assign_row] = entity :: any
		if last_row == 0 then
			archetype.alive = true
			fire_activated_archetype(archetype)
		end

		return assign_row
	end

	local function archetype_move_entity(entity: u53, record: EntityRecord, source: Archetype, destination: Archetype)
		local source_entities = source.entities
		local destination_entities = destination.entities

		local last_source_row = #source_entities
		local last_destination_row = #destination_entities

		local source_row = record.archetype_row
		local destination_row = last_destination_row + 1

		archetype_move_column_rows(source, destination, source_row, destination_row, last_source_row)

		if source_row == last_source_row then
			source_entities[last_source_row] = nil
			source.alive = false
			fire_deactivated_archetype(source)
		else
			local swapped_entity: u53 = source_entities[last_source_row] :: any
			source_entities[source_row] = swapped_entity :: any

			local swapped_record = get_entity_record(swapped_entity) :: EntityRecord
			swapped_record.archetype_row = source_row
			source_entities[last_source_row] = nil
		end

		destination_entities[destination_row] = entity :: any
		record.archetype_row = destination_row
		record.archetype = destination

		if last_destination_row == 0 then
			destination.alive = true
			fire_activated_archetype(destination)
		end
	end

	local function archetype_assign_entity(entity: u53, record: EntityRecord, archetype: Archetype)
		local assigned_row = archetype_insert_entity(entity, record, archetype)
		record.archetype = archetype
		record.archetype_row = assigned_row
	end

	local function archetype_delete_entity(archetype: Archetype, row: number)
		local columns = archetype.columns
		local entities = archetype.entities
		local last_row = #entities
		local swap = entities[last_row]

		if last_row == row then
			-- delete last column
			for _, column in columns do
				if column ~= NULL_ARRAY then
					column[last_row] = nil
				end
			end
			entities[last_row] = nil

			archetype.alive = false
			fire_deactivated_archetype(archetype)
		else
			-- swap column, and delete last
			local swap_record = get_entity_record(swap :: any)
			if swap_record then
				swap_record.archetype_row = row
			end
			entities[row] = swap

			for _, column in columns do
				if column ~= NULL_ARRAY then
					column[row] = column[last_row]
					column[last_row] = nil
				end
			end
			entities[last_row] = nil
		end
	end

	local function archetype_create(ids: { u53 }, hash: string): Archetype
		local archetype_id = archetypes_count + 1
		archetypes_count = archetype_id

		local columns_length = #ids
		local columns = table.create(columns_length) :: { Column }

		local columns_map: Map<u53, Column> = {}

		local archetype: Archetype = {
			archetype_id = archetype_id,
			hash = hash,
			alive = false,

			entities = {},
			columns = columns,
			components = ids,

			columns_map = columns_map,
			forward_edges = {},
			backward_edges = {},
		}

		for index, id in ids do
			local id_record = component_record_ensure(id)
			id_record.archetype_count += 1

			local is_tag = not CHECK_FLAG(id_record.flags, IS_COMPONENT_FLAG)
			local column = if is_tag then NULL_ARRAY else {}
			columns[index] = column
			columns_map[id] = column

			archetype_append_to_record(id_record, archetype, index)

			if IS_PAIR(id) then
				local relation = PAIR_FIRST(id)
				local target = PAIR_SECOND(id)

				local relation_wildcard = ECS_PAIR(relation, ECS_WILDCARD)
				local relation_record = component_record_ensure(relation_wildcard)
				relation_record.archetype_count += 1

				local relation_appended = archetype_append_to_record(relation_record, archetype, index)
				if relation_appended then
					columns_map[relation_wildcard] = column
				end

				local pair_records = relation_record.pair_records
				if pair_records then
					pair_records[id] = id_record
				else
					relation_record.pair_records = {
						[id] = id_record,
					}
				end

				local target_wildcard = ECS_PAIR(ECS_WILDCARD, target)
				local target_record = component_record_ensure(target_wildcard)
				target_record.archetype_count += 1

				local target_apended = archetype_append_to_record(target_record, archetype, index)
				if target_apended then
					columns_map[target_wildcard] = column
				end
			end
		end

		archetypes[archetype_id] = archetype
		archetypes_lookup[hash] = archetype
		return archetype
	end

	local function archetype_ensure(ids: { u53 }): Archetype
		if #ids < 1 then
			return ROOT_ARCHETYPE
		end

		local hash = HASH_IDS(ids)
		local archetype = archetypes_lookup[hash]
		if archetype then
			return archetype
		end

		return archetype_create(ids, hash)
	end

	local function archetype_find_with(source: Archetype, id: u53): Archetype
		if source.columns_map[id] then
			return source
		end

		local edges = source.forward_edges
		local destination = edges[id]
		if not destination then
			local destination_components = table.clone(source.components)
			local insert_at = FIND_INSERT(destination_components, id)
			table.insert(destination_components, insert_at, id)

			local found = archetype_ensure(destination_components)
			edges[id] = found
			found.backward_edges[id] = source
			return found
		end

		return destination
	end

	local function archetype_find_without(source: Archetype, id: u53)
		local edges = source.backward_edges
		local destination = edges[id]
		if not destination then
			local destination_components = table.clone(source.components)
			local remove_at = table.find(destination_components, id)
			table.remove(destination_components, remove_at)

			local found = archetype_ensure(destination_components)
			edges[id] = found
			found.forward_edges[id] = source
			return found
		end

		return destination
	end

	local function world_entity(): u53
		return get_new_entity_id()
	end

	local function world_set(entity: u53, id: u53, data: any)
		local record = get_entity_record_alive(entity)
		if not record then
			return
		end

		local source = record.archetype
		local column = source.columns_map[id]

		if column then
			column[record.archetype_row] = data

			local component_record = components_lookup[id]
			local changed_hooks = component_record.on_changed
			if changed_hooks then
				FIRE_SET_HOOKS(changed_hooks, entity, id, data)
			end
		else
			local destination = archetype_find_with(source, id)

			if source == ROOT_ARCHETYPE then
				archetype_assign_entity(entity, record, destination)
			else
				archetype_move_entity(entity, record, source, destination)
			end
			local new_column = destination.columns_map[id]
			new_column[record.archetype_row] = data

			local component_record = components_lookup[id]
			local added_hooks = component_record.on_added
			if added_hooks then
				FIRE_SET_HOOKS(added_hooks, entity, id, data)
			end
		end
	end

	local function world_add(entity: u53, id: u53)
		local record = get_entity_record_alive(entity)
		if not record then
			return
		end

		local source = record.archetype
		if source.columns_map[id] then
			return
		end

		local destination = archetype_find_with(source, id)

		if source == ROOT_ARCHETYPE then
			archetype_assign_entity(entity, record, destination)
		else
			archetype_move_entity(entity, record, source, destination)
		end

		local component_record = components_lookup[id]
		local added_hooks = component_record.on_added
		if added_hooks then
			FIRE_SET_HOOKS(added_hooks, entity, id)
		end
	end

	local function world_remove(entity: u53, id: u53)
		local record = get_entity_record_alive(entity)
		if not record then
			return
		end

		local source = record.archetype
		if not source.columns_map[id] then
			return
		end

		local component_record = components_lookup[id]
		local removed_hooks = component_record.on_removed
		local post_removed = removed_hooks and FIRE_REMOVE_HOOKS(removed_hooks, entity, id) or nil

		local destination = archetype_find_without(source, id)

		archetype_move_entity(entity, record, source, destination)
		if post_removed then
			for _, callback in post_removed do
				callback()
			end
		end
	end

	local function world_tag(): u24
		component_count += 1
		if component_count > (MAX_COMPONENT_ID - preregistered_count) then
			error "max components exceeded, consider changing _G.ECS_MAX_COMPONENT_ID"
		end
		return component_count
	end

	local function world_component(): u24
		local new_component = world_tag()
		world_add(new_component, ECS_COMPONENT)
		return new_component
	end

	local function world_alive(entity: u53): boolean
		local record = sparse_arr[ENTITY_ID(entity)]
		if record == nil then
			return false
		end
		local dense = record.dense
		if dense <= entity_index.alive then
			return false
		end
		local alive_id = dense_arr[dense]
		return alive_id == entity
	end

	local function insert_component_hook<T>(callback: T, hooks: { T }?)
		if hooks then
			table.insert(hooks, callback)
		else
			hooks = { callback }
		end

		local function disconnect()
			local index = table.find(hooks :: { any }, callback)
			if index then
				table.remove(hooks :: { any }, index)
			end
		end

		return hooks, disconnect
	end

	local function is_component(id: u53)
		local record = component_record_ensure(id)
		return CHECK_FLAG(record.flags, IS_COMPONENT_FLAG)
	end

	local function is_tag(id: u53)
		return not is_component(id)
	end

	local function world_added(id: u53, callback: SetHook)
		local record = component_record_ensure(id)
		local hooks, disconnect = insert_component_hook(callback, record.on_added)
		record.on_added = hooks
		return disconnect
	end

	local function world_changed(id: u53, callback: SetHook)
		local record = component_record_ensure(id)
		local hooks, disconnect = insert_component_hook(callback, record.on_changed)
		record.on_changed = hooks
		return disconnect
	end

	local function world_removed(id: u53, callback: RemovedHook)
		local record = component_record_ensure(id)
		local hooks, disconnect = insert_component_hook(callback, record.on_removed)
		record.on_removed = hooks
		return disconnect
	end

	local world: World = {
		entity_index = entity_index,
		components_lookup = components_lookup,
		archetypes_lookup = archetypes_lookup,

		archetypes = archetypes,
		ROOT_ARCHETYPE = ROOT_ARCHETYPE,

		archetype_activation_observers = archetype_activation_observers,
		archetype_deactivation_observers = archetype_deactivation_observers,

		entity = world_entity,
		component = world_component,

		add = world_add,
		set = world_set,
		remove = world_remove,

		get = world_get,
		has = world_has,
	} :: any

	-- query

	local function world_query(...: u53)
		return query_new(world, ...)
	end

	world.query = world_query :: any

	for i = 1, ECS_REST do
		get_new_entity_id()
	end

	return world
end

return {
	world = world_new,
}
