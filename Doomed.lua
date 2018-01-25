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
		local k, v
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
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
			interrupt = 0.4,
			petcd = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			petcd = true,
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
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		healthstone = true,
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

local events, glows = {}, {}

local abilityTimer, currentSpec, targetMode, combatStartTime = 0, 0, 0, 0

local Targets = {}

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
	ReapAndSow = false,
	RecurrentRitual = false,
	SephuzsSecret = false
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
doomedPanel.border = doomedPanel:CreateTexture(nil, 'ARTWORK')
doomedPanel.border:SetAllPoints(doomedPanel)
doomedPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedPanel.border:Hide()
doomedPanel.swipe = CreateFrame('Cooldown', nil, doomedPanel, 'CooldownFrameTemplate')
doomedPanel.swipe:SetAllPoints(doomedPanel)
doomedPanel.dimmer = doomedPanel:CreateTexture(nil, 'BORDER')
doomedPanel.dimmer:SetAllPoints(doomedPanel)
doomedPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
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
doomedPreviousPanel.border = doomedPreviousPanel:CreateTexture(nil, 'ARTWORK')
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
doomedCooldownPanel.border = doomedCooldownPanel:CreateTexture(nil, 'ARTWORK')
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
doomedInterruptPanel.border = doomedInterruptPanel:CreateTexture(nil, 'ARTWORK')
doomedInterruptPanel.border:SetAllPoints(doomedInterruptPanel)
doomedInterruptPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')
doomedInterruptPanel.cast = CreateFrame('Cooldown', nil, doomedInterruptPanel, 'CooldownFrameTemplate')
doomedInterruptPanel.cast:SetAllPoints(doomedInterruptPanel)
local doomedPetCDPanel = CreateFrame('Frame', 'doomedPetCDPanel', UIParent)
doomedPetCDPanel:SetPoint('TOPRIGHT', doomedPanel, 'TOPLEFT', -16, 25)
doomedPetCDPanel:SetFrameStrata('BACKGROUND')
doomedPetCDPanel:SetSize(64, 64)
doomedPetCDPanel:Hide()
doomedPetCDPanel:RegisterForDrag('LeftButton')
doomedPetCDPanel:SetScript('OnDragStart', doomedPetCDPanel.StartMoving)
doomedPetCDPanel:SetScript('OnDragStop', doomedPetCDPanel.StopMovingOrSizing)
doomedPetCDPanel:SetMovable(true)
doomedPetCDPanel.icon = doomedPetCDPanel:CreateTexture(nil, 'BACKGROUND')
doomedPetCDPanel.icon:SetAllPoints(doomedPetCDPanel)
doomedPetCDPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
doomedPetCDPanel.border = doomedPetCDPanel:CreateTexture(nil, 'ARTWORK')
doomedPetCDPanel.border:SetAllPoints(doomedPetCDPanel)
doomedPetCDPanel.border:SetTexture('Interface\\AddOns\\Doomed\\border.blp')

-- Start Abilities

local Ability, abilities, abilityBySpellId, abilitiesAutoAoe = {}, {}, {}, {}
Ability.__index = Ability

function Ability.add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_pet = false,
		triggers_gcd = true,
		hasted_duration = false,
		known = false,
		mana_cost = 0,
		shard_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
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
	if self:manaCost() > var.mana then
		return false
	end
	if self:shardCost() > var.soul_shards then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	if self.requires_pet and (not UnitExists('pet') or UnitIsDead('pet')) then
		return false
	end
	return self:ready(seconds)
end

function Ability:remains()
	if self.buff_duration > 0 and self:casting() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - var.time - var.execute_remains, 0)
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

function Ability:up()
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if id == self.spellId or id == self.spellId2 then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
end

function Ability:down(excludeCasting)
	return not self:up()
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:manaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * var.mana_max) or 0
end

function Ability:shardCost()
	return self.shard_cost
end

function Ability:charges()
	return GetSpellCharges(self.spellId) or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return var.cast_ability == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

--[[
function Ability:castRegen()
	return var.regen * max(self.triggers_gcd and var.gcd or 0, self:castTime())
end
]]

function Ability:tickInterval()
	return self.tick_interval - (self.tick_interval * (UnitSpellHaste('player') / 100))
end

function Ability:previous()
	if self:channeling() then
		return true
	end
	if var.cast_ability then
		return var.cast_ability == self
	end
	return var.last_gcd == self or var.last_ability == self
end

function Ability:setAutoAoe(enabled)
	if enabled and not self.auto_aoe then
		self.auto_aoe = true
		self.first_hit_time = nil
		self.targets_hit = {}
		abilitiesAutoAoe[#abilitiesAutoAoe + 1] = self
	end
	if not enabled and self.auto_aoe then
		self.auto_aoe = nil
		self.first_hit_time = nil
		self.targets_hit = nil
		local i
		for i = 1, #abilitiesAutoAoe do
			if abilitiesAutoAoe[i] == self then
				abilitiesAutoAoe[i] = nil
				break
			end
		end
	end
end

function Ability:recordTargetHit(guid)
	local t = GetTime()
	self.targets_hit[guid] = t
	Targets[guid] = t
	if not self.first_hit_time then
		self.first_hit_time = t
	end
end

local function AutoAoeUpdateTargetMode()
	local count, i = 0
	for i in next, Targets do
		count = count + 1
	end
	if count <= 1 then
		Doomed_SetTargetMode(1)
		return
	end
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			Doomed_SetTargetMode(i)
			return
		end
	end
end

local function AutoAoeRemoveTarget(guid)
	if Targets[guid] then
		Targets[guid] = nil
		AutoAoeUpdateTargetMode()
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and GetTime() - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		local guid
		for guid in next, Targets do
			if not self.targets_hit[guid] then
				Targets[guid] = nil
			end
		end
		for guid in next, self.targets_hit do
			self.targets_hit[guid] = nil
		end
		AutoAoeUpdateTargetMode()
	end
end

-- Warlock Abilities
---- Multiple Specializations
local CreateHealthstone = Ability.add(6201, true, true)
CreateHealthstone.mana_cost = 5
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
local SephuzsSecret = Ability.add(208052, true, true)
SephuzsSecret.cooldown_duration = 30
------ Permanent Pets
local SummonDoomguard = Ability.add(157757, false, true) -- Grimoire of Supremacy
SummonDoomguard.shard_cost = 1
SummonDoomguard.pet_family = 'Doomguard'
local SummonInfernal = Ability.add(157898, false, true) -- Grimoire of Supremacy
SummonInfernal.shard_cost = 1
SummonInfernal.pet_family = 'Infernal'
local SummonImp = Ability.add(688, false, true)
SummonImp.shard_cost = 1
SummonImp.pet_family = 'Imp'
local SummonFelImp = Ability.add(112866, false, true, 219424)
SummonFelImp.shard_cost = 1
SummonFelImp.pet_family = 'Fel Imp'
local SummonFelhunter = Ability.add(691, false, true)
SummonFelhunter.shard_cost = 1
SummonFelhunter.pet_family = 'Felhunter'
local SummonObserver = Ability.add(112869, false, true, 219450)
SummonObserver.shard_cost = 1
SummonObserver.pet_family = 'Observer'
local SummonVoidwalker = Ability.add(697, false, true)
SummonVoidwalker.shard_cost = 1
SummonVoidwalker.pet_family = 'Voidwalker'
local SummonVoidlord = Ability.add(112867, false, true, 219445)
SummonVoidlord.shard_cost = 1
SummonVoidlord.pet_family = 'Voidlord'
local SummonSuccubus = Ability.add(712, false, true)
SummonSuccubus.shard_cost = 1
SummonSuccubus.pet_family = 'Succubus'
local SummonShivarra = Ability.add(112868, false, true, 219436)
SummonShivarra.shard_cost = 1
SummonShivarra.pet_family = 'Shivarra'
local SummonFelguard = Ability.add(30146, false, true)
SummonFelguard.shard_cost = 1
SummonFelguard.pet_family = 'Felguard'
local SummonWrathguard = Ability.add(112870, false, true, 219467)
SummonWrathguard.shard_cost = 1
SummonWrathguard.pet_family = 'Wrathguard'
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
local SeedOfCorruption = Ability.add(27243, false, true, 27285)
SeedOfCorruption.shard_cost = 1
SeedOfCorruption.buff_duration = 18
SeedOfCorruption.hasted_duration = true
SeedOfCorruption:setAutoAoe(true)
local TormentedSouls = ReapSouls
local UnstableAffliction = Ability.add(30108, false, true)
UnstableAffliction.shard_cost = 1
UnstableAffliction.buff_duration = 8
UnstableAffliction.tick_interval = 2
UnstableAffliction.hasted_duration = true
UnstableAffliction[1] = Ability.add(233490, false, true)
UnstableAffliction[2] = Ability.add(233496, false, true)
UnstableAffliction[3] = Ability.add(233497, false, true)
UnstableAffliction[4] = Ability.add(233498, false, true)
UnstableAffliction[5] = Ability.add(233499, false, true)
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
PhantomSingularity:setAutoAoe(true)
local SiphonLife = Ability.add(63106, false, true)
SiphonLife.tick_interval = 3
local SowTheSeeds = Ability.add(196226, false, true)
---- Demonology
------ Base Abilities
local CallDreadstalkers = Ability.add(104316, true, true)
CallDreadstalkers.cooldown_duration = 15
CallDreadstalkers.shard_cost = 2
local Demonwrath = Ability.add(193440, 'pet', true, 193439)
Demonwrath.mana_cost = 2.5
Demonwrath.buff_duration = 3
Demonwrath.tick_interval = 1
Demonwrath.hasted_duration = true
Demonwrath:setAutoAoe(true)
local DemonicEmpowerment = Ability.add(193396, 'pet', true)
DemonicEmpowerment.mana_cost = 6
DemonicEmpowerment.buff_duration = 12
local Doom = Ability.add(603, false, true)
Doom.mana_cost = 2
Doom.buff_duration = 20
Doom.tick_interval = 20
Doom.hasted_duration = true
Doom.tick_targets = {}
local DrainLife = Ability.add(234153, false, true)
DrainLife.mana_cost = 3
DrainLife.buff_duration = 6
DrainLife.tick_interval = 1
DrainLife.hasted_duration = true
local HandOfGuldan = Ability.add(105174, false, true, 86040)
HandOfGuldan.shard_cost = 1
HandOfGuldan:setAutoAoe(true)
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
------ Pet Abilities
local AxeToss = Ability.add(89766, 'pet', true)
AxeToss.triggers_gcd = false
AxeToss.requires_pet = true
AxeToss.cooldown_duration = 30
local Felstorm = Ability.add(89753, 'pet', true, 119914)
Felstorm.requires_pet = true
Felstorm.triggers_gcd = false
Felstorm.buff_duration = 6
Felstorm.tick_interval = 1
Felstorm.cooldown_duration = 45
Felstorm:setAutoAoe(true)
local Wrathstorm = Ability.add(115831, 'pet', true, 115832)
Wrathstorm.requires_pet = true
Wrathstorm.triggers_gcd = false
Wrathstorm.buff_duration = 6
Wrathstorm.tick_interval = 1
Wrathstorm.cooldown_duration = 45
Wrathstorm:setAutoAoe(true)
local Immolation = Ability.add(20153, 'pet', true)
Immolation.tick_interval = 1.5
Immolation:setAutoAoe(true)
------ Talents Abilities
local Demonbolt = Ability.add(157695, false, true)
Demonbolt.mana_cost = 4.8
Demonbolt.shard_cost = -1
local GrimoireFelguard = Ability.add(111898, false, true)
GrimoireFelguard.cooldown_duration = 90
GrimoireFelguard.shard_cost = 1
local HandOfDoom = Ability.add(196283, false, true)
local ImpendingDoom = Ability.add(196270, false, true)
local Implosion = Ability.add(196277, false, true)
Implosion.mana_cost = 6
local ImprovedDreadstalkers = Ability.add(196272, false, true)
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
DemonicSynergy.buff_duration = 15
local DemonicSynergyPet = Ability.add(171975, 'pet', true, 171982)
DemonicSynergyPet.buff_duration = 15
local PowerTrip = Ability.add(196605, true, true)
local ShadowyInspiration = Ability.add(196269, true, true, 196606)
ShadowyInspiration.buff_duration = 15
-- Tier Bonuses
-- Racials
local ArcaneTorrent = Ability.add(136222, true, false) -- Blood Elf
ArcaneTorrent.mana_cost = -3
ArcaneTorrent.triggers_gcd = false
-- Potion Effects
local ProlongedPower = Ability.add(229206, true, true)
ProlongedPower.triggers_gcd = false
-- Trinket Effects

-- End Abilities

-- Start Summoned Pets

local SummonedPet, petsByUnitName = {}, {}
SummonedPet.__index = SummonedPet

function SummonedPet.add(name, duration)
	local pet = {
		name = name,
		duration = duration,
		active_units = {}
	}
	setmetatable(pet, SummonedPet)
	petsByUnitName[name] = pet
	return pet
end

function SummonedPet:remains()
	local remains, guid, unit, unit_remains = 0
	for guid, unit in next, self.active_units do
		unit_remains = unit.spawn_time + self.duration - var.time
		if unit_remains <= 0 then
			self.active_units[guid] = nil
		elseif unit_remains > remains then
			remains = unit_remains
		end
	end
	return min(self.duration, max(0, remains - var.execute_remains))
end

function SummonedPet:up()
	return self:remains() > 0
end

function SummonedPet:down()
	return self:remains() <= 0
end

function SummonedPet:count()
	local count, guid, unit, unit_remains = 0
	for guid, unit in next, self.active_units do
		unit_remains = unit.spawn_time + self.duration - var.time
		if unit_remains <= 0 then
			self.active_units[guid] = nil
		elseif unit_remains > var.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:empowered()
	local count, guid, unit, unit_remains, empower_remains = 0
	local casting_de = DemonicEmpowerment:casting()
	for guid, unit in next, self.active_units do
		unit_remains = unit.spawn_time + self.duration - var.time
		if unit_remains <= 0 then
			self.active_units[guid] = nil
		elseif unit_remains > var.execute_remains then
			if casting_de then
				count = count + 1
			elseif unit.empower_time then
				empower_remains = unit.empower_time + DemonicEmpowerment.buff_duration - var.time
				if empower_remains <= 0 then
					unit.empower_time = nil
				elseif empower_remains > var.execute_remains then
					count = count + 1
				end
			end
		end
	end
	return count
end

function SummonedPet:notEmpowered()
	if DemonicEmpowerment:casting() then
		return 0
	end
	local count, guid, unit, unit_remains, empower_remains = 0
	for guid, unit in next, self.active_units do
		unit_remains = unit.spawn_time + self.duration - var.time
		if unit_remains <= 0 then
			self.active_units[guid] = nil
		elseif unit_remains > var.execute_remains then
			if unit.empower_time then
				empower_remains = unit.empower_time + DemonicEmpowerment.buff_duration - var.time
				if empower_remains <= var.execute_remains then
					if empower_remains <= 0 then
						unit.empower_time = nil
					end
					count = count + 1
				end
			else
				count = count + 1
			end
		end
	end
	return count
end

function SummonedPet:addUnit(guid)
	self.active_units[guid] = {
		spawn_time = GetTime()
	}
end

function SummonedPet:removeUnit(guid, reason)
	if self.active_units[guid] then
		self.active_units[guid] = nil
	end
end

function SummonedPet:empowerUnit(guid)
	if self.active_units[guid] then
		self.active_units[guid].empower_time = GetTime()
	end
end

-- Summoned Pets
local Darkglare = SummonedPet.add('Darkglare', 12)
local Dreadstalker = SummonedPet.add('Dreadstalker', 12)
local WildImp = SummonedPet.add('Wild Imp', 12)
local Doomguard = SummonedPet.add('Doomguard', 25)
local Infernal = SummonedPet.add('Infernal', 25)
local ServiceFelguard = SummonedPet.add('Felguard', 25)

-- End Summoned Pets

-- Start Inventory Items

local InventoryItem = {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon
	}
	setmetatable(item, InventoryItem)
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or var.last_gcd == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or var.last_gcd == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local PotionOfProlongedPower = InventoryItem.add(142117)
local Healthstone = InventoryItem.add(5512)
Healthstone.created_by = CreateHealthstone
Healthstone.max_charges = 3

-- End Inventory Items

-- Start Helpful Functions

local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

local function GetCastManaRegen()
	return var.regen * var.execute_remains - (var.cast_ability and var.cast_ability:manaCost() or 0)
end

local function GetAvailableSoulShards()
	local shards = UnitPower('player', SPELL_POWER_SOUL_SHARDS)
	if currentSpec == SPEC.DEMONOLOGY and var.execute_remains > 0 then
		shards = min(5, shards + Doom:soulShardsGeneratedDuringCast())
	end
	if var.cast_ability then
		shards = min(5, max(0, shards - var.cast_ability:shardCost()))
	end
	return shards
end

--[[
local function Mana()
	return var.mana
end
]]

local function ManaPct()
	return var.mana / var.mana_max * 100
end

--[[
local function ManaDeficit()
	return var.mana_max - var.mana
end

local function ManaRegen()
	return var.mana_regen
end

local function ManaMax()
	return var.mana_max
end
]]

local function SoulShards()
	return var.soul_shards
end

local function SpellHasteFactor()
	return var.haste_factor
end

local function GCD()
	return var.gcd
end

--[[
local function GCDRemains()
	return var.gcd_remains
end
]]

local function PlayerIsMoving()
	return GetUnitSpeed('player') ~= 0
end

local function PetIsSummoned()
	return (IsMounted() or (UnitExists('pet') and not UnitIsDead('pet')) or
		SummonFelguard:up() or SummonWrathguard:up() or
		SummonDoomguard:up() or SummonInfernal:up() or
		SummonFelhunter:up() or SummonObserver:up() or
		SummonImp:up() or SummonFelImp:up() or
		SummonVoidwalker:up() or SummonVoidlord:up() or
		SummonSuccubus:up() or SummonShivarra:up())
end

local function Enemies()
	return targetModes[currentSpec][targetMode][1]
end

local function TimeInCombat()
	return combatStartTime > 0 and var.time - combatStartTime or 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if id == 2825 or id == 32182 or id == 80353 or id == 90355 or id == 160452 or id == 146555 then
			return true
		end
	end
end

local function TargetIsStunnable()
	if Target.boss then
		return false
	end
	if UnitHealthMax('target') > UnitHealthMax('player') * 25 then
		return false
	end
	return true
end

--[[
local PetHealthMultiplier = {
	Felguard = 0.5,
	Felhunter = 0.4,
	Imp = 0.4,
	Voidwalker = 0.5,
	Succubus = 0.4,
	Doomguard = 0.4,
	Infernal = 0.5,
	Darkglare = 0.4,
	Dreadstalker = 0.4,
	WildImp = 0.15
}

local function GetSummonersProwessRank()
	UIParent:UnregisterEvent('ARTIFACT_UPDATE')
	SocketInventoryItem(16)
	local power_info = C_ArtifactUI.GetPowerInfo(1171)
	C_ArtifactUI.Clear()
	UIParent:RegisterEvent('ARTIFACT_UPDATE')
	return power_info and power_info.currentRank or 0
end

local function GetActivePetFamily()
	if SummonInfernal:up() then
		return 'Infernal'
	end
	if SummonDoomguard:up() then
		return 'Doomguard'
	end
	if SummonImp:up() or SummonFelImp:up() then
		return 'Imp'
	end
	if SummonFelhunter:up() or SummonObserver:up() then
		return 'Felhunter'
	end
	if SummonVoidwalker:up() or SummonVoidlord:up() then
		return 'Voidwalker'
	end
	if SummonSuccubus:up() or SummonSuccubus:up() then
		return 'Succubus'
	end
	if SummonFelguard:up() or SummonWrathguard:up() then
		return 'Felguard'
	end
end
]]

-- End Helpful Functions

-- Start Ability Modifications

function LifeTap:usable()
	if (UnitHealth('player') / UnitHealthMax('player')) <= 0.10 then
		return false
	end
	return Ability.usable(self)
end

function Doom:duration()
	return var.haste_factor * (self.buff_duration - (ImpendingDoom.known and 3 or 0))
end

function Doom:up()
	if HandOfDoom.known and (HandOfGuldan:previous() or var.last_gcd == HandOfGuldan) then
		return true
	end
	return Ability.up(self)
end

function Doom:remains()
	if HandOfDoom.known and (HandOfGuldan:previous() or var.last_gcd == HandOfGuldan) then
		return self:duration()
	end
	return Ability.remains(self)
end

function Doom:addTarget(guid)
	local start = GetTime()
	local duration = Doom:duration()
	self.tick_targets[guid] = {
		last_tick = start,
		tick_duration = duration,
		expires = start + duration
	}
end

function Doom:tickTarget(guid)
	local t = self.tick_targets[guid]
	if not t then
		return
	end
	if not t.refreshed then
		self.tick_targets[guid] = nil
		return
	end
	t.refreshed = nil
	t.last_tick = GetTime()
	t.tick_duration = self:duration()
end

function Doom:refreshTarget(guid)
	local t = self.tick_targets[guid]
	if not t then
		return
	end
	t.refreshed = GetTime()
	local duration = Doom:duration()
	t.expires = t.refreshed + min(1.3 * duration, t.expires - t.refreshed + duration)
end

function Doom:removeTarget(guid)
	if self.tick_targets[guid] then
		self.tick_targets[guid] = nil
	end
end

--[[
function Doom:nextTick()
	local earliest, next_tick, guid, t
	for guid, t in next, self.tick_targets do
		if var.time > t.expires then
			self.tick_targets[guid] = nil
		else
			next_tick = min(t.expires, t.last_tick + t.tick_duration)
			if not earliest or next_tick < earliest then
				earliest = next_tick
			end
		end
	end
	return earliest or 0
end
]]

function Doom:soulShardsGeneratedDuringCast()
	if var.execute_remains == 0 then
		return 0
	end
	local shards, guid, t = 0
	for guid, t in next, self.tick_targets do
		if var.time > t.expires then
			self.tick_targets[guid] = nil
		elseif min(t.expires, t.last_tick + t.tick_duration) < var.time + var.execute_remains then
			shards = shards + 1
		end
	end
	return shards
end

function Doom:soulShardsGeneratedNextCast(ability)
	local castTime = ability:castTime()
	if castTime == 0 then
		return 0
	end
	local shards, next_tick, guid, t = 0
	for guid, t in next, self.tick_targets do
		if var.time > t.expires then
			self.tick_targets[guid] = nil
		else
			next_tick = min(t.expires, t.last_tick + t.tick_duration)
			if next_tick >= var.time + var.execute_remains and next_tick < var.time + var.execute_remains + castTime then
				shards = shards + 1
			end
		end
	end
	return shards
end

function ShadowyInspiration:up()
	if ShadowyInspiration.known and (DemonicEmpowerment:previous() or var.last_gcd == DemonicEmpowerment) then
		return true
	end
	return Ability.up(self)
end

function ShadowyInspiration:remains()
	if ShadowyInspiration.known and (DemonicEmpowerment:previous() or var.last_gcd == DemonicEmpowerment) then
		return self:duration()
	end
	return Ability.remains(self)
end

--[[
function DemonicEmpowerment:healthMultiplier()
	return 1.2 + (GetSummonersProwessRank() * 0.02)
end

function ThalkielsConsumption:multiplier()
	local mult = 0
	local de_mult = DemonicEmpowerment:healthMultiplier()
	local active_pet = GetActivePetFamily()
	if active_pet and PetHealthMultiplier[active_pet] then
		mult = mult + (DemonicEmpowerment:up() and de_mult or 1) * PetHealthMultiplier[active_pet]
	end
	mult = mult + (ServiceFelguard:notEmpowered() + (ServiceFelguard:empowered() * de_mult)) * PetHealthMultiplier.Felguard
	mult = mult + (Dreadstalker:notEmpowered() + (Dreadstalker:empowered() * de_mult)) * PetHealthMultiplier.Dreadstalker
	mult = mult + (WildImp:notEmpowered() + (WildImp:empowered() * de_mult)) * PetHealthMultiplier.WildImp
	if SummonDarkglare.known then
		mult = mult + (Darkglare:notEmpowered() + (Darkglare:empowered() * de_mult)) * PetHealthMultiplier.Darkglare
	end
	if not GrimoireOfSupremacy.known then
		mult = mult + (Doomguard:notEmpowered() + (Doomguard:empowered() * de_mult)) * PetHealthMultiplier.Doomguard
		mult = mult + (Infernal:notEmpowered() + (Infernal:empowered() * de_mult)) * PetHealthMultiplier.Infernal
	end
	return mult
end

function ThalkielsConsumption:damage()
	return UnitHealthMax('player') * 0.08 * self:multiplier()
end
]]

function ReapSouls:usable()
	if self:stack() == 0 then
		return false
	end
	return Ability.usable(self)
end

function Implosion:usable()
	return WildImp:count() > 0 and Ability.usable(self)
end

function Corruption:up()
	return Ability.up(self) or SeedOfCorruption:up()
end

function Corruption:remains()
	if SeedOfCorruption:up() or SeedOfCorruption:previous() or var.last_gcd == SeedOfCorruption then
		return Corruption:duration()
	end
	return Ability.remains(self)
end

function UnstableAffliction:stack()
	return (
		(UnstableAffliction[1]:up() and 1 or 0) +
		(UnstableAffliction[2]:up() and 1 or 0) +
		(UnstableAffliction[3]:up() and 1 or 0) +
		(UnstableAffliction[4]:up() and 1 or 0) +
		(UnstableAffliction[5]:up() and 1 or 0))
end

function UnstableAffliction:remains()
	return max(UnstableAffliction[1]:remains(), UnstableAffliction[2]:remains(), UnstableAffliction[3]:remains(), UnstableAffliction[4]:remains(), UnstableAffliction[5]:remains())
end

function UnstableAffliction:lowest()
	local ua = UnstableAffliction[1]
	local lowest = ua:remains()
	local remains, i
	for i = 2, 5 do
		remains = UnstableAffliction[i]:remains()
		if remains > 0 and remains < lowest then
			ua = UnstableAffliction[i]
			lowest = remains
		end
	end
	return ua, lowest
end

function UnstableAffliction:lowestRemains()
	local _, remains = UnstableAffliction:lowest()
	return remains
end

function UnstableAffliction:next()
	local i
	for i = 1, 5 do
		if not Ability.up(UnstableAffliction[i], true) then
			return UnstableAffliction[i]
		end
	end
	return UnstableAffliction:lowest()
end

function UnstableAffliction:up()
	return UnstableAffliction[1]:up() or UnstableAffliction[2]:up() or UnstableAffliction[3]:up() or UnstableAffliction[4]:up() or UnstableAffliction[5]:up()
end

local function UnstableAfflictionRemains(self)
	if UnstableAffliction:casting() and UnstableAffliction:next() == self then
		return UnstableAffliction:duration()
	end
	return Ability.remains(self)
end

local function UnstableAfflictionUp(self)
	if UnstableAffliction:casting() and UnstableAffliction:next() == self then
		return true
	end
	return Ability.up(self)
end

local i
for i = 1, 5 do
	UnstableAffliction[i].remains = UnstableAfflictionRemains
	UnstableAffliction[i].up = UnstableAfflictionUp
end

local function SummonPetUp(self)
	if self:casting() then
		return true
	end
	if UnitIsDead('pet') then
		return false
	end
	return UnitCreatureFamily('pet') == self.pet_family
end

SummonDoomguard.up = SummonPetUp
SummonInfernal.up = SummonPetUp
SummonImp.up = SummonPetUp
SummonFelImp.up = SummonPetUp
SummonFelhunter.up = SummonPetUp
SummonObserver.up = SummonPetUp
SummonVoidwalker.up = SummonPetUp
SummonVoidlord.up = SummonPetUp
SummonSuccubus.up = SummonPetUp
SummonShivarra.up = SummonPetUp
SummonFelguard.up = SummonPetUp
SummonWrathguard.up = SummonPetUp

function HandOfGuldan:shardCost()
	return min(4, max(UnitPower('player', SPELL_POWER_SOUL_SHARDS), self.shard_cost))
end

function CallDreadstalkers:shardCost()
	local cost = self.shard_cost
	if DemonicCalling:up() then
		cost = 0
	end
	if ItemEquipped.RecurrentRitual then
		cost = cost - 1
	end
	return cost
end

function SephuzsSecret:cooldown()
	if not self.cooldown_start then
		return 0
	end
	if var.time >= self.cooldown_start + self.cooldown_duration then
		self.cooldown_start = nil
		return 0
	end
	return self.cooldown_duration - (var.time - self.cooldown_start)
end

function AxeToss:usable(seconds)
	if not (SummonFelguard:up() or SummonWrathguard:up()) then
		return false
	end
	if Felstorm:up() or Wrathstorm:up() then
		return false
	end
	if not TargetIsStunnable() then
		return false
	end
	return self:ready(seconds)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function Dreadstalker:count()
	local count = SummonedPet.count(self)
	if CallDreadstalkers:casting() then
		count = count + 2
	end
	return count
end

function Dreadstalker:remains()
	if CallDreadstalkers:casting() then
		return self.duration
	end
	return SummonedPet.remains(self)
end

function Dreadstalker:notEmpowered()
	local count = SummonedPet.notEmpowered(self)
	if CallDreadstalkers:casting() then
		count = count + 2
	end
	return count
end

function WildImp:count()
	local count = SummonedPet.count(self)
	if HandOfGuldan:casting() then
		count = count + 4
	end
	if ImprovedDreadstalkers.known and CallDreadstalkers:casting() then
		count = count + 2
	end
	if ImpendingDoom.known then
		count = count + Doom:soulShardsGeneratedDuringCast()
	end
	return count
end

function WildImp:remains()
	if HandOfGuldan:casting() or (ImprovedDreadstalkers.known and CallDreadstalkers:casting()) then
		return self.duration
	end
	return SummonedPet.remains(self)
end

function WildImp:notEmpowered()
	local count = SummonedPet.notEmpowered(self)
	if HandOfGuldan:casting() then
		count = count + 4
	end
	if ImprovedDreadstalkers.known and CallDreadstalkers:casting() then
		count = count + 2
	end
	if ImpendingDoom.known then
		count = count + Doom:soulShardsGeneratedDuringCast()
	end
	return count
end

-- End Summoned Pet Modifications

local function UpdateVars()
	local _, start, duration, remains, hp, spellId
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_petcd = var.petcd
	var.time = GetTime()
	var.gcd = 1.5 - (1.5 * (UnitSpellHaste('player') / 100))
	start, duration = GetSpellCooldown(LifeTap.spellId)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.cast_ability = abilityBySpellId[spellId]
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.regen = GetPowerRegen()
	var.mana_regen = GetCastManaRegen()
	var.mana_max = UnitPowerMax('player', SPELL_POWER_MANA)
	var.mana = min(var.mana_max, floor(UnitPower('player', SPELL_POWER_MANA) + var.mana_regen))
	var.soul_shards = GetAvailableSoulShards()
	hp = UnitHealth('target')
	Target.healthArray[#Target.healthArray + 1] = hp
	table.remove(Target.healthArray, 1)
	Target.healthPercentage = Target.guid == 0 and 100 or (hp / UnitHealthMax('target') * 100)
	hp = Target.healthArray[1] - Target.healthArray[#Target.healthArray]
	Target.timeToDie = hp > 0 and (Target.healthArray[#Target.healthArray] / (hp / 3)) or 600
end

local function UseCooldown(ability, overwrite, always)
	if always or (Doomed.cooldown and (not Doomed.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UsePetCooldown(ability, overwrite, always)
	if always or (not var.petcd or overwrite) then
		var.petcd = ability
	end
end

-- Begin Action Priority Lists

local function DetermineAbilityAffliction()
	if TimeInCombat() == 0 then
		if not PetIsSummoned() then
			if GrimoireOfSupremacy.known then
				return Enemies() > 1 and SummonInfernal or SummonDoomguard
			end
			if not GrimoireOfSacrifice.known or (GrimoireOfSacrifice.known and DemonicPower:remains() < 300) then
				return SummonObserver.known and SummonObserver or SummonFelhunter
			end
		end
		if GrimoireOfSacrifice.known and PetIsSummoned() then
			return GrimoireOfSacrifice
		end
		if LifeTap:usable() and (ManaPct() < 70 or (EmpoweredLifeTap.known and EmpoweredLifeTap:refreshable())) then
			return LifeTap
		end
		if Doomed.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	end
	if ReapSouls:usable() and (DeadwindHarvester:down() or (not (DrainSoul:channeling() and UnstableAffliction:up()) and DeadwindHarvester:remains() < 3)) and TimeInCombat() > 5 and (TormentedSouls:stack() >= min(4 + Enemies(), 9) or Target.timeToDie <= (TormentedSouls:stack() * (ReapAndSow and 6.5 or 5) + (DeadwindHarvester:remains() * (ItemEquipped.ReapAndSow and 6.5 or 5) % 12 * (ItemEquipped.ReapAndSow and 6.5 or 5)))) then
		UseCooldown(ReapSouls, true, true)
	end
	if Agony:remains() <= (Agony:tickInterval() + GCD()) then
		return Agony
	end
	if not PetIsSummoned() then
		if GrimoireOfSupremacy.known then
			UseCooldown(Enemies() > 1 and SummonInfernal or SummonDoomguard)
		end
		if not GrimoireOfSacrifice.known or (GrimoireOfSacrifice.known and DemonicPower:down()) then
			UseCooldown(SummonObserver.known and SummonObserver or SummonFelhunter)
		end
	end
	if GrimoireOfSacrifice.known and PetIsSummoned() then
		UseCooldown(GrimoireOfSacrifice)
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
	if EmpoweredLifeTap.known and LifeTap:usable() and EmpoweredLifeTap:remains() <= GCD() then
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
	if SoulHarvest.known and SoulHarvest:ready() and UnstableAffliction:stack() > 1 and SoulHarvest:remains() <= 8 and (not DeathsEmbrace.known or Target.timeToDie >= 136 or Target.timeToDie <= 40) then
		UseCooldown(SoulHarvest)
	end
	if Doomed.pot and PotionOfProlongedPower:usable() and (Target.timeToDie <= 70 or ((not SoulHarvest.known or SoulHarvest:remains() > 12) and UnstableAffliction:stack() >= 2)) then
		UseCooldown(PotionOfProlongedPower)
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
	if LifeTap:usable() and ((EmpoweredLifeTap.known and EmpoweredLifeTap:refreshable()) or (Target.timeToDie > 15 and ManaPct() < 10)) and not (DrainSoul:channeling() and UnstableAffliction:stack() > 1) then
		return LifeTap
	end
	if SeedOfCorruption:usable() and ((SowTheSeeds.known and Enemies() >= 3) or (Enemies() >= 5 and Corruption:remains() <= SeedOfCorruption:castTime())) then
		return SeedOfCorruption
	end
	if LifeTap:usable() and ManaPct() < 20 and UnstableAffliction:down() and not DrainSoul:channeling() then
		return LifeTap
	end
	if UnstableAffliction:usable() then
		if min(Agony:remains(), Corruption:remains()) > UnstableAffliction:castTime() + (6.5 * SpellHasteFactor()) and (UnstableAffliction:down() or (MaleficGrasp.known and SoulShards() >= 3 and UnstableAffliction:previous() and UnstableAffliction:lowestRemains() > (UnstableAffliction:castTime() + 0.4))) then
			return UnstableAffliction
		end
		if Contagion.known and UnstableAffliction:down() or (not MaleficGrasp.known and UnstableAffliction:remains() < UnstableAffliction:castTime()) then
			return UnstableAffliction
		end
		if Target.timeToDie < (UnstableAffliction:castTime() * SoulShards()) + UnstableAffliction:duration() then
			return UnstableAffliction
		end
		if Enemies() > 1 and SoulShards() >= 4 then
			return UnstableAffliction
		end
	end
	if ReapSouls:usable() and DeadwindHarvester:remains() < UnstableAffliction:remains() and UnstableAffliction:stack() > 1 then
		UseCooldown(ReapSouls, true, true)
	end
	if LifeTap:usable() and (ManaPct() < 10 or (LifeTap:previous() and UnstableAffliction:down() and ManaPct() < 50)) then
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
	if LifeTap:usable() and ManaPct() < 80 then
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

local function DetermineAbilityDemonology()
	if TimeInCombat() == 0 then
		if not PetIsSummoned() then
			if GrimoireOfSupremacy.known then
				return Enemies() > 1 and SummonInfernal or SummonDoomguard
			end
			return SummonWrathguard.known and SummonWrathguard or SummonFelguard
		end
		if DemonicEmpowerment:usable() and DemonicEmpowerment:refreshable() then
			return DemonicEmpowerment
		end
		if LifeTap:usable() and ManaPct() < 70 then
			return LifeTap
		end
		if Doomed.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
		if SoulShards() < 5 then
			if Enemies() >= 5 and Demonwrath:usable() then
				return Demonwrath
			end
			if Demonbolt.known then
				if Demonbolt:usable() then
					return Demonbolt
				end
			elseif ShadowBolt:usable() then
				return ShadowBolt
			end
		end
	end

	if not PetIsSummoned() then
		if GrimoireOfSupremacy.known then
			UseCooldown(Enemies() > 1 and SummonInfernal or SummonDoomguard)
		else
			UseCooldown(SummonWrathguard.known and SummonWrathguard or SummonFelguard)
		end
	end

	if DemonicEmpowerment:up() then
		if SummonFelguard:up() and Felstorm:ready() then
			UsePetCooldown(Felstorm)
		end
		if SummonWrathguard:up() and Wrathstorm:ready() then
			UsePetCooldown(Wrathstorm)
		end
		if ItemEquipped.SephuzsSecret and SephuzsSecret:ready() and AxeToss:usable() then
			UsePetCooldown(AxeToss)
		end
	end

	if Implosion.known and Implosion:usable() and WildImp:remains() <= ShadowBolt:castTime() and (DemonicSynergy:up() or SoulConduit.known or (not SoulConduit.known and Enemies() > 1) or WildImp:count() <= 4) then
		UseCooldown(Implosion)
	end
	if ItemEquipped.SigilOfSuperiorSummoning and not GrimoireOfSupremacy.known then
		if Enemies() > 2 and SummonInfernalCD:usable() then
			UseCooldown(SummonInfernalCD)
		elseif Enemies() <= 2 and SummonDoomguardCD:usable() then
			UseCooldown(SummonDoomguardCD)
		end
	end
	if CallDreadstalkers:usable() and ((not SummonDarkglare.known or PowerTrip.known) and (Enemies() < 3 or not Implosion.known) and (Enemies() < 5 or DemonicCalling:up())) and not (SoulShards() == 5 and DemonicCalling:up()) then
		return CallDreadstalkers
	end

	local service_no_de = ServiceFelguard:notEmpowered()
	local dreadstalker_no_de = Dreadstalker:notEmpowered()
	local wild_imp_no_de = WildImp:notEmpowered()
	local darkglare_no_de = Darkglare:notEmpowered()
	local doomguard_no_de = Doomguard:notEmpowered()
	local infernal_no_de = Infernal:notEmpowered()
	local cd_no_de = doomguard_no_de > 0 or infernal_no_de > 0
	local non_imp_no_de = dreadstalker_no_de > 0 or darkglare_no_de > 0 or cd_no_de or service_no_de > 0

	if Doom:usable() and Doom:refreshable() and Target.timeToDie > Doom:duration() + Doom:remains() then
		if not (HandOfDoom.known or non_imp_no_de or HandOfGuldan:previous()) then
			return Doom
		end
		if HandOfDoom.known and Doom:down() and Enemies() < 3 and SoulShards() < 4 then
			return Doom
		end
	end
	if Shadowflame.known and Shadowflame:usable() and Shadowflame:charges() == 2 and SoulShards() < 5 and Enemies() < 5 then
		return Shadowflame
	end
	if GrimoireFelguard.known and GrimoireFelguard:usable() then
		UseCooldown(GrimoireFelguard)
	end
	if not GrimoireOfSupremacy.known then
		if Enemies() <= 2 and SummonDoomguardCD:usable() and (Target.timeToDie > 180 or Target.healthPercentage <= 20 or Target.timeToDie < 30) then
			UseCooldown(SummonDoomguardCD)
		elseif Enemies() > 2 and SummonInfernalCD:usable() then
			UseCooldown(SummonInfernalCD)
		end
	end

	local cond_no_de = (cd_no_de and service_no_de > 0) or (cd_no_de and wild_imp_no_de > 0) or (cd_no_de and dreadstalker_no_de > 0) or (service_no_de > 0 and dreadstalker_no_de > 0) or (service_no_de > 0 and wild_imp_no_de > 0) or (dreadstalker_no_de > 0 and wild_imp_no_de > 0) or (HandOfGuldan:previous() and non_imp_no_de)

	if ShadowyInspiration.known and ShadowyInspiration:up() and SoulShards() < 5 and not (Doom:previous() or cond_no_de) then
		if Demonbolt.known then
			if Demonbolt:usable() then
				return Demonbolt
			end
		elseif ShadowBolt:usable() then
			return ShadowBolt
		end
	end
	if SummonDarkglare.known then
		if SummonDarkglare:usable() and (
			(HandOfGuldan:previous() or CallDreadstalkers:previous() or PowerTrip.known) or
			(CallDreadstalkers:cooldown() > 5 and SoulShards() < 3) or
			(CallDreadstalkers:remains() <= SummonDarkglare:castTime() and (SoulShards() >= 3 or (SoulShards() >= 1 and DemonicCalling:up())))
		) then
			UseCooldown(SummonDarkglare)
		end
		if CallDreadstalkers:usable() and ((Enemies() < 3 or not Implosion.known) and (SummonDarkglare:cooldown() > 2 or SummonDarkglare:previous() or SummonDarkglare:cooldown() <= CallDreadstalkers:castTime() and SoulShards() >= 3) or (SummonDarkglare:cooldown() <= CallDreadstalkers:castTime() and SoulShards() >= 1 and DemonicCalling:up())) then
			return CallDreadstalkers
		end
	end
	if HandOfGuldan:usable() then
		if SoulShards() == 5 or SoulShards() + Doom:soulShardsGeneratedNextCast(HandOfGuldan) >= 5 then
			return HandOfGuldan
		end
		if SoulShards() >= 4 then
			if (CallDreadstalkers:cooldown() > 4 or DemonicCalling:remains() > HandOfGuldan:castTime() + 2) and (Enemies() >= 5 or HandOfGuldan:previous() or CallDreadstalkers:previous() or (SummonDarkglare.known and SummonDarkglare:previous()) or (HandOfDoom.known and Doom:refreshable())) then
				return HandOfGuldan
			end
			if SummonDarkglare.known and SummonDarkglare:cooldown() > 2 then
				return HandOfGuldan
			end
			local pet_count = (PetIsSummoned() and 1 or 0) + ServiceFelguard:count() + WildImp:count() + Dreadstalker:count() + Darkglare:count() + Doomguard:count() + Infernal:count()
			if PowerTrip.known and ((not (non_imp_no_de or HandOfGuldan:previous()) and (pet_count >= (ShadowyInspiration.known and 6 or 13))) or not cond_no_de) then
				return HandOfGuldan
			end
		end
	end
	if DemonicEmpowerment:usable() then
		if non_imp_no_de or HandOfGuldan:previous() then
			return DemonicEmpowerment
		end
		if (((PowerTrip.known and (not Implosion.known or Enemies() == 1)) or not Implosion.known or (Implosion.known and not SoulConduit.known and Enemies() <= 3)) and wild_imp_no_de > 3) or (Implosion.known and Implosion:previous() and wild_imp_no_de > 0) then
			return DemonicEmpowerment
		end
	end
	if SoulHarvest.known and SoulHarvest:ready() and SoulHarvest:down() then
		UseCooldown(SoulHarvest)
	end
	if Doomed.pot and PotionOfProlongedPower:usable() and (SoulHarvest:up() or Target.timeToDie <= 70 or BloodlustActive()) then
		UseCooldown(PotionOfProlongedPower)
	end
	if Shadowflame.known and Shadowflame:usable() and Shadowflame:charges() == 2 and Enemies() < 5 then
		return Shadowflame
	end
	if ThalkielsConsumption:usable() and (Dreadstalker:remains() > ThalkielsConsumption:castTime() or (Implosion.known and Enemies() >= 3)) and (WildImp:count() > 3 and Dreadstalker:count() <= 2 or WildImp:count() > 5) and WildImp:remains() > ThalkielsConsumption:castTime() then
		UseCooldown(ThalkielsConsumption)
	end
	if LifeTap:usable() and (ManaPct() <= 15 or (ManaPct() <= 65 and (PlayerIsMoving() or (CallDreadstalkers:cooldown() <= 0.75 and SoulShards() >= 2) or ((CallDreadstalkers:cooldown() < GCD() * 2) and SummonDoomguardCD:cooldown() <= 0.75 and SoulShards() >= 3)))) then
		return LifeTap
	end
	if (Enemies() >= 3 or PlayerIsMoving()) and Demonwrath:usable() then
		return Demonwrath
	end
	if Demonbolt.known then
		if Demonbolt:usable() then
			return Demonbolt
		end
	else
		if ShadowyInspiration.known then
			if ShadowBolt:usable() and ShadowyInspiration:up() then
				return ShadowBolt
			end
			if PowerTrip.known and DemonicEmpowerment:usable() then
				return DemonicEmpowerment
			end
		end
		if ShadowBolt:usable() then
			return ShadowBolt
		end
	end
	if LifeTap:usable() and ManaPct() < 80 then
		return LifeTap
	end
end

local function DetermineAbilityDestruction()
	return ShadowBolt
end

-- End Action Priority Lists

local function DetermineAbility()
	var.cd = nil
	var.interrupt = nil
	var.petcd = nil
	if TimeInCombat() == 0 then
		if Doomed.healthstone and Healthstone:charges() == 0 and CreateHealthstone:usable() then
			return CreateHealthstone
		end
	end
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
	local w, h, glow, i
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
	local b, i
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
		for i = 1, 10 do
			GenerateGlow(_G['PetActionButton' .. i])
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
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Doomed.glow.main and var.main and icon == var.main.icon) or
			(Doomed.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Doomed.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Doomed.glow.petcd and var.petcd and icon == var.petcd.icon)
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
	var.petcd = nil
	UpdateGlows()
	doomedPanel:Hide()
	doomedPanel.border:Hide()
	doomedPreviousPanel:Hide()
	doomedCooldownPanel:Hide()
	doomedInterruptPanel:Hide()
	doomedPetCDPanel:Hide()
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
	local i
	for i = 1, 19 do
		if SlotMatches(name, i) then
			return true
		end
	end
	return false
end

function EquippedTier(name)
	local slot = { 1, 3, 5, 7, 10, 15 }
	local equipped, i = 0
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
		doomedPetCDPanel:EnableMouse(false)
	else
		if not Doomed.aoe then
			doomedPanel:SetScript('OnDragStart', doomedPanel.StartMoving)
			doomedPanel:SetScript('OnDragStop', doomedPanel.StopMovingOrSizing)
			doomedPanel:RegisterForDrag('LeftButton')
		end
		doomedPreviousPanel:EnableMouse(true)
		doomedCooldownPanel:EnableMouse(true)
		doomedInterruptPanel:EnableMouse(true)
		doomedPetCDPanel:EnableMouse(true)
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
	doomedPetCDPanel:SetAlpha(Doomed.alpha)
end

local function UpdateHealthArray()
	Target.healthArray = {}
	local i
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
	if var.petcd ~= var.last_petcd then
		if var.petcd then
			doomedPetCDPanel.icon:SetTexture(var.petcd.icon)
			doomedPetCDPanel:Show()
		else
			doomedPetCDPanel:Hide()
		end
	end
	if Doomed.dimmer then
		if not var.main then
			doomedPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			doomedPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
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

function events:SPELL_UPDATE_COOLDOWN()
	if Doomed.spell_swipe then
		local start, duration
		local _, _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(LifeTap.spellId)
			if start <= 0 then
				return doomedPanel.swipe:Hide()
			end
		end
		doomedPanel.swipe:SetCooldown(start, duration)
		doomedPanel.swipe:Show()
	end
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
		doomedPetCDPanel:SetScale(Doomed.scale.petcd)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED(timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName)
	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		if Doomed.auto_aoe then
			AutoAoeRemoveTarget(dstGUID)
		end
		Doom:removeTarget(dstGUID)
	end
	if srcGUID ~= UnitGUID('player') and srcGUID ~= UnitGUID('pet') then
		return
	end
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
		if Doomed.auto_aoe then
			if spellId == Corruption.spellId then
				if targetMode > 1 then
					Doomed_SetTargetMode(1)
				end
			elseif spellId == ShadowBolt.spellId then
				if targetMode > 2 then
					Doomed_SetTargetMode(2)
				end
			end
		end
		return
	end
	if eventType == 'SPELL_MISSED' then
		if Doomed.previous and doomedPanel:IsVisible() and Doomed.miss_effect and var.last_ability and spellId == var.last_ability.spellId then
			doomedPreviousPanel.border:SetTexture('Interface\\AddOns\\Doomed\\misseffect.blp')
		end
		return
	end
	if eventType == 'SPELL_DAMAGE' then
		if Doomed.auto_aoe then
			local i
			for i = 1, #abilitiesAutoAoe do
				if spellId == abilitiesAutoAoe[i].spellId or spellId == abilitiesAutoAoe[i].spellId2 then
					abilitiesAutoAoe[i]:recordTargetHit(dstGUID)
				end
			end
		end
	end
	if eventType == 'SPELL_AURA_APPLIED' then
		if spellId == SephuzsSecret.spellId then
			SephuzsSecret.cooldown_start = GetTime()
			return
		end
	end
	if currentSpec == SPEC.DEMONOLOGY and spellId == Doom.spellId then
		if eventType == 'SPELL_AURA_APPLIED' then
			Doom:addTarget(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			Doom:removeTarget(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			Doom:refreshTarget(dstGUID)
		elseif eventType == 'SPELL_PERIODIC_DAMAGE' then
			Doom:tickTarget(dstGUID)
		end
		return
	end
	if petsByUnitName[dstName] then
		if eventType == 'SPELL_SUMMON' then
			petsByUnitName[dstName]:addUnit(dstGUID)
		elseif eventType == 'UNIT_DIED' or eventType == 'SPELL_INSTAKILL' then
			petsByUnitName[dstName]:removeUnit(dstGUID)
		elseif (eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH') and spellId == DemonicEmpowerment.spellId then
			petsByUnitName[dstName]:empowerUnit(dstGUID)
		end
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
		local i
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
		local i
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
		local guid
		for guid in next, Targets do
			Targets[guid] = nil
		end
		Doomed_SetTargetMode(1)
	end
	if currentSpec == SPEC.DEMONOLOGY then
		local guid
		for guid in next, Doom.tick_targets do
			Doom.tick_targets[guid] = nil
		end
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Tier.T19P = EquippedTier(" of Azj'Aqir")
	Tier.T20P = EquippedTier("Diabolic ")
	Tier.T21P = EquippedTier("Grim Inquisitor's ")
	ItemEquipped.SigilOfSuperiorSummoning = Equipped("Wilfred's Sigil of Superior Summoning")
	ItemEquipped.SindoreiSpite = Equipped("Sin'dorei Spite")
	ItemEquipped.ReapAndSow = Equipped("Reap and Sow")
	ItemEquipped.RecurrentRitual = Equipped("Recurrent Ritual")
	ItemEquipped.SephuzsSecret = Equipped("Sephuz's Secret")
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		local i
		for i = 1, #abilities do
			abilities[i].name, _, abilities[i].icon = GetSpellInfo(abilities[i].spellId)
			abilities[i].known = IsPlayerSpell(abilities[i].spellId) or (abilities[i].spellId2 and IsPlayerSpell(abilities[i].spellId2))
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
	UpdateVars()
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
		if Doomed.auto_aoe then
			local i
			for i = 1, #abilitiesAutoAoe do
				abilitiesAutoAoe[i]:updateTargetsHit()
			end
		end
		UpdateCombat()
	end
end)

doomedPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
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
		if startsWith(msg[2], 'pet') then
			if msg[3] then
				Doomed.scale.petcd = tonumber(msg[3]) or 0.4
				doomedPetCDPanel:SetScale(Doomed.scale.petcd)
			end
			return print('Doomed - Pet cooldown ability icon scale set to: |cFFFFD000' .. Doomed.scale.petcd .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Doomed.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Doomed - Action button glow scale set to: |cFFFFD000' .. Doomed.scale.glow .. '|r times')
		end
		return print('Doomed - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
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
		if startsWith(msg[2], 'pet') then
			if msg[3] then
				Doomed.glow.petcd = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Doomed - Glowing ability buttons (pet cooldown icon): ' .. (Doomed.glow.petcd and '|cFF00C000On' or '|cFFC00000Off'))
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
		return print('Doomed - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
	if msg[1] == 'swipe' then
		if msg[2] then
			Doomed.spell_swipe = msg[2] == 'on'
			if not Doomed.spell_swipe then
				doomedPanel.swipe:Hide()
			end
		end
		return print('Doomed - Spell casting swipe animation: ' .. (Doomed.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
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
	if msg[1] == 'auto' then
		if msg[2] then
			Doomed.auto_aoe = msg[2] == 'on'
		end
		return print('Doomed - Automatically change target mode on AoE spells: ' .. (Doomed.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Doomed.pot = msg[2] == 'on'
		end
		return print('Doomed - Show Prolonged Power potions in cooldown UI: ' .. (Doomed.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'health') then
		if msg[2] then
			Doomed.healthstone = msg[2] == 'on'
		end
		return print('Doomed - Show Create Healthstone reminder out of combat: ' .. (Doomed.healthstone and '|cFF00C000On' or '|cFFC00000Off'))
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
		doomedPetCDPanel:ClearAllPoints()
		doomedPetCDPanel:SetPoint('TOPRIGHT', doomedPanel, 'TOPLEFT', -16, 25)
		return print('Doomed - Position has been reset to default')
	end
	print('Doomed (version: |cFFFFD000' .. GetAddOnMetadata('Doomed', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Doomed UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Doomed UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000glow|r - adjust the scale of the Doomed UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Doomed UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Doomed UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Doomed for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough mana to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000aff|r/|cFFFFD000demo|r/|cFFFFD000dest|r - toggle disabling Doomed for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'pot |cFF00C000on|r/|cFFC00000off|r - show Prolonged Power potions in cooldown UI',
		'healthstone |cFF00C000on|r/|cFFC00000off|r - show Create Healthstone reminder out of combat',
		'|cFFFFD000reset|r - reset the location of the Doomed UI to default',
	} do
		print('  ' .. SLASH_Doomed1 .. ' ' .. cmd)
	end
	print('Need to threaten with the wrath of doom? You can still use |cFFFFD000/wrath|r!')
	print('Got ideas for improvement or found a bug? Contact |cFF9482C9Guud|cFFFFD000-Mal\'Ganis|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
