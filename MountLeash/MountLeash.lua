local addon = LibStub("AceAddon-3.0"):NewAddon("MountLeash", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
_G.MountLeash = addon

local L = LibStub("AceLocale-3.0"):GetLocale("MountLeash")

-- Binding globals
BINDING_HEADER_MOUNTLEASH = "MountLeash"
BINDING_NAME_MOUNTLEASH_SUMMON = L["Summon Another Mount"]
BINDING_NAME_MOUNTLEASH_CONFIG = L["Open Configuration"]


-- Default DB
local defaults = {
	profile = {
		enable = true,
		enableInBattleground = true,
		weightedMounts = false
	},
	char = {
		ignore_mounts = {}, -- [spellid] = true, hide.  if false, don't hide
		weights = {}, -- [spellid] = num (if nil default is 1)

		sets = {
			-- locations
			customLocations = {
				-- custom locations
				["*"] = {
					enable = false,
					inherit = false,
					mounts = {} -- {spellid, spellid, ...}
				}
			},
			specialLocations = {
				-- premade (special) locations
				["*"] = {
					enable = false,
					inherit = false,
					mounts = {} -- {spellid, spellid, ...}
				}
			},
			customSpec = {
				-- custom locations
				["*"] = {
					enable = false,
					inherit = false,
					mounts = {} -- {spellid, spellid, ...}
				}
			},
		}
	}
}

-- config

local function config_toggle_get(info) return addon.db.profile[info[#info]] end
local function config_toggle_set(info, v) addon.db.profile[info[#info]] = v end

local options = {
	name = "MountLeash",
	handler = MountLeash,
	type = 'group',
	args = {
		main = {
			name = GENERAL,
			type = 'group',
			childGroups = "tab",
			args = {
				general = {
					name = GENERAL,
					type = "group",
					order = 10,
					args = {
						enableInBattleground = {
							type = "toggle",
							name = L["Enable In Battlegrounds/Arena"],
							order = 12,
							width = "double",
							get = config_toggle_get,
							set = config_toggle_set
						},
					},
				},
			}
		},
		mounts = {
			type = "group",
			name = L["Enabled Mounts"],
			order = 10,
			cmdHidden = true,
			args = {
				enableAll = {
					type = "execute",
					name = L["Enable All"],
					order = 1,
					func = function(info)
						addon:_Config_MountToggle_SetAll(info, false)
					end
				},
				disableAll = {
					type = "execute",
					name = L["Disable All"],
					order = 2,
					func = function(info)
						addon:_Config_MountToggle_SetAll(info, true)
					end
				},
				useWeightedMounts = {
					-- If we get more pickers, change this to type = "select"
					type = "toggle",
					name = L["Weighted Mounts"],
					order = 3,
					get = function(info)
						return addon.db.profile.weightedMounts
					end,
					set = function(info, v)
						addon.db.profile.weightedMounts = v
						addon:UpdateConfigTables()
					end
				},
				seperator = {
					type = "header",
					name = "",
					order = 9,
				},
				mounts = {
					type = "group",
					name = "",
					order = 10,
					args = {},
					inline = true
				}
			}
		},
		locations = {
			type = "group",
			name = L["Locations"],
			order = 11,
			cmdHidden = true,
			args = {
				specialLocations = {
					type = "group",
					name = L["Special Locations"],
					order = 1,
					args = {
						description = {
							type = "description",
							name = L["Special Locations are predefined areas that cover a certain type of zone."]
						}
					},
					plugins = { data = {} }
				},
				customLocations = {
					type = "group",
					name = L["Custom Locations"],
					order = 2,
					args = {
						addCurrentZone = {
							type = "execute",
							name = L["Add Current Zone"],
							order = 1,
							func = function(info)
								addon:AddCustomLocation(GetZoneText())
							end,
						},
						addCurrentSubZone = {
							type = "execute",
							name = L["Add Current Subzone"],
							order = 1,
							func = function(info)
								addon:AddCustomLocation(GetSubZoneText())
							end,
						},
						--addNamedZone = {
						--
						--}
					},
					plugins = { data = {} }
				},
			}
		},
		specs = {
			type = "group",
			name = L["Specs"],
			order = 12,
			cmdHidden = true,
			args = {
				customSpec = {
					type = "group",
					name = L["Custom Specialization"],
					order = 3,
					args = {
						addCurrentSpec = {
							type = "execute",
							name = L["Add Current Spec"],
							order = 1,
							func = function(info)
								addon:AddCustomSpec(tostring(SpecializationUtil.GetActiveSpecialization()))
							end,
						},
					},
					plugins = { data = {} }
				},
			}
		}
	},
}

local options_slashcmd = {
	name = "MountLeash Slash Command",
	handler = MountLeash,
	type = "group",
	order = -2,
	args = {
		config = {
			type = "execute",
			name = L["Open Configuration"],
			dialogHidden = true,
			order = 1,
			func = function(info) addon:OpenOptions() end
		},
		resummon = {
			type = "execute",
			name = L["Summon Another Mount"],
			desc = L["Desummon your current mount and summon another mount.  Enable summoning if needed."],
			order = 20,
			func = function(info) addon:SummonMount() end
		},
	},
}

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("MountLeashDB", defaults)
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChange")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChange")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChange")

	self.usable_mounts = {} -- spellid, spellid
	self.override_mounts = {} -- spellid, spellid -- OVERRIDE FOR USABLE_MOUNTS
	self.mount_map = {}    -- spellid -> {id,name} (complete)

	self.options = options
	self.options_slashcmd = options_slashcmd

	AceConfig:RegisterOptionsTable(self.name, options)
	self.optionsFrame = AceConfigDialog:AddToBlizOptions(self.name, self.name, nil, "main")
	self.optionsFrame.Mounts = AceConfigDialog:AddToBlizOptions(self.name, L["Enabled Mounts"], self.name, "mounts")
	self.optionsFrame.Locations = AceConfigDialog:AddToBlizOptions(self.name, L["Locations"], self.name, "locations")
	self.optionsFrame.Locations = AceConfigDialog:AddToBlizOptions(self.name, L["Specs"], self.name, "specs")
	self.optionsFrame.About = LibStub("LibAboutPanel").new(self.name, self.name)
	AceConfig:RegisterOptionsTable(self.name .. "SlashCmd", options_slashcmd, { "mountleash", "pl" })

	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("COMPANION_UPDATE")
	self:RegisterEvent("COMPANION_LEARNED")
	self:RegisterEvent("ZONE_CHANGED")
	self:RegisterEvent("ZONE_CHANGED_INDOORS")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	self:RegisterEvent("PLAYER_UPDATE_RESTING")
	self:RegisterEvent("ASCENSION_CA_SPECIALIZATION_ACTIVE_ID_CHANGED")

	self:LoadMounts()                 -- attempt to load mounts (might fail)
	self:ScheduleTimer("LoadMounts", 45) -- sometimes COMPANION_* fails

	-- specifically clicking dismiss will disable us
	-- TODO: perhaps clicking summon when we've been disabled in this
	-- way should reenable us?
	self:InitBroker()
end

function addon:OnEnable()
	if select(4, GetBuildInfo()) >= 50001 then
		self:ScheduleTimer(function()
			self:Print("This version of MountLeash is not designed for WoW 5.0.  Please check for an updated version.")
		end, 10)
	end
end

function addon:IsEnabledSummoning()
	return self.db.profile.enable
end

function addon:EnableSummoning(v)
	local oldv = self.db.profile.enable

	if ((not oldv) ~= (not v)) then
		self.db.profile.enable = v

		-- TODO: is there a better way to trigger config update?
		AceConfigRegistry:NotifyChange("MountLeash")
	end

	if (self.broker) then
		local notR = v and 1 or 0.3
		self.broker.iconG = notR
		self.broker.iconB = notR
	end
end

function addon:OpenOptions()
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
end

-- utility functions

local function HasCompanion(mounttype)
	for id = 1, GetNumCompanions(mounttype) do
		local _, _, _, _, issum = GetCompanionInfo(mounttype, id)
		if (issum) then
			return id
		end
	end
	return nil
end

local function IsMounted()
	return _G.IsMounted()
	--return HasCompanion("MOUNT")
end

local function IsMountted(id)
	if (id) then
		local _, _, _, _, issum = GetCompanionInfo("MOUNT", id)
		if (issum) then
			return id
		end
	else
		return HasCompanion("MOUNT")
	end
end
addon.IsMountted = IsMountted -- expose (mostly for debugging)

local function IsCasting()
	return (UnitCastingInfo("player") or UnitChannelInfo("player"))
end

local BATTLEGROUND_ARENA = { ["pvp"] = 1, ["arena"] = 1 }
local function InBattlegroundOrArena()
	local _, t = IsInInstance()
	return BATTLEGROUND_ARENA[t]
end
addon.InBattlegroundOrArena = InBattlegroundOrArena

local InCombat = InCombatLockdown -- shorthand

local function CanSummonMount()
	return
	-- are we busy?
		not IsCasting()
		and not UnitInVehicle("player")
		and not UnitIsGhost("player")
		and not UnitIsDead("player")
		and not UnitOnTaxi("player")
		and not IsFlying()
		and not IsFalling()
		and GetNumLootItems() == 0
		and HasFullControl()
		-- verify we have mounts
		and GetNumCompanions("MOUNT") > 0
		-- gcd check
		and (not GetCompanionCooldown or GetCompanionCooldown("MOUNT", 1) == 0)
end
addon.CanSummonMount = CanSummonMount -- expose (mostly for debugging)

-- mount list handling

function addon:LoadMounts(updateconfig)
	wipe(self.usable_mounts)

	for i = 1, GetNumCompanions("MOUNT") do
		local _, name, spellid = GetCompanionInfo("MOUNT", i)

		if (not name) then
			return -- mounts not loaded yet?
		end

		if (not self.mount_map[spellid]) then
			self.mount_map[spellid] = {}
		end
		self.mount_map[spellid].id = i
		self.mount_map[spellid].name = name
	end

	if (updateconfig == nil or updateconfig) then
		self:UpdateConfigTables(true)
	end

	-- does nothing if we've called it successfully before
	self:TryInitLocation()
	self:TryInitSpec()
end

function addon:OnProfileChange()
	self:LoadMounts()
end

local L_WeightValues = { "|cffff0000" .. L["Never"] .. "|r",
	"|cffff6600" .. L["Hardly Ever"] .. "|r",
	"|cffff9900" .. L["Rarely"] .. "|r",
	"|cffddff00" .. L["Occasionally"] .. "|r",
	"|cff99ff00" .. L["Sometimes"] .. "|r",
	"|cff00ff00" .. L["Often"] .. "|r" }
function addon:UpdateConfigTables()
	local args = options.args.mounts.args.mounts.args
	local useWeighted = self.db.profile.weightedMounts

	wipe(args)

	for i = 1, GetNumCompanions("MOUNT") do
		local _, name, spellid = GetCompanionInfo("MOUNT", i)

		if (not useWeighted) then
			args[tostring(spellid)] = {
				type = "toggle",
				name = name,
				order = 1,
				get = "Config_MountToggle_Get",
				set = "Config_MountToggle_Set"
			}
		else
			args[tostring(spellid)] = {
				type = "select",
				name = name,
				order = 1,
				values = L_WeightValues,
				get = "Config_MountToggle_Weighted_Get",
				set = "Config_MountToggle_Weighted_Set"
			}
		end
	end

	self:UpdateLocationConfigTables()
	self:UpdateSpecConfigTables()

	-- Config Tables changed!
	AceConfigRegistry:NotifyChange("MountLeash")
end

function addon:Config_MountToggle_Set(info, v)
	if (v) then
		self.db.char.ignore_mounts[tonumber(info[#info])] = false
	else
		self.db.char.ignore_mounts[tonumber(info[#info])] = true
	end

	self:LoadMounts(false)
end

function addon:Config_MountToggle_Get(info)
	return not self.db.char.ignore_mounts[tonumber(info[#info])]
end

function addon:Config_MountToggle_Weighted_Get(info)
	local id = tonumber(info[#info])
	if (not self.db.char.ignore_mounts[id]) then
		return math.floor((self.db.char.weights[id] or 1) * 5) + 1
	end
	return 1
end

function addon:Config_MountToggle_Weighted_Set(info, v)
	local id = tonumber(info[#info])
	if (v == 1) then
		self.db.char.ignore_mounts[id] = true
	else
		self.db.char.ignore_mounts[id] = false
		self.db.char.weights[id] = (v - 1) / 5
	end
	self:LoadMounts(false)
end

function addon:_Config_MountToggle_SetAll(info, v)
	for key in pairs(info.options.args.mounts.args.mounts.args) do
		self.db.char.ignore_mounts[tonumber(key)] = v
	end
	self:LoadMounts(false)
end

-- events

function addon:PLAYER_ENTERING_WORLD()
	self:TryInitSpec()
	self:TryInitLocation()
end

function addon:COMPANION_UPDATE(event, ctype)
	if (ctype == nil) then
		self:LoadMounts()
	end
end

function addon:COMPANION_LEARNED()
	self:LoadMounts()
end

function addon:OnZoneChanged()
	local curZone = GetZoneText()
	if self.currentZone ~= curZone then
		self.currentZone = curZone
		if MountLeash.db.profile.autoSwitchOnZone then
			-- mount will be resummoned shortly
			if (CanSummonMount()) then
				self:DesummonMount(true)
			end
		end
	end
end

function addon:OnSpecChanged(curSpec)
	if self.currentSpec ~= curSpec then
		self.currentSpec = curSpec
		-- mount will be resummoned shortly
		if (CanSummonMount()) then
			self:DesummonMount(true)
		end
	end
end

function addon:ZONE_CHANGED()
	self:DoLocationCheck()
	self:OnZoneChanged()
end

function addon:ZONE_CHANGED_INDOORS()
	self:DoLocationCheck()
	self:OnZoneChanged()
end

function addon:ZONE_CHANGED_NEW_AREA()
	self:DoLocationCheck()
	self:OnZoneChanged()
end

function addon:ASCENSION_CA_SPECIALIZATION_ACTIVE_ID_CHANGED(event, spec)
	self:DoLocationCheck()
	self:OnSpecChanged(spec)
end

function addon:PLAYER_UPDATE_RESTING()
	self:DoLocationCheck()
end

function addon:IsMountSummonReady()
	if (not self.db.profile.enable) then
		return
	elseif (not self.db.profile.enableInCombat and InCombat()) then
		return
	elseif (not self.db.profile.enableInBattleground and InBattlegroundOrArena()) then
		return
	elseif (self.db.profile.disableOutsideCities and not IsResting()) then
		return
	end

	if (CanSummonMount()) then
		return true
	end
end

function addon:HasMount(nocache)
	if (nocache) then
		local mount_id = IsMountted(self.mount_id) or IsMountted()
		self.mount_id = mount_id
		return mount_id
	end
	return self.mount_id
end

local function pick_flat(self, mountlist)
	mountlist = mountlist or self.usable_mounts
	local random_spellid = mountlist[math.random(#mountlist)]
	return self.mount_map[random_spellid].id
end

local function pick_weighted(self, countdown)
	countdown = (countdown or 1000) -- upper bound on tries

	local random_spellid = self.usable_mounts[math.random(#self.usable_mounts)]
	local weight = self.db.char.weights[random_spellid] or 1

	assert(weight > 0)

	if (math.random() > weight and countdown > 0) then
		-- retry
		return pick_weighted(self, countdown - 1)
	end

	return self.mount_map[random_spellid].id
end

function addon:PickMount()
	if (self.override_mounts and #self.override_mounts > 0) then
		return pick_flat(self, self.override_mounts)
	end

	if (not self.db.weightedMounts) then
		return pick_flat(self)
	else
		return pick_weighted(self)
	end
end

function addon:SummonMount()
	if (#self.usable_mounts > 0) then
		CallCompanion("MOUNT", self:PickMount())
	end
end

function addon:DesummonMount(disable)
	DismissCompanion("MOUNT")
	if (not disable or disable == nil) then
		addon:EnableSummoning(false)
	end
end

function addon:SummonMount()
	self:EnableSummoning(true)

	self:DesummonMount(true)
	self:SummonMount()
end

function addon:ToggleMount()
	if (IsMountted()) then
		self:DesummonMount()
	else
		self:EnableSummoning(true)
		if (CanSummonMount()) then
			self:SummonMount()
		end
	end
end
