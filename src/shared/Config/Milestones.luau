--!strict
-- Collection milestones: rewards for discovering artifacts and mutation variants. They are
-- claimed from Collection → Rewards and never reset (not even on rebirth).
-- `artifacts` counts different artifacts found, `variants` counts mutation variants found.

export type Milestone = {
	id: string,
	artifacts: number?,
	variants: number?,
	reward: { [string]: any },
}

local Milestones = {}

Milestones.List = {
	{ id = "artifacts_3", artifacts = 3, reward = { seconds = 120, min = 1000 } },
	{ id = "artifacts_6", artifacts = 6, reward = { crates = 1 } },
	{ id = "artifacts_9", artifacts = 9, reward = { seconds = 600, min = 20000, boost = "luck", duration = 600 } },
	{ id = "artifacts_12", artifacts = 12, reward = { crates = 2, shards = 1 } },
	{ id = "artifacts_15", artifacts = 15, reward = { shards = 3, boost = "energy", duration = 1800 } },
	{ id = "variants_2", variants = 2, reward = { seconds = 300, min = 5000 } },
	{ id = "variants_5", variants = 5, reward = { crates = 1, shards = 1 } },
	{ id = "variants_10", variants = 10, reward = { shards = 3 } },
} :: { Milestone }

local byId: { [string]: Milestone } = {}
for _, milestone in Milestones.List do
	byId[milestone.id] = milestone
end

function Milestones.get(id: string): Milestone?
	return byId[id]
end

return Milestones
