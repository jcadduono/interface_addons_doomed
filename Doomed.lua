if select(2, UnitClass('player')) ~= 'WARLOCK' then
	DisableAddOn('Doomed')
	return
end

-- useful functions
local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Doomed = {}

SLASH_Doomed1, SLASH_Doomed2 = '/doomed', '/doom'
BINDING_HEADER_DOOMED = 'Doomed'

local function InitializeVariables()
	local function SetDefaults(t, ref)
		for k, v in pairs(ref) do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				print('initializing ' .. k .. ' to ' .. pchar)
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Doomed, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
--[[
			atone = 0.4,
			shield = 0.4,
]]
			interrupt = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 }
		},
		hide = {
			affliction = false,
			demonology = false,
			destruction = false
		},
		alpha = 1,
		frequency = 0.05,
		previous = true,
		always_on = false,
		cooldown = true,
		aoe = false,
		gcd = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		atone = true,
		shield = true,
		interrupt = true,
		auto_aoe = false,
		pot = false
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	AFFLICTION = 1,
	DEMONOLOGY = 2,
	DESTRUCTION = 3
}

local events, abilities, abilityBySpellId, glows = {}, {}, {}, {}

local me, abilityTimer, currentSpec, targetMode, combatStartTime = 0, 0, 0, 0, 0

-- tier set equipped pieces count
local Tier = {
	T19P = 0,
	T20P = 0,
	T21P = 0
}

-- legendary item equipped
local ItemEquipped = {
	SigilOfSuperiorSummoning = false,
	SindoreiSpite = false,
	ReapAndSow = false
}

local var = {
	gcd = 0
}

local targetModes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.AFFLICTION] = {
		{1, ''},
		{2, '2+'},
		{3, '3+'},
		{5, '5+'}
	},
	[SPEC.DEMONOLOGY] = {
		{1, ''},
		{2, '2+'},
		{3, '3+'},
		{5, '5+'}
	},
	[SPEC.DESTRUCTION] = {
		{1, ''},
		{2, '2+'},
		{3, '3+'},
		{5, '5+'}
	}
}

local doomedPanel = CreateFrame('Frame', 'doomedPanel', UIParent)
doomedPanel:SetPoint('CENTER', 0, -169)
doomedPanel:SetFrameStrata('BACKGROUND')
doomedPanel:SetSize(64, 64)
doomedPanel:SetMovable(true)
doomedPanel:Hide()
doomedPanel.icon = doomedPanel:CreateTexture(nil, 'BACKGROUND')
doomedPanel.icon:SetAllPoints(doomedPanel)
doomedPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedPanel.border = doomedPanel:CreateTexture(nil, 'BORDER')
doomedPanel.border:SetAllPoints(doomedPanel)
doomedPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedPanel.border:Hide()
doomedPanel.gcd = CreateFrame('Cooldown', nil, doomedPanel, 'CooldownFrameTemplate')
doomedPanel.gcd:SetAllPoints(doomedPanel)
doomedPanel.dimmer = doomedPanel:CreateTexture(nil, 'OVERLAY')
doomedPanel.dimmer:SetAllPoints(doomedPanel)
doomedPanel.dimmer:SetTexture(0, 0, 0, 0.6)
doomedPanel.dimmer:Hide()
doomedPanel.targets = doomedPanel:CreateFontString(nil, 'OVERLAY')
doomedPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
doomedPanel.targets:SetPoint('BOTTOMRIGHT', doomedPanel, 'BOTTOMRIGHT', -1.5, 3)
doomedPanel.button = CreateFrame('Button', 'doomedPanelButton', doomedPanel)
doomedPanel.button:SetAllPoints(doomedPanel)
doomedPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local doomedPreviousPanel = CreateFrame('Frame', 'doomedPreviousPanel', UIParent)
doomedPreviousPanel:SetPoint('BOTTOMRIGHT', doomedPanel, 'BOTTOMLEFT', -10, -5)
doomedPreviousPanel:SetFrameStrata('BACKGROUND')
doomedPreviousPanel:SetSize(64, 64)
doomedPreviousPanel:Hide()
doomedPreviousPanel:RegisterForDrag('LeftButton')
doomedPreviousPanel:SetScript('OnDragStart', doomedPreviousPanel.StartMoving)
doomedPreviousPanel:SetScript('OnDragStop', doomedPreviousPanel.StopMovingOrSizing)
doomedPreviousPanel:SetMovable(true)
doomedPreviousPanel.icon = doomedPreviousPanel:CreateTexture(nil, 'BACKGROUND')
doomedPreviousPanel.icon:SetAllPoints(doomedPreviousPanel)
doomedPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedPreviousPanel.border = doomedPreviousPanel:CreateTexture(nil, 'BORDER')
doomedPreviousPanel.border:SetAllPoints(doomedPreviousPanel)
doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
local doomedCooldownPanel = CreateFrame('Frame', 'doomedCooldownPanel', UIParent)
doomedCooldownPanel:SetPoint('BOTTOMLEFT', doomedPanel, 'BOTTOMRIGHT', 10, -5)
doomedCooldownPanel:SetSize(64, 64)
doomedCooldownPanel:SetFrameStrata('BACKGROUND')
doomedCooldownPanel:Hide()
doomedCooldownPanel:RegisterForDrag('LeftButton')
doomedCooldownPanel:SetScript('OnDragStart', doomedCooldownPanel.StartMoving)
doomedCooldownPanel:SetScript('OnDragStop', doomedCooldownPanel.StopMovingOrSizing)
doomedCooldownPanel:SetMovable(true)
doomedCooldownPanel.icon = doomedCooldownPanel:CreateTexture(nil, 'BACKGROUND')
doomedCooldownPanel.icon:SetAllPoints(doomedCooldownPanel)
doomedCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedCooldownPanel.border = doomedCooldownPanel:CreateTexture(nil, 'BORDER')
doomedCooldownPanel.border:SetAllPoints(doomedCooldownPanel)
doomedCooldownPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedCooldownPanel.cd = CreateFrame('Cooldown', nil, doomedCooldownPanel, 'CooldownFrameTemplate')
doomedCooldownPanel.cd:SetAllPoints(doomedCooldownPanel)
local doomedInterruptPanel = CreateFrame('Frame', 'doomedInterruptPanel', UIParent)
doomedInterruptPanel:SetPoint('TOPLEFT', doomedPanel, 'TOPRIGHT', 16, 25)
doomedInterruptPanel:SetFrameStrata('BACKGROUND')
doomedInterruptPanel:SetSize(64, 64)
doomedInterruptPanel:Hide()
doomedInterruptPanel:RegisterForDrag('LeftButton')
doomedInterruptPanel:SetScript('OnDragStart', doomedInterruptPanel.StartMoving)
doomedInterruptPanel:SetScript('OnDragStop', doomedInterruptPanel.StopMovingOrSizing)
doomedInterruptPanel:SetMovable(true)
doomedInterruptPanel.icon = doomedInterruptPanel:CreateTexture(nil, 'BACKGROUND')
doomedInterruptPanel.icon:SetAllPoints(doomedInterruptPanel)
doomedInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedInterruptPanel.border = doomedInterruptPanel:CreateTexture(nil, 'BORDER')
doomedInterruptPanel.border:SetAllPoints(doomedInterruptPanel)
doomedInterruptPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedInterruptPanel.cast = CreateFrame('Cooldown', nil, doomedInterruptPanel, 'CooldownFrameTemplate')
doomedInterruptPanel.cast:SetAllPoints(doomedInterruptPanel)
--[[
local doomedAtonementPanel = CreateFrame('Frame', 'doomedAtonementPanel', UIParent)
doomedAtonementPanel:SetPoint('TOPRIGHT', doomedPanel, 'TOPLEFT', -16, 25)
doomedAtonementPanel:SetFrameStrata('BACKGROUND')
doomedAtonementPanel:SetSize(64, 64)
doomedAtonementPanel:Hide()
doomedAtonementPanel:RegisterForDrag('LeftButton')
doomedAtonementPanel:SetScript('OnDragStart', doomedAtonementPanel.StartMoving)
doomedAtonementPanel:SetScript('OnDragStop', doomedAtonementPanel.StopMovingOrSizing)
doomedAtonementPanel:SetMovable(true)
doomedAtonementPanel.icon = doomedAtonementPanel:CreateTexture(nil, 'BACKGROUND')
doomedAtonementPanel.icon:SetAllPoints(doomedAtonementPanel)
doomedAtonementPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedAtonementPanel.border = doomedAtonementPanel:CreateTexture(nil, 'BORDER')
doomedAtonementPanel.border:SetAllPoints(doomedAtonementPanel)
doomedAtonementPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedAtonementPanel.text = doomedAtonementPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
doomedAtonementPanel.text:SetFont("Fonts\\FRIZQT__.TTF", 40, "OUTLINE")
doomedAtonementPanel.text:SetTextColor(1, 1, 1, 1)
doomedAtonementPanel.text:SetAllPoints(doomedAtonementPanel)
doomedAtonementPanel.text:SetJustifyH("CENTER")
doomedAtonementPanel.text:SetJustifyV("CENTER")
local doomedShieldPanel = CreateFrame('Frame', 'doomedShieldPanel', UIParent)
doomedShieldPanel:SetPoint('TOPLEFT', doomedPanel, 'TOPRIGHT', 16, 25)
doomedShieldPanel:SetFrameStrata('BACKGROUND')
doomedShieldPanel:SetSize(64, 64)
doomedShieldPanel:Hide()
doomedShieldPanel:RegisterForDrag('LeftButton')
doomedShieldPanel:SetScript('OnDragStart', doomedShieldPanel.StartMoving)
doomedShieldPanel:SetScript('OnDragStop', doomedShieldPanel.StopMovingOrSizing)
doomedShieldPanel:SetMovable(true)
doomedShieldPanel.icon = doomedShieldPanel:CreateTexture(nil, 'BACKGROUND')
doomedShieldPanel.icon:SetAllPoints(doomedShieldPanel)
doomedShieldPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedShieldPanel.border = doomedShieldPanel:CreateTexture(nil, 'BORDER')
doomedShieldPanel.border:SetAllPoints(doomedShieldPanel)
doomedShieldPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedShieldPanel.cooldown = CreateFrame('Cooldown', nil, doomedShieldPanel, 'CooldownFrameTemplate')
doomedShieldPanel.cooldown:SetAllPoints(doomedShieldPanel)
doomedShieldPanel.cooldown:SetFrameStrata('BACKGROUND')
doomedShieldPanel.text = doomedShieldPanel.cooldown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
doomedShieldPanel.text:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
doomedShieldPanel.text:SetTextColor(1, 1, 1, 1)
doomedShieldPanel.text:SetAllPoints(doomedShieldPanel)
doomedShieldPanel.text:SetJustifyH("CENTER")
doomedShieldPanel.text:SetJustifyV("CENTER")
]]

local Ability = {}
Ability.__index = Ability

function Ability.add(spellId, buff, player, spellId2)
	local name, _, icon = GetSpellInfo(spellId)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2 or 0,
		name = name,
		icon = icon,
		mana_cost = 0,
		shard_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		requires_charge = false,
		requires_pet = false,
		triggers_gcd = true,
		hasted_duration = false,
		known = IsPlayerSpell(spellId),
		auraTarget = buff == 'pet' and 'pet' or buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities[#abilities + 1] = ability
	abilityBySpellId[spellId] = ability
	return ability
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable(seconds)
	if self:cost() > var.mana then
		return false
	end
	if self.shard_cost > var.soul_shards then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

function Ability:remains()
	if self.buff_duration > 0 and self:casting() then
		return self:duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			return max(expires - var.time - var.cast_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up(excludeCasting)
	if not excludeCasting and self.buff_duration > 0 and self:casting() then
		return true
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if id == self.spellId or id == self.spellId2 then
			return expires == 0 or expires - var.time > var.cast_remains
		end
	end
end

function Ability:down(excludeCasting)
	return not self:up(excludeCasting)
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	return start > 0 and max(0, (duration - (var.time - start)) - var.cast_remains) or 0
end

function Ability:stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			return (expires == 0 or expires - var.time > var.cast_remains) and count or 0
		end
	end
	return 0
end

function Ability:cost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * var.mana_max) or 0
end

function Ability:charges()
	return GetSpellCharges(self.spellId) or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return var.cast_name == self.name
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	return castTime / 1000
end

function Ability:castRegen()
	return var.regen * max(1, self:castTime())
end

function Ability:tickInterval()
	return self.tick_interval - (self.tick_interval * (UnitSpellHaste('player') / 100))
end

function Ability:previous()
	if self:casting() or self:channeling() then
		return true
	end
	return var.last_gcd == self or var.last_ability == self
end

--[[
function Ability:recordTargetsHit()
	if not self.first_hit_time then
		self.first_hit_time = var.time
		self.target_hit_count = 0
	end
	self.target_hit_count = self.target_hit_count + 1
	for i = 1, #targetModes[currentSpec] do
		if self.target_hit_count >= targetModes[currentSpec][i][1] and targetModes[currentSpec][i][1] > targetModes[currentSpec][targetMode][1] then
			Doomed_SetTargetMode(i)
		end
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and var.time - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		local highestTargetMode = 1
		for i = 1, #targetModes[currentSpec] do
			if self.target_hit_count >= targetModes[currentSpec][i][1] and targetModes[currentSpec][i][1] > highestTargetMode then
				highestTargetMode = i
			end
		end
		if highestTargetMode ~= targetMode then
			Doomed_SetTargetMode(highestTargetMode)
		end
	end
end
]]

local SummonedPet = {}
SummonedPet.__index = SummonedPet

function SummonedPet.add(name, summonedBy, count)
	local pet = {
		name = name,
		summoned_by = summonedBy,
		summon_count = count or 1
	}
	setmetatable(pet, SummonedPet)
	return pet
end

function SummonedPet:remains()
	local _, name, startTime, duration
	local remains = 0
	for i = 1, 6 do
		_, name, startTime, duration = GetTotemInfo(i)
		if name == self.name then
			remains = max(remains, startTime + duration - var.time - var.cast_remains)
		end
	end
	return remains
end

function SummonedPet:up()
	return self:remains() > 0
end

function SummonedPet:down()
	return self:remains() <= 0
end

function SummonedPet:stack()
	local _, name, startTime, duration
	local stack = 0
	for i = 1, 6 do
		_, name, startTime, duration = GetTotemInfo(i)
		if name == self.name and startTime + duration - var.time > var.cast_remains then
			stack = stack + 1
		end
	end
	return stack
end

function SummonedPet:count()
	return self.summon_count * self:stack()
end

function SummonedPet:ready()
	return self.summoned_by:ready()
end

function SummonedPet:cooldown()
	return self.summoned_by:cooldown()
end

-- Warlock Abilities
---- Multiple Specializations
local LifeTap = Ability.add(1454, false, true) -- Used for GCD calculation
LifeTap.mana_cost = -30
local ShadowLock = Ability.add(171138, 'pet', false)
ShadowLock.cooldown_duration = 24
local SpellLock = Ability.add(119910, 'pet', false)
SpellLock.cooldown_duration = 24
------ Talents
local DemonicPower = Ability.add(196099, true, true) -- Grimoire of Sacrifice buff
local GrimoireOfSacrifice = Ability.add(108503, true, true)
local GrimoireOfSupremacy = Ability.add(152107, true, true)
local SoulHarvest = Ability.add(196098, true, true)
SoulHarvest.buff_duration = 12
SoulHarvest.cooldown_duration = 120
------ Procs
local SoulConduit = Ability.add(215941, true, true)
------ Permanent Pets
local SummonDoomguard = Ability.add(157757, false, true) -- Grimoire of Supremacy
SummonDoomguard.shard_cost = 1
local SummonInfernal = Ability.add(157898, false, true) -- Grimoire of Supremacy
SummonInfernal.shard_cost = 1
local SummonImp = Ability.add(688, false, true)
SummonImp.shard_cost = 1
local SummonFelhunter = Ability.add(691, false, true)
SummonFelhunter.shard_cost = 1
local SummonVoidwalker = Ability.add(697, false, true)
SummonVoidwalker.shard_cost = 1
local SummonSuccubus = Ability.add(712, false, true)
SummonSuccubus.shard_cost = 1
local SummonFelguard = Ability.add(30146, false, true)
SummonFelguard.shard_cost = 1
---- Affliction
local Agony = Ability.add(980, false, true)
Agony.mana_cost = 3
Agony.buff_duration = 18
Agony.tick_interval = 2
local Corruption = Ability.add(172, false, true, 146739)
Corruption.mana_cost = 3
Corruption.buff_duration = 14
Corruption.tick_interval = 2
local DeadwindHarvester = Ability.add(216708, true, true)
local DrainSoul = Ability.add(198590, false, true)
DrainSoul.mana_cost = 3
DrainSoul.buff_duration = 6
DrainSoul.tick_interval = 1
DrainSoul.hasted_duration = true
local ReapSouls = Ability.add(216698, true, true, 216695)
ReapSouls.cooldown_duration = 5
ReapSouls.buff_duration = 60
ReapSouls.triggers_gcd = false
local SeedOfCorruption = Ability.add(27243, false, true)
SeedOfCorruption.shard_cost = 1
SeedOfCorruption.buff_duration = 18
SeedOfCorruption.hasted_duration = true
local TormentedSouls = ReapSouls
local UnstableAffliction = Ability.add(30108, false, true)
UnstableAffliction.shard_cost = 1
UnstableAffliction.buff_duration = 8
UnstableAffliction.tick_interval = 2
UnstableAffliction.hasted_duration = true
local UnstableAffliction1 = Ability.add(233490, false, true)
local UnstableAffliction2 = Ability.add(233496, false, true)
local UnstableAffliction3 = Ability.add(233497, false, true)
local UnstableAffliction4 = Ability.add(233498, false, true)
local UnstableAffliction5 = Ability.add(233499, false, true)
------ Talents
local Contagion = Ability.add(196105, false, true)
local DeathsEmbrace = Ability.add(234876, false, true)
local EmpoweredLifeTap = Ability.add(235157, true, true, 235156)
EmpoweredLifeTap.buff_duration = 20
local Haunt = Ability.add(48181, false, true)
Haunt.mana_cost = 5
Haunt.buff_duration = 10
Haunt.cooldown_duration = 25
local MaleficGrasp = Ability.add(235155, false, true)
local PhantomSingularity = Ability.add(205179, false, true)
PhantomSingularity.buff_duration = 16
PhantomSingularity.cooldown_duration = 40
PhantomSingularity.hasted_duration = true
local SiphonLife = Ability.add(63106, false, true)
SiphonLife.tick_interval = 3
local SowTheSeeds = Ability.add(196226, false, true)
---- Demonology
------ Base Abilities
local CallDreadstalkers = Ability.add(104316, true, true)
CallDreadstalkers.cooldown_duration = 15
CallDreadstalkers.shard_cost = 2
local Demonwrath = Ability.add(193440, 'pet', true)
Demonwrath.mana_cost = 2.5
Demonwrath.buff_duration = 3
Demonwrath.tick_interval = 1
Demonwrath.hasted_duration = true
DemonicEmpowerment = Ability.add(193396, 'pet', true)
DemonicEmpowerment.requires_pet = true
DemonicEmpowerment.mana_cost = 6
DemonicEmpowerment.buff_duration = 12
local Doom = Ability.add(603, false, true)
Doom.mana_cost = 2
Doom.buff_duration = 20
Doom.tick_interval = 20
Doom.hasted_duration = true
local DrainLife = Ability.add(234153, false, true)
DrainLife.mana_cost = 3
DrainLife.buff_duration = 6
DrainLife.tick_interval = 1
DrainLife.hasted_duration = true
local HandOfGuldan = Ability.add(105174, false, true)
HandOfGuldan.shard_cost = 4
local ShadowBolt = Ability.add(686, false, true)
ShadowBolt.mana_cost = 6
ShadowBolt.shard_cost = -1
local SummonDoomguardCD = Ability.add(18540, false, true)
SummonDoomguardCD.cooldown_duration = 180
SummonDoomguardCD.shard_cost = 1
local SummonInfernalCD = Ability.add(1122, false, true)
SummonInfernalCD.cooldown_duration = 180
SummonInfernalCD.shard_cost = 1
local ThalkielsConsumption = Ability.add(211714, false, true)
ThalkielsConsumption.cooldown_duration = 45
local Wrathstorm = Ability.add(115831, 'pet', true)
Wrathstorm.requires_pet = true
Wrathstorm.triggers_gcd = false
Wrathstorm.buff_duration = 6
Wrathstorm.tick_interval = 1
Wrathstorm.cooldown_duration = 45
------ Talents Abilities
local Demonbolt = Ability.add(157695, false, true)
Demonbolt.mana_cost = 4.8
Demonbolt.shard_cost = -1
local GrimoireFelguard = Ability.add(111898, false, true)
GrimoireFelguard.cooldown_duration = 90
GrimoireFelguard.shard_cost = 1
local HandOfDoom = Ability.add(196283, false, true)
local Implosion = Ability.add(196277, false, true)
Implosion.mana_cost = 6
local Shadowflame = Ability.add(205181, false, true)
Shadowflame.requires_charge = true
Shadowflame.cooldown_duration = 14
Shadowflame.shard_cost = -1
local SummonDarkglare = Ability.add(205180, false, true)
SummonDarkglare.cooldown_duration = 24
SummonDarkglare.shard_cost = 1
------ Procs
local DemonicCalling = Ability.add(205145, true, true, 205146)
local DemonicSynergy = Ability.add(171975, true, false, 171982)
local DemonicSynergyPet = Ability.add(171975, 'pet', true, 171982)
local PowerTrip = Ability.add(196605, true, true)
local ShadowyInspiration = Ability.add(196269, true, true, 196606)
---- Summoned Pets
local Darkglare = SummonedPet.add('Darkglare', SummonDarkglare)
local Dreadstalkers = SummonedPet.add('Dreadstalkers', CallDreadstalkers, 2)
local WildImps = SummonedPet.add('Wild Imps', HandOfGuldan, 4)
-- Tier Bonuses
-- Racials
local ArcaneTorrent = Ability.add(136222, true, false) -- Blood Elf
ArcaneTorrent.mana_cost = -3
ArcaneTorrent.triggers_gcd = false
-- Potions
local ProlongedPower = Ability.add(229206, true, true)
ProlongedPower.triggers_gcd = false
-- Trinkets

-- Start Ability Modifications

function ReapSouls:usable()
	if self:stack() == 0 then
		return false
	end
	return Ability.usable(self)
end

function Corruption:up()
	return Ability.up(self) or SeedOfCorruption:up()
end

function Corruption:remains()
	if SeedOfCorruption:up() then
		return Corruption:duration()
	end
	return Ability.remains(self)
end

function UnstableAffliction:stack()
	return (
		(UnstableAffliction1:up() and 1 or 0) +
		(UnstableAffliction2:up() and 1 or 0) +
		(UnstableAffliction3:up() and 1 or 0) +
		(UnstableAffliction4:up() and 1 or 0) +
		(UnstableAffliction5:up() and 1 or 0))
end

function UnstableAffliction:remains()
	return max(UnstableAffliction1:remains(), UnstableAffliction2:remains(), UnstableAffliction3:remains(), UnstableAffliction4:remains(), UnstableAffliction5:remains())
end

function UnstableAffliction:next()
	if not Ability.up(UnstableAffliction1, true) then
		return UnstableAffliction1
	end
	if not Ability.up(UnstableAffliction2, true) then
		return UnstableAffliction2
	end
	if not Ability.up(UnstableAffliction3, true) then
		return UnstableAffliction3
	end
	if not Ability.up(UnstableAffliction4, true) then
		return UnstableAffliction4
	end
	if not Ability.up(UnstableAffliction5, true) then
		return UnstableAffliction5
	end
	return UnstableAffliction1
end

function UnstableAffliction:up()
	return UnstableAffliction1:up() or UnstableAffliction2:up() or UnstableAffliction3:up() or UnstableAffliction4:up() or UnstableAffliction5:up()
end

function UnstableAffliction1:remains()
	if UnstableAffliction:casting() and UnstableAffliction:next() == self then
		return UnstableAffliction:duration()
	end
	return Ability.remains(self)
end

UnstableAffliction2.remains = UnstableAffliction1.remains
UnstableAffliction3.remains = UnstableAffliction1.remains
UnstableAffliction4.remains = UnstableAffliction1.remains
UnstableAffliction5.remains = UnstableAffliction1.remains

function UnstableAffliction1:up()
	if UnstableAffliction:casting() and UnstableAffliction:next() == self then
		return true
	end
	return Ability.up(self)
end

UnstableAffliction2.up = UnstableAffliction1.up
UnstableAffliction3.up = UnstableAffliction1.up
UnstableAffliction4.up = UnstableAffliction1.up
UnstableAffliction5.up = UnstableAffliction1.up

function SummonDoomguard:up()
	return UnitCreatureFamily('pet') == 'Doomguard' or UnitCreatureFamily('pet') == 'Terrorguard'
end

function SummonInfernal:up()
	return UnitCreatureFamily('pet') == 'Infernal' or UnitCreatureFamily('pet') == 'Abyssal'
end

function SummonImp:up()
	return UnitCreatureFamily('pet') == 'Imp' or UnitCreatureFamily('pet') == 'Fel Imp'
end

function SummonFelhunter:up()
	return UnitCreatureFamily('pet') == 'Felhunter' or UnitCreatureFamily('pet') == 'Observer'
end

function SummonVoidwalker:up()
	return UnitCreatureFamily('pet') == 'Voidwalker' or UnitCreatureFamily('pet') == 'Voidlord'
end

function SummonSuccubus:up()
	return UnitCreatureFamily('pet') == 'Succubus' or UnitCreatureFamily('pet') == 'Shivarra'
end

function SummonFelguard:up()
	return UnitCreatureFamily('pet') == 'Felguard' or UnitCreatureFamily('pet') == 'Wrathguard'
end

-- End Ability Modifications

local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

local function GetAbilityCasting()
	if not var.cast_name then
		return
	end
	for i = 1,#abilities do
		if abilities[i].name == var.cast_name then
			return abilities[i]
		end
	end
end

local function GetCastManaRegen()
	return var.regen * var.cast_remains - (var.cast_ability and var.cast_ability:cost() or 0)
end

local function GetAvailableSoulShards()
	return min(5, max(0, UnitPower('player', SPELL_POWER_SOUL_SHARDS) - (var.cast_ability and var.cast_ability.shard_cost or 0)))
end

local function UpdateVars()
	local _, start, duration, remains, hp
	var.last_main = var.main
	var.last_cd = var.cd
	var.time = GetTime()
	var.gcd = 1.5 - (1.5 * (UnitSpellHaste('player') / 100))
	start, duration = GetSpellCooldown(LifeTap.spellId)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	var.cast_name, _, _, _, _, remains = UnitCastingInfo('player')
	var.cast_remains = remains and remains / 1000 - var.time or var.gcd_remains
	var.cast_ability = GetAbilityCasting()
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.regen = GetPowerRegen()
	var.mana_regen = GetCastManaRegen()
	var.mana_max = UnitPowerMax('player', SPELL_POWER_MANA)
	var.mana = min(var.mana_max, floor(UnitPower('player', SPELL_POWER_MANA) + var.mana_regen))
	var.soul_shards = GetAvailableSoulShards()
	Target.healthArray[#Target.healthArray + 1] = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthPercentage = Target.guid == 0 and 100 or UnitHealth('target') / UnitHealthMax('target') * 100
	hp = Target.healthArray[1] - Target.healthArray[#Target.healthArray]
	Target.timeToDie = hp > 0 and Target.healthArray[#Target.healthArray] / (hp / 3) or 600
end

local function Mana()
	return var.mana
end

local function ManaPct()
	return var.mana / var.mana_max * 100
end

local function ManaDeficit()
	return var.mana_max - var.mana
end

local function ManaRegen()
	return var.mana_regen
end

local function ManaMax()
	return var.mana_max
end

local function SoulShards()
	return var.soul_shards
end

local function SpellHasteFactor()
	return var.haste_factor
end

local function GCD()
	return var.gcd
end

local function GCDRemains()
	return var.gcd_remains
end

local function PlayerIsMoving()
	return GetUnitSpeed('player') ~= 0
end

local function PetIsSummoned()
	return UnitExists('pet') or IsMounted()
end

local function Enemies()
	return targetModes[currentSpec][targetMode][1]
end

local function TimeInCombat()
	return combatStartTime > 0 and var.time - combatStartTime or 0
end

function ProlongedPower:cooldown()
	local startTime, duration = GetItemCooldown(142117)
	return duration - (var.time - startTime)
end

local function BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if id == 2825 or id == 32182 or id == 80353 or id == 90355 or id == 160452 or id == 146555 then
			return true
		end
	end
end

local function UseCooldown(ability, overwrite, always)
	if always or (Doomed.cooldown and (not Doomed.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function DetermineAbilityAffliction()
	if TimeInCombat() == 0 then
		if not PetIsSummoned() then
			if GrimoireOfSupremacy.known then
				return Enemies() > 1 and SummonInfernal or SummonDoomguard
			end
			if not GrimoireOfSacrifice.known or (GrimoireOfSacrifice.known and DemonicPower:remains() < 300) then
				return SummonFelhunter
			end
		end
		if GrimoireOfSacrifice.known and PetIsSummoned() then
			return GrimoireOfSacrifice
		end
		if ManaPct() < 70 or (EmpoweredLifeTap.known and EmpoweredLifeTap:refreshable()) then
			return LifeTap
		end
		if Doomed.pot and ProlongedPower:ready() then
			UseCooldown(ProlongedPower)
		end
	end
	if ReapSouls:usable() and (DeadwindHarvester:down() or (not (DrainSoul:channeling() and UnstableAffliction:up()) and DeadwindHarvester:remains() < 3)) and TimeInCombat() > 5 and (TormentedSouls:stack() >= min(4 + Enemies(), 9) or Target.timeToDie <= (TormentedSouls:stack() * (ReapAndSow and 6.5 or 5) + (DeadwindHarvester:remains() * (ItemEquipped.ReapAndSow and 6.5 or 5) % 12 * (ItemEquipped.ReapAndSow and 6.5 or 5)))) then
		UseCooldown(ReapSouls, true, true)
	end
	if Agony:remains() <= (Agony:tickInterval() + GCD()) then
		return Agony
	end
	if SowTheSeeds.known and Enemies() >= 3 and SoulShards() == 5 then
		return SeedOfCorruption
	end
	if SoulShards() == 5 then
		return UnstableAffliction
	end
	if Target.timeToDie < GCD() * 2 and SoulShards() < 5 then
		return DrainSoul
	end
	if EmpoweredLifeTap.known and EmpoweredLifeTap:remains() <= GCD() then
		return LifeTap
	end
	if not GrimoireOfSupremacy.known then
		if SummonDoomguardCD:ready() and Enemies() <= 2 and (Target.timeToDie > 180 or Target.healthPercentage <= 20 or Target.timeToDie < 30) then
			UseCooldown(SummonDoomguardCD)
		elseif SummonInfernalCD:ready() and Enemies() > 2 then
			UseCooldown(SummonInfernalCD)
		end
	end
	if SiphonLife.known and SiphonLife:remains() <= (SiphonLife:tickInterval() + GCD()) and Target.timeToDie > (SiphonLife:tickInterval() * 3) then
		return SiphonLife
	end
	if (not SowTheSeeds.known or Enemies() < 3) and Enemies() < 5 and Corruption:remains() <= (Corruption:tickInterval() + GCD()) and Target.timeToDie > (Corruption:tickInterval() * 3) then
		return Corruption
	end
	if PhantomSingularity.known and PhantomSingularity:ready() then
		UseCooldown(PhantomSingularity)
	end
	if SoulHarvest.known and UnstableAffliction:stack() > 1 and SoulHarvest:remains() <= 8 and (not DeathsEmbrace.known or Target.timeToDie >= 136 or Target.timeToDie <= 40) then
		UseCooldown(SoulHarvest)
	end
	if Doomed.pot and ProlongedPower:ready() and (Target.timeToDie <= 70 or ((not SoulHarvest.known or SoulHarvest:remains() > 12) and UnstableAffliction:stack() >= 2)) then
		UseCooldown(ProlongedPower)
	end
	if Agony:usable() and Agony:refreshable() and Target.timeToDie >= Agony:remains() and (UnstableAffliction:down() or (SiphonLife:remains() > 10 and Corruption:remains() > 10)) then
		return Agony
	end
	if SiphonLife.known and SiphonLife:refreshable() and Target.timeToDie >= SiphonLife:remains() and (UnstableAffliction:down() or (Agony:remains() > 10 and Corruption:remains() > 10)) then
		return SiphonLife
	end
	if Corruption:usable() and (not SowTheSeeds.known or Enemies() < 3) and Enemies() < 5 and Corruption:refreshable() and Target.timeToDie >= Corruption:remains() and (UnstableAffliction:down() or (SiphonLife:remains() > 10 and Agony:remains() > 10)) then
		return Corruption
	end
	if ((EmpoweredLifeTap.known and EmpoweredLifeTap:refreshable()) or (Target.timeToDie > 15 and ManaPct() < 10)) and not (DrainSoul:channeling() and UnstableAffliction:stack() > 1) then
		return LifeTap
	end
	if SeedOfCorruption:usable() and ((SowTheSeeds.known and Enemies() >= 3) or (Enemies() >= 5 and Corruption:remains() <= SeedOfCorruption:castTime())) then
		return SeedOfCorruption
	end
	if UnstableAffliction:usable() then
		if Agony:remains() > UnstableAffliction:castTime() + (6.5 * SpellHasteFactor()) and (UnstableAffliction:down() or (MaleficGrasp.known and SoulShards() >= 2 and UnstableAffliction:previous() and UnstableAffliction:stack() < SoulShards())) then
			return UnstableAffliction
		end
		if Contagion.known and UnstableAffliction:remains() < UnstableAffliction:castTime() and (not MaleficGrasp.known or UnstableAffliction:stack() <= 2) then
			return UnstableAffliction
		end
		if Target.timeToDie < 30 and (not Contagion.known or SoulShards() >= 2 or Target.timeToDie < UnstableAffliction:castTime() + UnstableAffliction:duration()) then
			return UnstableAffliction
		end
		if Enemies() > 1 and SoulShards() >= 4 then
			return UnstableAffliction
		end
	end
	if ReapSouls:usable() and DeadwindHarvester:remains() < UnstableAffliction:remains() and UnstableAffliction:stack() > 1 then
		UseCooldown(ReapSouls, true, true)
	end
	if ManaPct() < 10 or (LifeTap:previous() and UnstableAffliction:down() and ManaPct() < 50) then
		return LifeTap
	end
	if not DrainSoul:channeling() and (not MaleficGrasp.known or UnstableAffliction:stack() <= 1) then
		if Agony:usable() and Agony:refreshable() then
			return Agony
		end
		if Corruption:usable() and Corruption:refreshable() then
			return Corruption
		end
		if SiphonLife.known and SiphonLife:refreshable() then
			return SiphonLife
		end
	end
	if not PlayerIsMoving() then
		return DrainSoul
	end
	if ManaPct() < 80 then
		return LifeTap
	end
	if Agony:remains() < (Agony:duration() - (3 * Agony:tickInterval())) then
		return Agony
	end
	if SiphonLife:remains() < (SiphonLife:duration() - (3 * SiphonLife:tickInterval())) then
		return SiphonLife
	end
	if Corruption:remains() < (Corruption:duration() - (3 * Corruption:tickInterval())) then
		return Corruption
	end
	return DrainSoul
end

--[[
actions=implosion,if=wild_imp_remaining_duration<=action.shadow_bolt.execute_time&(buff.demonic_synergy.remains|talent.soul_conduit.enabled|(!talent.soul_conduit.enabled&spell_targets.implosion>1)|wild_imp_count<=4)
actions+=/variable,name=3min,value=doomguard_no_de>0|infernal_no_de>0
actions+=/variable,name=no_de1,value=dreadstalker_no_de>0|darkglare_no_de>0|doomguard_no_de>0|infernal_no_de>0|service_no_de>0
actions+=/variable,name=no_de2,value=(variable.3min&service_no_de>0)|(variable.3min&wild_imp_no_de>0)|(variable.3min&dreadstalker_no_de>0)|(service_no_de>0&dreadstalker_no_de>0)|(service_no_de>0&wild_imp_no_de>0)|(dreadstalker_no_de>0&wild_imp_no_de>0)|(prev_gcd.1.hand_of_guldan&variable.no_de1)
actions+=/implosion,if=prev_gcd.1.hand_of_guldan&((wild_imp_remaining_duration<=3&buff.demonic_synergy.remains)|(wild_imp_remaining_duration<=4&spell_targets.implosion>2))
actions+=/shadowflame,if=(debuff.shadowflame.stack>0&remains<action.shadow_bolt.cast_time+travel_time)&spell_targets.demonwrath<5
actions+=/summon_infernal,if=(!talent.grimoire_of_supremacy.enabled&spell_targets.infernal_awakening>2)&equipped.132369
actions+=/summon_doomguard,if=!talent.grimoire_of_supremacy.enabled&spell_targets.infernal_awakening<=2&equipped.132369
actions+=/call_dreadstalkers,if=((!talent.summon_darkglare.enabled|talent.power_trip.enabled)&(spell_targets.implosion<3|!talent.implosion.enabled))&!(soul_shard=5&buff.demonic_calling.remains)
actions+=/doom,cycle_targets=1,if=(!talent.hand_of_doom.enabled&target.time_to_die>duration&(!ticking|remains<duration*0.3))&!(variable.no_de1|prev_gcd.1.hand_of_guldan)
actions+=/shadowflame,if=(charges=2&soul_shard<5)&spell_targets.demonwrath<5&!variable.no_de1
actions+=/service_pet
actions+=/summon_doomguard,if=!talent.grimoire_of_supremacy.enabled&spell_targets.infernal_awakening<=2&(target.time_to_die>180|target.health.pct<=20|target.time_to_die<30)
actions+=/summon_infernal,if=!talent.grimoire_of_supremacy.enabled&spell_targets.infernal_awakening>2
actions+=/summon_doomguard,if=talent.grimoire_of_supremacy.enabled&spell_targets.summon_infernal=1&equipped.132379&!cooldown.sindorei_spite_icd.remains
actions+=/summon_infernal,if=talent.grimoire_of_supremacy.enabled&spell_targets.summon_infernal>1&equipped.132379&!cooldown.sindorei_spite_icd.remains
actions+=/shadow_bolt,if=buff.shadowy_inspiration.remains&soul_shard<5&!prev_gcd.1.doom&!variable.no_de2
actions+=/summon_darkglare,if=prev_gcd.1.hand_of_guldan|prev_gcd.1.call_dreadstalkers|talent.power_trip.enabled
actions+=/summon_darkglare,if=cooldown.call_dreadstalkers.remains>5&soul_shard<3
actions+=/summon_darkglare,if=cooldown.call_dreadstalkers.remains<=action.summon_darkglare.cast_time&(soul_shard>=3|soul_shard>=1&buff.demonic_calling.react)
actions+=/call_dreadstalkers,if=talent.summon_darkglare.enabled&(spell_targets.implosion<3|!talent.implosion.enabled)&(cooldown.summon_darkglare.remains>2|prev_gcd.1.summon_darkglare|cooldown.summon_darkglare.remains<=action.call_dreadstalkers.cast_time&soul_shard>=3|cooldown.summon_darkglare.remains<=action.call_dreadstalkers.cast_time&soul_shard>=1&buff.demonic_calling.react)
actions+=/hand_of_guldan,if=soul_shard>=4&(((!(variable.no_de1|prev_gcd.1.hand_of_guldan)&(pet_count>=13&!talent.shadowy_inspiration.enabled|pet_count>=6&talent.shadowy_inspiration.enabled))|!variable.no_de2|soul_shard=5)&talent.power_trip.enabled)
actions+=/hand_of_guldan,if=(soul_shard>=3&prev_gcd.1.call_dreadstalkers&!artifact.thalkiels_ascendance.rank)|soul_shard>=5|(soul_shard>=4&cooldown.summon_darkglare.remains>2)
actions+=/demonic_empowerment,if=(((talent.power_trip.enabled&(!talent.implosion.enabled|spell_targets.demonwrath<=1))|!talent.implosion.enabled|(talent.implosion.enabled&!talent.soul_conduit.enabled&spell_targets.demonwrath<=3))&(wild_imp_no_de>3|prev_gcd.1.hand_of_guldan))|(prev_gcd.1.hand_of_guldan&wild_imp_no_de=0&wild_imp_remaining_duration<=0)|(prev_gcd.1.implosion&wild_imp_no_de>0)
actions+=/demonic_empowerment,if=variable.no_de1|prev_gcd.1.hand_of_guldan
actions+=/use_items
actions+=/berserking
actions+=/blood_fury
actions+=/soul_harvest,if=!buff.soul_harvest.remains
actions+=/potion,name=prolonged_power,if=buff.soul_harvest.remains|target.time_to_die<=70|trinket.proc.any.react
actions+=/shadowflame,if=charges=2&spell_targets.demonwrath<5
actions+=/thalkiels_consumption,if=(dreadstalker_remaining_duration>execute_time|talent.implosion.enabled&spell_targets.implosion>=3)&(wild_imp_count>3&dreadstalker_count<=2|wild_imp_count>5)&wild_imp_remaining_duration>execute_time
actions+=/life_tap,if=mana.pct<=15|(mana.pct<=65&((cooldown.call_dreadstalkers.remains<=0.75&soul_shard>=2)|((cooldown.call_dreadstalkers.remains<gcd*2)&(cooldown.summon_doomguard.remains<=0.75|cooldown.service_pet.remains<=0.75)&soul_shard>=3)))
actions+=/demonwrath,chain=1,interrupt=1,if=spell_targets.demonwrath>=3
actions+=/demonwrath,moving=1,chain=1,interrupt=1
actions+=/demonbolt
actions+=/shadow_bolt,if=buff.shadowy_inspiration.remains
actions+=/demonic_empowerment,if=artifact.thalkiels_ascendance.rank&talent.power_trip.enabled&!talent.demonbolt.enabled&talent.shadowy_inspiration.enabled
actions+=/shadow_bolt
actions+=/life_tap
]]

local function DetermineAbilityDemonology()
	if Implosion.known and Implosion:ready() and WildImps:remains() <= ShadowBolt:castTime() and (DemonicSynergy:up() or SoulConduit.known or (not SoulConduit.known and Enemies() > 1) or WildImps:count() <= 4) then
		return Implosion
	end
	if CallDreadstalkers:usable() and ((not SummonDarkglare.known or PowerTrip.known) and (Enemies() < 3 or not Implosion.known())) and not (SoulShards() == 5 and DemonicCalling:up()) then
		return CallDreadstalkers
	end
	if ManaPct() < 5 then
		return LifeTap
	end
	if not HandOfDoom.known and Target.timeToDie > 18 and Doom:refreshable() then
		return Doom
	end
	if Shadowflame.known and Shadowflame:ready() and Shadowflame:charges() == 2 and SoulShards() < 5 and Enemies() < 5 then
		return Shadowflame
	end
	if ShadowyInspiration.known and ShadowBolt:usable() and ShadowyInspiration:up() and SoulShards() < 5 then
		return ShadowBolt
	end
	if SummonDarkglare.known and CallDreadstalkers:usable() and (Enemies() < 3 or not Implosion.known) and (SummonDarkglare:cooldown() > 2 or (SummonDarkglare:cooldown() <= CallDreadstalkers:castTime() and SoulShards() >= 3) or (SummonDarkglare:cooldown() <= CallDreadstalkers:castTime() and SoulShards() >= 1 and DemonicCalling:up())) then
		return CallDreadstalkers
	end
	if HandOfGuldan:usable() and SoulShards() == 5 then
		return HandOfGuldan
	end
	if HandOfGuldan:casting() and DemonicEmpowerment:usable() then
		return DemonicEmpowerment
	end
	if SoulHarvest.known and SoulHarvest:ready() and SoulHarvest:down() then
		return SoulHarvest
	end
	if Shadowflame.known and Shadowflame:ready() and Shadowflame:charges() == 2 and Enemies() < 5 then
		return Shadowflame
	end
	if ThalkielsConsumption:ready() and (Dreadstalkers:remains() > ThalkielsConsumption:castTime() or (Implosion.known and Enemies() >= 3)) and (WildImps:count() > 3 and Dreadstalkers:count() <= 2 or WildImps:count() > 5) and WildImps:remains() > ThalkielsConsumption:castTime() then
		return ThalkielsConsumption
	end
	if ManaPct() <= 15 or (ManaPct() <= 65 and ((Dreadstalkers:cooldown() <= 0.75 and SoulShards() >= 2) or ((Dreadstalkers:cooldown() < GCD() * 2) and (SummonDoomguardCD:cooldown() <= 0.75) and SoulShards() >= 3))) then
		return LifeTap
	end
	if Enemies() >= 3 or PlayerIsMoving() then
		return Demonwrath
	end
	if Demonbolt.known and Demonbolt:usable() then
		return Demonbolt
	end
	if ShadowyInspiration.known and ShadowyInspiration:up() then
		return ShadowBolt
	end
	if PowerTrip.known and not Demonbolt.known and ShadowyInspiration.known then
		return DemonicEmpowerment
	end
	if ShadowBolt:usable() then
		return ShadowBolt
	end
	if ManaPct() < 80 then
		return LifeTap
	end
end

local function DetermineAbilityDestruction()
	return ShadowBolt
end

local function DetermineAbility()
	var.cd = nil
	var.interrupt = nil
	if currentSpec == SPEC.AFFLICTION then
		return DetermineAbilityAffliction()
	elseif currentSpec == SPEC.DEMONOLOGY then
		return DetermineAbilityDemonology()
	elseif currentSpec == SPEC.DESTRUCTION then
		return DetermineAbilityDestruction()
	end
	doomedPreviousPanel:Hide()
end

local function DetermineInterrupt()
	if SummonDoomguard:up() and ShadowLock:ready() then
		return ShadowLock
	end
	if SummonFelhunter:up() and SpellLock:ready() then
		return SpellLock
	end
	if ArcaneTorrent.known and ArcaneTorrent:ready() then
		return ArcaneTorrent
	end
end

local function UpdateInterrupt()
	local _, _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start or notInterruptible then
		var.interrupt = nil
		doomedInterruptPanel:Hide()
		return
	end
	var.interrupt = DetermineInterrupt()
	if var.interrupt then
		doomedInterruptPanel.icon:SetTexture(var.interrupt.icon)
		doomedInterruptPanel.icon:Show()
		doomedInterruptPanel.border:Show()
	else
		doomedInterruptPanel.icon:Hide()
		doomedInterruptPanel.border:Hide()
	end
	doomedInterruptPanel:Show()
	doomedInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
end

local function DenyOverlayGlow(actionButton)
	if not Doomed.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow
	local r = Doomed.glow.color.r
	local g = Doomed.glow.color.g
	local b = Doomed.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Doomed.scale.glow, h * 0.2 * Doomed.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Doomed.scale.glow, -h * 0.2 * Doomed.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

local function CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
		end
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	elseif ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	else
		for i = 1, 12 do
			GenerateGlow(_G['ActionButton' .. i])
			GenerateGlow(_G['MultiBarLeftButton' .. i])
			GenerateGlow(_G['MultiBarRightButton' .. i])
			GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
			GenerateGlow(_G['MultiBarBottomRightButton' .. i])
		end
		if Dominos then
			for i = 1, 60 do
				GenerateGlow(_G['DominosActionButton' .. i])
			end
		end
	end
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon
	for i = 1, #glows do
		glow = glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Doomed.glow.main and var.main and icon == var.main.icon) or
			(Doomed.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Doomed.glow.interrupt and var.interrupt and icon == var.interrupt.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

function events:PLAYER_LOGIN()
	me = UnitGUID('player')
	CreateOverlayGlows()
end

local function ShouldHide()
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.AFFLICTION and Doomed.hide.affliction) or
		   (currentSpec == SPEC.DEMONOLOGY and Doomed.hide.demonology) or
		   (currentSpec == SPEC.DESTRUCTION and Doomed.hide.destruction))
end

local function Disappear()
	var.main = nil
	var.cd = nil
	var.interrupt = nil
	UpdateGlows()
	doomedPanel:Hide()
	doomedPanel.border:Hide()
	doomedPreviousPanel:Hide()
	doomedCooldownPanel:Hide()
	doomedInterruptPanel:Hide()
--[[
	doomedAtonementPanel:Hide()
	doomedShieldPanel:Hide()
]]
end

function Doomed_ToggleTargetMode()
	local mode = targetMode + 1
	Doomed_SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end

function Doomed_ToggleTargetModeReverse()
	local mode = targetMode - 1
	Doomed_SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end

function Doomed_SetTargetMode(mode)
	targetMode = min(mode, #targetModes[currentSpec])
	doomedPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end

function Equipped(name, slot)
	local function SlotMatches(name, slot)
		local ilink = GetInventoryItemLink('player', slot)
		if ilink then
			local iname = ilink:match('%[(.*)%]')
			return (iname and iname:find(name))
		end
		return false
	end
	if slot then
		return SlotMatches(name, slot)
	end
	for slot = 1, 19 do
		if SlotMatches(name, slot) then
			return true
		end
	end
	return false
end

function EquippedTier(name)
	local slot = { 1, 3, 5, 7, 10, 15 }
	local equipped = 0
	for i = 1, #slot do
		if Equipped(name, slot) then
			equipped = equipped + 1
		end
	end
	return equipped
end

local function UpdateDraggable()
	doomedPanel:EnableMouse(Doomed.aoe or not Doomed.locked)
	if Doomed.aoe then
		doomedPanel.button:Show()
	else
		doomedPanel.button:Hide()
	end
	if Doomed.locked then
		doomedPanel:SetScript('OnDragStart', nil)
		doomedPanel:SetScript('OnDragStop', nil)
		doomedPanel:RegisterForDrag(nil)
		doomedPreviousPanel:EnableMouse(false)
		doomedCooldownPanel:EnableMouse(false)
		doomedInterruptPanel:EnableMouse(false)
--[[
		doomedAtonementPanel:EnableMouse(false)
		doomedShieldPanel:EnableMouse(false)
]]
	else
		if not Doomed.aoe then
			doomedPanel:SetScript('OnDragStart', doomedPanel.StartMoving)
			doomedPanel:SetScript('OnDragStop', doomedPanel.StopMovingOrSizing)
			doomedPanel:RegisterForDrag('LeftButton')
		end
		doomedPreviousPanel:EnableMouse(true)
		doomedCooldownPanel:EnableMouse(true)
		doomedInterruptPanel:EnableMouse(true)
--[[
		doomedAtonementPanel:EnableMouse(true)
		doomedShieldPanel:EnableMouse(true)
]]
	end
end

local function OnResourceFrameHide()
	if Doomed.snap then
		doomedPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Doomed.snap then
		doomedPanel:ClearAllPoints()
		if Doomed.snap == 'above' then
			doomedPanel:SetPoint('BOTTOM', NamePlatePlayerResourceFrame, 'TOP', 0, 18)
		elseif Doomed.snap == 'below' then
			doomedPanel:SetPoint('TOP', NamePlatePlayerResourceFrame, 'BOTTOM', 0, -4)
		end
	end
end

NamePlatePlayerResourceFrame:HookScript("OnHide", OnResourceFrameHide)
NamePlatePlayerResourceFrame:HookScript("OnShow", OnResourceFrameShow)

local function UpdateAlpha()
	doomedPanel:SetAlpha(Doomed.alpha)
	doomedPreviousPanel:SetAlpha(Doomed.alpha)
	doomedCooldownPanel:SetAlpha(Doomed.alpha)
	doomedInterruptPanel:SetAlpha(Doomed.alpha)
--[[
	doomedAtonementPanel:SetAlpha(Doomed.alpha)
	doomedShieldPanel:SetAlpha(Doomed.alpha)
]]
end

local function UpdateHealthArray()
	Target.healthArray = {}
	for i = 1, floor(3 / Doomed.frequency) do
		Target.healthArray[i] = 0
	end
end

local function UpdateCombat()
	UpdateVars()
	var.main = DetermineAbility()
	if var.main ~= var.last_main then
		if var.main then
			doomedPanel.icon:SetTexture(var.main.icon)
			doomedPanel.icon:Show()
			doomedPanel.border:Show()
		else
			doomedPanel.icon:Hide()
			doomedPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			doomedCooldownPanel.icon:SetTexture(var.cd.icon)
			doomedCooldownPanel:Show()
		else
			doomedCooldownPanel:Hide()
		end
	end
	local gcdStart, gcdDuration = GetSpellCooldown(LifeTap.spellId)
	local gcdRemains = gcdDuration - (var.time - gcdStart)
	--[[if currentSpec == SPEC.AFFLICTION then
		if var.atonement_count > 0 then
			doomedAtonementPanel.text:SetText(var.atonement_count)
			doomedAtonementPanel:Show()
		else
			doomedAtonementPanel.text:SetText('')
			doomedAtonementPanel:Hide()
		end
		local shieldCDStart, shieldCDDuration = GetSpellCooldown(PowerWordShield.spellId)
		local shieldRemains = shieldCDDuration - (var.time - shieldCDStart)
		if shieldCDStart == 0 or shieldRemains <= gcdRemains then
			doomedShieldPanel.text:SetText('')
			doomedShieldPanel:Hide()
		else
			doomedShieldPanel.text:SetText(string.format("%.1f", shieldRemains))
			doomedShieldPanel.cooldown:SetCooldown(shieldCDStart, shieldCDDuration)
			doomedShieldPanel:Show()
		end
	end]]
	if Doomed.gcd then
		if gcdStart == 0 then
			doomedPanel.gcd:Hide()
		else
			doomedPanel.gcd:SetCooldown(gcdStart, gcdDuration)
			doomedPanel.gcd:Show()
		end
	end
	if Doomed.dimmer then
		if not var.main or IsUsableSpell(var.main.spellId) then
			doomedPanel.dimmer:Hide()
		else
			doomedPanel.dimmer:Show()
		end
	end
	if Doomed.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
	abilityTimer = 0
end

function events:ADDON_LOADED(name)
	if name == 'Doomed' then
		if not Doomed.frequency then
			print('It looks like this is your first time running Doomed, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000/doom|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] Doomed is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeVariables()
		UpdateHealthArray()
		UpdateDraggable()
		UpdateAlpha()
		doomedPanel:SetScale(Doomed.scale.main)
		doomedPreviousPanel:SetScale(Doomed.scale.previous)
		doomedCooldownPanel:SetScale(Doomed.scale.cooldown)
		doomedInterruptPanel:SetScale(Doomed.scale.interrupt)
--[[
		doomedAtonementPanel:SetScale(Doomed.scale.atone)
		doomedAtonementPanel.icon:SetTexture(ShadowBolt.icon)
		doomedShieldPanel:SetScale(Doomed.scale.shield)
		doomedShieldPanel.icon:SetTexture(ShadowBolt.icon)
]]
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED(timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName)
	if srcGUID == me then
		if eventType == 'SPELL_CAST_SUCCESS' then
			local castedAbility = abilityBySpellId[spellId]
			if castedAbility then
				var.last_ability = castedAbility
				if var.last_ability.triggers_gcd then
					var.last_gcd = var.last_ability
				end
				if Doomed.previous and doomedPanel:IsVisible() then
					doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
					doomedPreviousPanel.icon:SetTexture(var.last_ability.icon)
					doomedPreviousPanel:Show()
				end
			end
		end
		if eventType == 'SPELL_MISSED' then
			if Doomed.previous and doomedPanel:IsVisible() and Doomed.miss_effect and var.last_ability and spellId == var.last_ability.spellId then
				doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Doomed\\misseffect.blp')
			end
		end
		--[[
		if Doomed.auto_aoe then
			if eventType == 'SPELL_CAST_SUCCESS' then
				if spellId == Corruption.spellId then
					Doomed_SetTargetMode(1)
				elseif spellId == SeedOfCorruption.spellId then
					SeedOfCorruption.first_hit_time = nil
				elseif spellId == PhantomSingularity.spellId then
					PhantomSingularity.first_hit_time = nil
				end
			elseif eventType == 'SPELL_DAMAGE' then
				if spellId == SeedOfCorruption.spellId then
					SeedOfCorruption:recordTargetsHit()
				elseif spellId == PhantomSingularity.spellId then
					PhantomSingularity:recordTargetsHit()
				end
			end
		end
		]]
	end
end

local function UpdateTargetInfo()
	if ShouldHide() then
		Disappear()
		return false
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.hostile = true
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = 0
		end
		if Doomed.always_on then
			UpdateCombat()
			doomedPanel:Show()
			return true
		end
		Disappear()
		return
	end
	if guid ~= Target.guid then
		Target.guid = UnitGUID('target')
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	Target.boss = Target.level == -1 or (Target.level >= UnitLevel('player') + 2 and not UnitInRaid('player'))
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Doomed.always_on then
		UpdateCombat()
		doomedPanel:Show()
		return true
	end
	Disappear()
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
	if Doomed.auto_aoe then
		Doomed_SetTargetMode(1)
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Tier.T19P = EquippedTier(" of Azj'Aqir")
	Tier.T20P = EquippedTier("Diabolic ")
	Tier.T21P = EquippedTier("Grim Inquisitor's ")
	ItemEquipped.SigilOfSuperiorSummoning = Equipped("Wilfred's Sigil of Superior Summoning")
	ItemEquipped.SindoreiSpite = Equipped("Sin'dorei Spite")
	ItemEquipped.ReapAndSow = Equipped("Reap and Sow")
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		for i = 1, #abilities do
			abilities[i].name, _, abilities[i].icon = GetSpellInfo(abilities[i].spellId)
			abilities[i].known = IsPlayerSpell(abilities[i].spellId)
		end
		currentSpec = GetSpecialization() or 0
		Doomed_SetTargetMode(1)
		UpdateTargetInfo()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
	end
end

doomedPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Doomed_ToggleTargetMode()
		elseif button == 'RightButton' then
			Doomed_ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Doomed_SetTargetMode(1)
		end
	end
end)

doomedPanel:SetScript('OnUpdate', function(self, elapsed)
	abilityTimer = abilityTimer + elapsed
	if abilityTimer >= Doomed.frequency then
		--[[
		if Doomed.auto_aoe then
			if currentSpec == SPEC.AFFLICTION then
				SeedOfCorruption:updateTargetsHit()
				PhantomSingularity:updateTargetsHit()
			end
		end
		]]
		UpdateCombat()
	end
end)

doomedPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
for event in pairs(events) do
	doomedPanel:RegisterEvent(event)
end

function SlashCmdList.Doomed(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Doomed.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('Doomed - Locked: ' .. (Doomed.locked and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Doomed.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Doomed.snap = 'below'
			else
				Doomed.snap = false
				doomedPanel:ClearAllPoints()
			end
			OnResourceFrameShow()
		end
		return print('Doomed - Snap to Blizzard combat resources frame: ' .. (Doomed.snap and ('|cFF00C000' .. Doomed.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Doomed.scale.previous = tonumber(msg[3]) or 0.7
				doomedPreviousPanel:SetScale(Doomed.scale.previous)
			end
			return print('Doomed - Previous ability icon scale set to: |cFFFFD000' .. Doomed.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Doomed.scale.main = tonumber(msg[3]) or 1
				doomedPanel:SetScale(Doomed.scale.main)
			end
			return print('Doomed - Main ability icon scale set to: |cFFFFD000' .. Doomed.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Doomed.scale.cooldown = tonumber(msg[3]) or 0.7
				doomedCooldownPanel:SetScale(Doomed.scale.cooldown)
			end
			return print('Doomed - Cooldown ability icon scale set to: |cFFFFD000' .. Doomed.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Doomed.scale.interrupt = tonumber(msg[3]) or 0.4
				doomedInterruptPanel:SetScale(Doomed.scale.interrupt)
			end
			return print('Doomed - Interrupt ability icon scale set to: |cFFFFD000' .. Doomed.scale.interrupt .. '|r times')
		end
--[[
		if msg[2] == 'atone' then
			if msg[3] then
				Doomed.scale.atone = tonumber(msg[3]) or 0.4
				doomedAtonementPanel:SetScale(Doomed.scale.atone)
			end
			return print('Doomed - Atonement count icon scale set to: |cFFFFD000' .. Doomed.scale.atone .. '|r times')
		end
		if msg[2] == 'shield' then
			if msg[3] then
				Doomed.scale.shield = tonumber(msg[3]) or 0.4
				doomedShieldPanel:SetScale(Doomed.scale.shield)
			end
			return print('Doomed - Power Word: Shield icon scale set to: |cFFFFD000' .. Doomed.scale.shield .. '|r times')
		end
]]
		if msg[2] == 'glow' then
			if msg[3] then
				Doomed.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Doomed - Action button glow scale set to: |cFFFFD000' .. Doomed.scale.glow .. '|r times')
		end
		return print('Doomed - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Doomed.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('Doomed - Icon transparency set to: |cFFFFD000' .. Doomed.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Doomed.frequency = tonumber(msg[2]) or 0.05
			UpdateHealthArray()
		end
		return print('Doomed - Calculation frequency: Every |cFFFFD000' .. Doomed.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Doomed.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (main icon): ' .. (Doomed.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Doomed.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (cooldown icon): ' .. (Doomed.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Doomed.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (interrupt icon): ' .. (Doomed.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Doomed.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Blizzard default proc glow: ' .. (Doomed.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Doomed.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Doomed.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Doomed.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('Doomed - Glow color:', '|cFFFF0000' .. Doomed.glow.color.r, '|cFF00FF00' .. Doomed.glow.color.g, '|cFF0000FF' .. Doomed.glow.color.b)
		end
		return print('Doomed - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Doomed.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Doomed - Previous ability icon: ' .. (Doomed.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Doomed.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Doomed - Show the Doomed UI without a target: ' .. (Doomed.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Doomed.cooldown = msg[2] == 'on'
		end
		return print('Doomed - Use Doomed for cooldown management: ' .. (Doomed.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'gcd' then
		if msg[2] then
			Doomed.gcd = msg[2] == 'on'
			if not Doomed.gcd then
				doomedPanel.gcd:Hide()
			end
		end
		return print('Doomed - Global cooldown swipe: ' .. (Doomed.gcd and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Doomed.dimmer = msg[2] == 'on'
			if not Doomed.dimmer then
				doomedPanel.dimmer:Hide()
			end
		end
		return print('Doomed - Dim main ability icon when you don\'t have enough mana to use it: ' .. (Doomed.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Doomed.miss_effect = msg[2] == 'on'
		end
		return print('Doomed - Red border around previous ability when it fails to hit: ' .. (Doomed.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Doomed.aoe = msg[2] == 'on'
			Doomed_SetTargetMode(1)
			UpdateDraggable()
		end
		return print('Doomed - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Doomed.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Doomed.boss_only = msg[2] == 'on'
		end
		return print('Doomed - Only use cooldowns on bosses: ' .. (Doomed.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'aff') then
				Doomed.hide.affliction = not Doomed.hide.affliction
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Doomed - Affliction specialization: |cFFFFD000' .. (Doomed.hide.affliction and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'demo') then
				Doomed.hide.demonology = not Doomed.hide.demonology
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Doomed - Demonology specialization: |cFFFFD000' .. (Doomed.hide.demonology and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'dest') then
				Doomed.hide.destruction = not Doomed.hide.destruction
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Doomed - Destruction specialization: |cFFFFD000' .. (Doomed.hide.destruction and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('Doomed - Possible hidespec options: |cFFFFD000aff|r/|cFFFFD000demo|r/|cFFFFD000dest|r - toggle disabling Doomed for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Doomed.interrupt = msg[2] == 'on'
		end
		return print('Doomed - Show an icon for interruptable spells: ' .. (Doomed.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
--[[
	if msg[1] == 'atone' then
		if msg[2] then
			Doomed.atone = msg[2] == 'on'
		end
		return print('Doomed - Show an icon for atonement count (discipline): ' .. (Doomed.atone and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'shield' then
		if msg[2] then
			Doomed.shield = msg[2] == 'on'
		end
		return print('Doomed - Show an icon for Power Word: Shield cooldown (discipline): ' .. (Doomed.shield and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Doomed.auto_aoe = msg[2] == 'on'
		end
		return print('Doomed - Automatically change target mode on AoE spells: ' .. (Doomed.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
]]
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Doomed.pot = msg[2] == 'on'
		end
		return print('Doomed - Show Prolonged Power potions in cooldown UI: ' .. (Doomed.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'reset' then
		doomedPanel:ClearAllPoints()
		doomedPanel:SetPoint('CENTER', 0, -169)
		doomedPreviousPanel:ClearAllPoints()
		doomedPreviousPanel:SetPoint('BOTTOMRIGHT', doomedPanel, 'BOTTOMLEFT', -10, -5)
		doomedCooldownPanel:ClearAllPoints()
		doomedCooldownPanel:SetPoint('BOTTOMLEFT', doomedPanel, 'BOTTOMRIGHT', 10, -5)
		doomedInterruptPanel:ClearAllPoints()
		doomedInterruptPanel:SetPoint('TOPLEFT', doomedPanel, 'TOPRIGHT', 16, 25)
--[[
		doomedAtonementPanel:ClearAllPoints()
		doomedAtonementPanel:SetPoint('TOPRIGHT', doomedPanel, 'TOPLEFT', -16, 25)
		doomedShieldPanel:ClearAllPoints()
		doomedShieldPanel:SetPoint('TOPLEFT', doomedPanel, 'TOPRIGHT', 16, 25)
]]
		return print('Doomed - Position has been reset to default')
	end
	print('Doomed (version: |cFFFFD000' .. GetAddOnMetadata('Doomed', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in pairs({
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Doomed UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Doomed UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000glow|r - adjust the scale of the Doomed UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Doomed UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Doomed UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Doomed for cooldown management',
		'gcd |cFF00C000on|r/|cFFC00000off|r - show global cooldown swipe on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough mana to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000aff|r/|cFFFFD000demo|r/|cFFFFD000dest|r - toggle disabling Doomed for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
--[[
		'atone |cFF00C000on|r/|cFFC00000off|r - show an icon for atonement count (discipline)',
		'shield |cFF00C000on|r/|cFFC00000off|r - show an icon for Power Word: Shield cooldown (discipline)',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
]]
		'pot |cFF00C000on|r/|cFFC00000off|r - show Prolonged Power potions in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the Doomed UI to default',
	}) do
		print('  ' .. SLASH_Doomed1 .. ' ' .. cmd)
	end
	print('Need to threaten with the wrath of doom? You can still use |cFFFFD000/wrath|r!')
	print('Got ideas for improvement or found a bug? Contact |cFF9482C9Guud|cFFFFD000-Mal\'Ganis|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
