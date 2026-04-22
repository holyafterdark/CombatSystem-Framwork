-- { constants }
local BLOCK_KEY = Enum.KeyCode.F
local TOOL_NAME = "Fists"
local ATTACK_COOLDOWN = 0.4
local COMBO_RESET = 1.2
local MAX_COMBO = 3
local SHAKE_DURATION = 0.08
local SHAKE_RECOVER = 0.12

-- { variables }
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local plr = Players.LocalPlayer
local rep = game.ReplicatedStorage
local combatRemotes = rep:WaitForChild("Remotes"):WaitForChild("Combat")
local punchRemote = combatRemotes:WaitForChild("Punch")
local blockRemote = combatRemotes:WaitForChild("Block")
local hitFeedback = combatRemotes:WaitForChild("HitFeedback")

local combatAssets = rep:WaitForChild("CombatAssets")
local animFolder = combatAssets:WaitForChild("Animations")
local soundsFolder = combatAssets:WaitForChild("Sounds")
local effectsFolder = combatAssets:WaitForChild("Effects")

local m1Folder = animFolder:WaitForChild("M1")
local leftPunchAnim = m1Folder:WaitForChild("LeftPunch")
local rightPunchAnim = m1Folder:WaitForChild("RightPunch")
local thirdPunchAnim = m1Folder:WaitForChild("ThirdPunch")
local blockAnim = animFolder:WaitForChild("Blocking"):WaitForChild("BlockAnim")
local combatAnimFolder = animFolder:WaitForChild("Combat")
local equipAnim = combatAnimFolder:WaitForChild("Equip")
local idleAnim = combatAnimFolder:WaitForChild("Idle")

local tracks = {}
local blocking = false
local comboIndex = 1
local lastAttack = 0
local pending = {}
local equipped = false
local equipping = false

-- { functions }
local setEquipped

local function loadTracks(char)
	local hum = char:WaitForChild("Humanoid")
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	tracks.RightPunch = animator:LoadAnimation(rightPunchAnim)
	tracks.LeftPunch = animator:LoadAnimation(leftPunchAnim)
	tracks.ThirdPunch = animator:LoadAnimation(thirdPunchAnim)
	for _, name in ipairs({ "RightPunch", "LeftPunch", "ThirdPunch" }) do
		tracks[name].Priority = Enum.AnimationPriority.Action
		tracks[name].Looped = false
	end
	tracks.Block = animator:LoadAnimation(blockAnim)
	tracks.Block.Priority = Enum.AnimationPriority.Action
	tracks.Equip = animator:LoadAnimation(equipAnim)
	tracks.Equip.Priority = Enum.AnimationPriority.Action
	tracks.Equip.Looped = false
	tracks.Idle = animator:LoadAnimation(idleAnim)
	tracks.Idle.Priority = Enum.AnimationPriority.Idle
	tracks.Idle.Looped = true
end

local function shakeCamera(intensity)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local mag = 0.15 * (intensity or 1)
	local offset = Vector3.new((math.random() - 0.5) * mag, (math.random() - 0.5) * mag, -mag * 0.5)
	TweenService:Create(hum, TweenInfo.new(SHAKE_DURATION), { CameraOffset = offset }):Play()
	task.delay(SHAKE_DURATION, function()
		if hum and hum.Parent then
			TweenService:Create(hum, TweenInfo.new(SHAKE_RECOVER), { CameraOffset = Vector3.zero }):Play()
		end
	end)
end

local function bindTool(tool)
	tool.Equipped:Connect(function() task.spawn(setEquipped, true) end)
	tool.Unequipped:Connect(function() task.spawn(setEquipped, false) end)
end

local function watchForTool(char)
	local backpack = plr:WaitForChild("Backpack", 5)
	if not backpack then return end
	local function tryBind(c)
		if c:IsA("Tool") and c.Name == TOOL_NAME then bindTool(c) end
	end
	for _, c in pairs(backpack:GetChildren()) do tryBind(c) end
	for _, c in pairs(char:GetChildren()) do tryBind(c) end
	backpack.ChildAdded:Connect(tryBind)
	char.ChildAdded:Connect(tryBind)
end

local function onCharacterAdded(char)
	tracks = {}
	blocking = false
	comboIndex = 1
	lastAttack = 0
	pending = {}
	equipped = false
	equipping = false
	loadTracks(char)
	task.spawn(watchForTool, char)
end

local function playLocalSound(parent, name)
	local original = soundsFolder:FindFirstChild(name)
	if not original or not parent then return end
	local s = original:Clone()
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 2)
end

local function playLocalEffect(parent, name)
	local original = effectsFolder:FindFirstChild(name)
	if not original or not parent then return end
	local e = original:Clone()
	e.Parent = parent
	Debris:AddItem(e, 2)
end

local function findLocalTarget(char, hrp)
	local origin = hrp.CFrame.Position + hrp.CFrame.LookVector * 2
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local parts = workspace:GetPartBoundsInRadius(origin, 2.6, params)
	local closest, closestDist = nil, math.huge
	for _, p in pairs(parts) do
		local m = p.Parent
		local h = m and m:FindFirstChildOfClass("Humanoid")
		local targetHrp = m and m:FindFirstChild("HumanoidRootPart")
		if h and targetHrp and h.Health > 0 and m ~= char then
			local d = (targetHrp.Position - origin).Magnitude
			if d < closestDist then closest, closestDist = m, d end
		end
	end
	return closest
end

function setEquipped(state)
	if equipping then return end
	if equipped == state then return end
	equipping = true
	if state then
		if tracks.Equip then
			tracks.Equip:Play()
			tracks.Equip.Stopped:Wait()
		end
		equipped = true
		if tracks.Idle then tracks.Idle:Play() end
	else
		if tracks.Equip then tracks.Equip:Stop() end
		if tracks.Idle then tracks.Idle:Stop() end
		equipped = false
	end
	equipping = false
end

local function tryPunch()
	if not equipped or blocking then return end
	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end

	local now = os.clock()
	if now - lastAttack < ATTACK_COOLDOWN then return end
	if now - lastAttack > COMBO_RESET then comboIndex = 1 end

	local thisCombo = comboIndex
	lastAttack = now
	comboIndex = (comboIndex % MAX_COMBO) + 1

	local trackName = thisCombo == 1 and "RightPunch" or thisCombo == 2 and "LeftPunch" or "ThirdPunch"
	if tracks[trackName] then tracks[trackName]:Play() end
	shakeCamera(thisCombo == 3 and 1.4 or 1)
	playLocalSound(hrp, "Swing")

	local target = findLocalTarget(char, hrp)
	local hitId = tostring(now) .. "_" .. tostring(math.random(1, 1e6))

	if target then
		local torso = target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso")
		if torso then
			playLocalEffect(torso, "HitEffect")
			playLocalSound(torso, thisCombo == 1 and "Punched1" or "Punched2")
		end
		pending[hitId] = { target = target, time = now }
		task.delay(2, function() pending[hitId] = nil end)
		local targetPlr = Players:GetPlayerFromCharacter(target)
		punchRemote:FireServer({
			hitId = hitId,
			targetUserId = targetPlr and targetPlr.UserId or nil,
			timestamp = now,
			origin = hrp.Position,
			direction = hrp.CFrame.LookVector,
			combo = thisCombo,
		})
	else
		punchRemote:FireServer({
			hitId = hitId,
			timestamp = now,
			origin = hrp.Position,
			direction = hrp.CFrame.LookVector,
			combo = thisCombo,
		})
	end
end

if plr.Character then onCharacterAdded(plr.Character) end
plr.CharacterAdded:Connect(onCharacterAdded)

hitFeedback.OnClientEvent:Connect(function(action, data)
	if action == "HitRejected" or action == "HitConfirmed" then
		pending[data] = nil
	elseif action == "BlockStart" then
		if tracks.Block then tracks.Block:Play() end
	elseif action == "BlockEnd" then
		if tracks.Block then tracks.Block:Stop() end
	end
end)

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		tryPunch()
	elseif input.KeyCode == BLOCK_KEY then
		if equipped and not blocking then
			blocking = true
			blockRemote:FireServer(true)
		end
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.KeyCode == BLOCK_KEY and blocking then
		blocking = false
		blockRemote:FireServer(false)
	end
end)
