local addon = MountLeash
local L = LibStub("AceLocale-3.0"):GetLocale("MountLeash")

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local SPEC_TYPES = { customSpec = 12222222222222222 }

local UpdateCustomSpecConfigTables, config_getSpecArgs, buildConfigSpec

function addon:AddCustomSpec(specid)
	if (not specid) then
		return
	end

	self.db.char.sets.customSpec[specid].enable = true -- touch

	UpdateCustomSpecConfigTables(self)
end

function addon:DeleteCustomSpec(specid)
	wipe(self.db.char.sets.customSpec[specid])
	self.db.char.sets.customSpec[specid] = nil
	UpdateCustomSpecConfigTables(self)
	self:DoLocationCheck()
end

function addon:GetSpecMount(ltype, name, spellid)
	assert(SPEC_TYPES[ltype])

	for i, v in ipairs(self.db.char.sets[ltype][name].mounts) do
		if (spellid == v) then
			return i
		end
	end
end

function addon:SetSpecMount(ltype, name, spellid, value)
	assert(SPEC_TYPES[ltype])

	local t = self.db.char.sets[ltype][name].mounts
	local iszit = self:GetSpecMount(ltype, name, spellid)
	if (value and not iszit) then
		table.insert(t, spellid)
	elseif (not value and iszit) then
		table.remove(t, iszit)
	end

	self:DoLocationCheck()
end

--
-- config
--

function addon:UpdateSpecConfigTables()
	UpdateCustomSpecConfigTables(self, true)
end

-- dirty bits for updating custom specs

local function config_spec_mounttoggle_get(info)
	return info.handler:GetSpecMount(info[#info - 3], info[#info - 2], tonumber(info[#info]))
end

local function config_spec_mounttoggle_set(info, val)
	info.handler:SetSpecMount(info[#info - 3], info[#info - 2], tonumber(info[#info]), val)
end

local function config_spec_delete(info)
	info.handler:DeleteCustomSpec(info[#info - 1])
end

local function config_spec_inherit_set(info, v)
	assert(SPEC_TYPES[info[#info - 2]])
	local loc = info.handler.db.char.sets[info[#info - 2]][info[#info - 1]]
	if (not v) then
		loc.inherit = false
		info.handler:UpdateSpecConfigTables()
	elseif (v and not loc.inherit) then
		-- only set if we're not going to clobber it
		-- and not ourselves
		loc.inherit = true
		info.handler:UpdateSpecConfigTables()
	end

	info.handler:DoLocationCheck()
end

local function config_spec_inherit_get(info)
	assert(SPEC_TYPES[info[#info - 2]])
	return info.handler.db.char.sets[info[#info - 2]][info[#info - 1]].inherit
end

local loc_mount_config = {
	type = "group",
	name = "",
	order = 10,
	args = {},
	inline = true
}
local loc_inherit_config = {
	type = "select",
	name = L["Inherits From"],
	order = 11,
	values = {},
	get = function(info)
		assert(SPEC_TYPES[info[#info - 2]])

		local inherit = info.handler.db.char.sets[info[#info - 2]][info[#info - 1]].inherit
		if (inherit ~= true) then
			return inherit
		end
	end,
	set = function(info, val)
		assert(SPEC_TYPES[info[#info - 2]])
		info.handler.db.char.sets[info[#info - 2]][info[#info - 1]].inherit = val
		info.handler:DoLocationCheck()
	end
}

function UpdateCustomSpecConfigTables(self, nosignal)
	local mount_args = loc_mount_config.args
	wipe(mount_args)

	for i = 1, GetNumCompanions("MOUNT") do
		local _, name, spellid = GetCompanionInfo("MOUNT", i)

		mount_args[tostring(spellid)] = {
			type = "toggle",
			name = name,
			get = config_spec_mounttoggle_get,
			set = config_spec_mounttoggle_set
		}
	end

	local loc_args = self.options.args.specs.args.customSpec.plugins.data
	wipe(loc_args) -- TODO: check to see if specs is dirty before wiping
	wipe(loc_inherit_config.values)

	for name, data in pairs(self.db.char.sets.customSpec) do
		if (data.enable) then
			if (not loc_inherit_config.values[name]) then
				loc_inherit_config.values[name] = name
			end

			buildConfigSpec(loc_args,
				name,
				name,
				self.db.char.sets.customSpec[name].inherit,
				"customSpec")
		end
	end

	if (not nosignal) then
		AceConfigRegistry:NotifyChange("MountLeash")
	end
end

function buildConfigSpec(args, key, name, inherit, ctype)
	if (not args[key]) then
		args[key] = config_getSpecArgs(name, ctype)
	end

	if (inherit) then
		args[key].args.mounts = nil
		args[key].args.inherits = loc_inherit_config
	else
		args[key].args.mounts = loc_mount_config
		args[key].args.inherits = nil
	end
end

function config_getSpecArgs(name, ctype)
	local deleteMe, enableMe

	if (ctype == "customSpec") then
		deleteMe = {
			type = "execute",
			name = DELETE,
			order = 1,
			func = config_spec_delete
		}
	end

	return {
		type = "group",
		name = name,
		args = {
			deleteMe = deleteMe,
			enableMe = enableMe,
			inherit = {
				type = "toggle",
				name = L["Inherits"],
				desc = L["Use a mount list from another Spec."],
				order = 2,
				set = config_spec_inherit_set,
				get = config_spec_inherit_get,
			},
			seperator = {
				type = "header",
				name = "",
				order = 3,
			},
		}
	}
end

--
-- switcher code
--

function addon:TryInitSpec()
	if (tostring(SpecializationUtil.GetActiveSpecialization()) == nil) then
		return
	end

	self:HasMount(true) -- not yet called?
	self:UpdateSpecConfigTables()
	self:DoLocationCheck()

	self.TryInitSpec = function() end
end

local checkSpec

function addon:DoSpecCheck()
	local cur_spec = tostring(SpecializationUtil.GetActiveSpecialization())

	-- custom spec check
	if (checkSpec(self, "customSpec", cur_spec)) then
		return
	end

	-- nothing doing
	self.override_mounts = {}
end

function checkSpec(self, ltype, cur_spec)
	if (not cur_spec or cur_spec == "") then
		return
	end

	-- don't let AceDB generate an entry for us
	local specdata = rawget(self.db.char.sets[ltype], cur_spec)

	-- make sure entry exists
	if (not specdata or not specdata.enable) then
		return
	end

	local mounts = specdata.mounts
	if (specdata.inherit and specdata.inherit ~= true
			and self.db.char.sets.customSpec[specdata.inherit]) then
		mounts = self.db.char.sets.customSpec[specdata.inherit].mounts
	end

	if (specdata and #mounts > 0) then
		self.override_mounts = mounts
		return true
	end
end
