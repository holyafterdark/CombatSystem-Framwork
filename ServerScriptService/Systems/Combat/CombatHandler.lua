local Players = game:GetService("Players")

local CombatModule = require(script.Parent.CombatModule)

-- { variables }
local rep = game.ReplicatedStorage
local combatRemotes = rep:WaitForChild("Remotes"):WaitForChild("Combat")
local punchRemote = combatRemotes:WaitForChild("Punch")
local blockRemote = combatRemotes:WaitForChild("Block")

-- { functions }
local function onPlayerAdded(plr)
	CombatModule.AddPlayer(plr)
	plr.CharacterAdded:Connect(function(char)
		CombatModule.OnCharacterAdded(plr, char)
	end)
	if plr.Character then
		CombatModule.OnCharacterAdded(plr, plr.Character)
	end
end

for _, plr in pairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, plr)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(CombatModule.RemovePlayer)

punchRemote.OnServerEvent:Connect(function(plr, payload)
	CombatModule.HandlePunch(plr, payload)
end)

blockRemote.OnServerEvent:Connect(function(plr, state)
	if type(state) ~= "boolean" then return end
	CombatModule.SetBlocking(plr, state)
end)
