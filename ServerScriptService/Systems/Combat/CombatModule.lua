local CombatModule = {}

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local Config = require(script.Parent.CombatConfig)
local Hitbox = require(script.Parent.HitboxModule)

-- { variables }
local rep = game.ReplicatedStorage
local combatAssets = rep:WaitForChild("CombatAssets")
local sounds = combatAssets:WaitForChild("Sounds")
local effects = combatAssets:WaitForChild("Effects")

local hitFeedback = rep:WaitForChild("Remotes"):WaitForChild("Combat"):WaitForChild("HitFeedback")
local states = {}

-- { functions }
local function getState(plr)
	return states[plr]
end

local function makeState()
	return {
		comboIndex = 1,
		lastAttack = 0,
		lastRemote = 0,
		lastBlockToggle = 0,
		blocking = false,
		blockStarted = 0,
		blockHits = 0,
		hitTargets = {},
	}
end

local function getTargetTorso(char)
	return char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

local function playSound(parent, name)
	local original = sounds:FindFirstChild(name)
	if not original or not parent then return end
	local s = original:Clone()
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 2)
end

local function playEffect(parent, name)
	local original = effects:FindFirstChild(name)
	if not original or not parent then return end
	local e = original:Clone()
	e.Parent = parent
	Debris:AddItem(e, 2)
end

local function applyKnockback(targetChar, direction, magnitude)
	local hrp = targetChar:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 0 then flat = flat.Unit end

	local att = Instance.new("Attachment")
	att.Parent = hrp

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VectorVelocity = flat * (magnitude or Config.Knockback)
	lv.Parent = hrp

	Debris:AddItem(att, Config.KnockbackDuration)
end

-- { hit handling }
function CombatModule.HandlePunch(plr, payload)
	local state = getState(plr)
	if not state then return end
	if type(payload) ~= "table" then return end

	local now = os.clock()
	if now - state.lastRemote < Config.RemoteCooldown then return end
	state.lastRemote = now

	if state.blocking then return end
	if now - state.lastAttack < Config.AttackCooldown then return end

	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end

	local hitId = payload.hitId
	local targetUserId = payload.targetUserId
	local claimedOrigin = payload.origin
	local claimedTime = payload.timestamp
	local direction = payload.direction

	if claimedOrigin and typeof(claimedOrigin) ~= "Vector3" then return end
	if direction and typeof(direction) ~= "Vector3" then return end
	if claimedTime and typeof(claimedTime) ~= "number" then return end
	if targetUserId and type(targetUserId) ~= "number" then return end

	if claimedTime and math.abs(now - claimedTime) > Config.MaxTimestampDrift then
		if hitId then hitFeedback:FireClient(plr, "HitRejected", hitId) end
		return
	end

	hum.WalkSpeed = Config.AfterPunchSpeed
	task.delay(Config.PunchSpeedRecover, function()
		if hum and hum.Parent then hum.WalkSpeed = Config.BaseWalkSpeed end
	end)

	if now - state.lastAttack > Config.ComboResetTime then
		state.comboIndex = 1
	end

	local thisCombo = state.comboIndex
	state.lastAttack = now
	state.comboIndex = (state.comboIndex % Config.MaxCombo) + 1

	playSound(hrp, "Swing")

	-- resolve target server-side, never trust a client instance ref
	local targetChar
	if targetUserId then
		local targetPlr = Players:GetPlayerByUserId(targetUserId)
		targetChar = targetPlr and targetPlr.Character
	end

	if not targetChar then
		local hits = Hitbox.Cast(char, { Size = Config.HitboxSize, Offset = Config.HitboxOffset })
		targetChar = hits[1]
		if not targetChar then return end
	end

	if claimedOrigin and (hrp.Position - claimedOrigin).Magnitude > Config.PositionTolerance then
		if hitId then hitFeedback:FireClient(plr, "HitRejected", hitId) end
		return
	end

	if not targetChar:IsDescendantOf(workspace) then return end

	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHum or not targetHrp or targetHum.Health <= 0 or targetChar == char then
		if hitId then hitFeedback:FireClient(plr, "HitRejected", hitId) end
		return
	end

	if (targetHrp.Position - hrp.Position).Magnitude > Config.MaxHitRange then
		if hitId then hitFeedback:FireClient(plr, "HitRejected", hitId) end
		return
	end

	local toTarget = targetHrp.Position - hrp.Position
	local flatTo = Vector3.new(toTarget.X, 0, toTarget.Z)
	local useDir = direction or hrp.CFrame.LookVector
	local flatDir = Vector3.new(useDir.X, 0, useDir.Z)
	if flatTo.Magnitude < 0.01 or flatDir.Magnitude < 0.01 then return end
	if flatDir.Unit:Dot(flatTo.Unit) < Config.HitAngle then
		if hitId then hitFeedback:FireClient(plr, "HitRejected", hitId) end
		return
	end

	if state.hitTargets[targetChar] then
		if hitId then hitFeedback:FireClient(plr, "HitRejected", hitId) end
		return
	end

	local targetPlr = Players:GetPlayerFromCharacter(targetChar)
	local targetState = targetPlr and getState(targetPlr)

	if targetState and targetState.blocking then
		local torso = getTargetTorso(targetChar)
		if torso then playEffect(torso, "BlockEffect") end
		if targetPlr then
			hitFeedback:FireClient(targetPlr, "Blocked")
			CombatModule.RegisterBlockedHit(targetPlr, hrp.Position)
		end
		if hitId then hitFeedback:FireClient(plr, "HitConfirmed", hitId) end
		return
	end

	state.hitTargets[targetChar] = true
	task.delay(Config.HitClearDelay, function()
		if states[plr] then states[plr].hitTargets[targetChar] = nil end
	end)

	targetHum:TakeDamage(Config.Damage)

	local pushDir = targetHrp.Position - hrp.Position
	pushDir = Vector3.new(pushDir.X, 0, pushDir.Z)
	if pushDir.Magnitude > 0 then pushDir = pushDir.Unit else pushDir = hrp.CFrame.LookVector end
	applyKnockback(targetChar, pushDir)

	local torso = getTargetTorso(targetChar)
	if torso then
		playEffect(torso, "HitEffect")
		playSound(torso, thisCombo == 1 and "Punched1" or "Punched2")
	end
	if targetPlr then hitFeedback:FireClient(targetPlr, "TookHit") end
	if hitId then hitFeedback:FireClient(plr, "HitConfirmed", hitId) end
end

-- { block handling }
function CombatModule.SetBlocking(plr, isBlocking)
	local state = getState(plr)
	if not state then return end

	local now = os.clock()
	if now - state.lastBlockToggle < Config.BlockToggleCooldown then return end
	state.lastBlockToggle = now

	if isBlocking then
		if state.blocking then return end
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		if now - state.lastAttack < Config.AttackCooldown then return end
		state.blocking = true
		state.blockStarted = now
		state.blockHits = 0
		hitFeedback:FireClient(plr, "BlockStart")
	else
		if not state.blocking then return end
		if now - state.blockStarted < Config.BlockMinDuration then return end
		state.blocking = false
		state.blockHits = 0
		hitFeedback:FireClient(plr, "BlockEnd")
	end
end

function CombatModule.IsBlocking(plr)
	local state = getState(plr)
	return state and state.blocking or false
end

function CombatModule.RegisterBlockedHit(plr, fromPos)
	local state = getState(plr)
	if not state or not state.blocking then return false end

	state.blockHits += 1
	if state.blockHits < Config.BlockMaxHits then return false end

	state.blocking = false
	state.blockHits = 0
	hitFeedback:FireClient(plr, "BlockEnd")
	hitFeedback:FireClient(plr, "BlockBroken")

	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and fromPos then
		local dir = hrp.Position - fromPos
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude > 0 then dir = dir.Unit else dir = -hrp.CFrame.LookVector end
		applyKnockback(char, dir, Config.BlockBreakKnockback)
	end
	return true
end

-- { player lifecycle }
function CombatModule.AddPlayer(plr)
	states[plr] = makeState()
end

function CombatModule.RemovePlayer(plr)
	states[plr] = nil
end

function CombatModule.OnCharacterAdded(plr, char)
	if not states[plr] then
		states[plr] = makeState()
	else
		local s = states[plr]
		s.comboIndex = 1
		s.blocking = false
		s.hitTargets = {}
	end
end

return CombatModule
