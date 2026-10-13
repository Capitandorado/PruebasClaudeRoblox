-- Machine/expansion ProximityPrompts: only usable on your own plot; they trigger the same
-- requests as the UI buttons.

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Machines = require(Shared.Config.Machines)
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local App = require(Client.UI.App)
local Box = require(script.Parent.Box)

local Prompts = {}

local function plotIndexOf(instance: Instance): number?
	local current: Instance? = instance
	while current do
		local index = current:GetAttribute("PlotIndex")
		if type(index) == "number" and current:IsA("Model") and string.match(current.Name, "^Plot_") then
			return index
		end
		current = current.Parent
	end
	return nil
end

local function isOwn(prompt: Instance): boolean
	return plotIndexOf(prompt) == Store.plot and Store.plot ~= 0
end

local function enforce(prompt: Instance)
	-- Until the client knows its plot it cannot tell whose prompt this is: leave it alone
	-- (triggering is still checked here and on the server), and enforce on Store.Ready.
	if Store.plot == 0 then
		return
	end
	if prompt:IsA("ProximityPrompt") and prompt.Enabled and not isOwn(prompt) then
		prompt.Enabled = false
	end
end

local function track(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	enforce(prompt)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		enforce(prompt)
	end)
end

function Prompts.trigger(prompt: ProximityPrompt)
	if not isOwn(prompt) then
		return
	end
	local action = prompt:GetAttribute("Action")
	local machineId = prompt:GetAttribute("MachineId")
	if action == "OpenBox" and type(machineId) == "string" then
		task.spawn(Box.open, machineId)
	elseif action == "BuyMachine" and type(machineId) == "string" then
		local machine = Machines.get(machineId)
		local response = Remote.request("BuyMachine", machineId)
		if response.ok then
			Sound.play("Unlock")
			App.toast("Bought " .. (if machine then machine.name else machineId) .. "!", "success")
		else
			App.showError(response.err)
			if response.err == "NotEnoughEnergy" and machine then
				App.toast("Costs ⚡" .. Format.number(machine.cost), "info")
			end
		end
	elseif action == "BuyExpansion" then
		local response = Remote.request("BuyExpansion")
		if response.ok then
			Sound.play("Unlock")
			App.toast("Plot expanded!", "success")
		else
			App.showError(response.err)
		end
	elseif action == "OpenFusion" then
		App.openWindow("Inventory")
	elseif action == "OpenShop" then
		App.openWindow("Shop")
	end
end

function Prompts.start()
	for _, prompt in CollectionService:GetTagged("MachinePrompt") do
		track(prompt)
	end
	CollectionService:GetInstanceAddedSignal("MachinePrompt"):Connect(track)
	Store.Ready:Connect(function()
		for _, prompt in CollectionService:GetTagged("MachinePrompt") do
			enforce(prompt)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:HasTag("MachinePrompt") then
			Prompts.trigger(prompt)
		end
	end)
end

return Prompts
