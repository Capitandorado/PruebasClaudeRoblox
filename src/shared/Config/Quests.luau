--!strict
-- Quest pool. Three quests are active at a time; claiming one draws a new one.
-- `target` is scaled by the player's rebirths (targetPerRebirth) so quests stay meaningful.
-- Reward = max(rewardBase * (1 + rebirths), production * Economy.QuestRewardSeconds * rewardScale).
-- Only use stats that cannot be farmed for free (every stat here costs time, items or Energy).

export type Quest = {
	id: string,
	stat: string,
	target: number,
	targetPerRebirth: number,
	rewardBase: number,
	rewardScale: number,
	text: string,
	rarity: string?,
}

local Quests = {}

Quests.ActiveCount = 3

Quests.List = {
	{
		id = "open_15",
		stat = "boxesOpened",
		target = 15,
		targetPerRebirth = 10,
		rewardBase = 120,
		rewardScale = 1,
		text = "Open %d boxes",
	},
	{
		id = "open_60",
		stat = "boxesOpened",
		target = 60,
		targetPerRebirth = 30,
		rewardBase = 600,
		rewardScale = 3,
		text = "Open %d boxes",
	},
	{
		id = "earn_energy",
		stat = "energyEarned",
		target = 2500,
		targetPerRebirth = 20000,
		rewardBase = 300,
		rewardScale = 2,
		text = "Produce %s Energy",
	},
	{
		id = "discover",
		stat = "discoveries",
		target = 1,
		targetPerRebirth = 0,
		rewardBase = 250,
		rewardScale = 3,
		text = "Discover %d new artifact(s) or mutation variant(s)",
	},
	{
		id = "find_rare",
		stat = "foundRare",
		target = 3,
		targetPerRebirth = 2,
		rewardBase = 400,
		rewardScale = 2,
		text = "Find %d Rare-or-better artifacts",
	},
	{
		id = "find_epic",
		stat = "foundEpic",
		target = 1,
		targetPerRebirth = 1,
		rewardBase = 1500,
		rewardScale = 4,
		text = "Find %d Epic-or-better artifact(s)",
	},
	{
		id = "sell_items",
		stat = "itemsSold",
		target = 10,
		targetPerRebirth = 10,
		rewardBase = 200,
		rewardScale = 1,
		text = "Sell %d artifacts",
	},
	{
		id = "fuse_items",
		stat = "fusions",
		target = 1,
		targetPerRebirth = 1,
		rewardBase = 1000,
		rewardScale = 3,
		text = "Fuse %d artifact(s) in the Fusion Chamber",
	},
	{
		id = "buy_upgrades",
		stat = "upgradesBought",
		target = 3,
		targetPerRebirth = 2,
		rewardBase = 500,
		rewardScale = 2,
		text = "Buy %d upgrades or machine levels",
	},
} :: { Quest }

local byId: { [string]: Quest } = {}
for _, quest in Quests.List do
	byId[quest.id] = quest
end
Quests.ById = byId

return Quests
