--!strict
-- Global economy constants. Tune pacing here; tools/simulate.luau replays a session with them.

local Economy = {}

Economy.StartingEnergy = 0
Economy.BaseStorage = 40
-- Stars gained through fusion multiply an artifact's output.
Economy.StarMultipliers = { 1, 1.75, 3, 5, 8 }
Economy.MaxStars = #Economy.StarMultipliers
Economy.FusionCopies = 3
-- Energy cost to fuse = artifact value * FusionCostFactor * current stars.
Economy.FusionCostFactor = 2
-- Sold artifacts give `value * starMultiplier * mutationMult * SellFactor`.
Economy.SellFactor = 1
-- Luck can never exceed this multiplier, whatever the stacking.
Economy.MaxLuck = 25
-- Duplicate chance cap (Echo Duplicator & co.).
Economy.MaxDuplicateChance = 0.5
-- Speed (fabricator / printer interval reduction) is applied as interval / (1 + speed).
Economy.MaxSpeedBonus = 1.5
-- Hard floors (seconds) after every speed bonus.
Economy.MinChargeInterval = 2
Economy.MinPrinterInterval = 3
-- Server simulation tick (seconds). Production is integrated per tick.
Economy.TickInterval = 1
-- Box printer can bank at most this many pending boxes while the player is away from the server.
Economy.PrinterBacklog = 3
-- Permanent production bonus for the collection (kept through rebirths).
Economy.CollectionBonusPerArtifact = 0.01
Economy.CollectionBonusPerVariant = 0.0025
-- Every quest reward is at least this many seconds of the player's current production.
Economy.QuestRewardSeconds = 30

return Economy
