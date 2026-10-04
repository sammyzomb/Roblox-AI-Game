--!strict
-- Pure repair plan for TrainingSceneBootstrap.
--
-- The bootstrap service applies this plan to real Instances. The plan has
-- no Roblox API, so unit tests can cover the finite role-tag set and the
-- Part rebuild policy. Tests still cannot prove CollectionService,
-- BasePart.Touched, Destroy, or that a tag listener observes a configured
-- Instance. Those stay Studio checks.
--
-- Replacing an owned non-Part does not keep the old Instance. The
-- replacement tag list is the snapshot's non-role tags plus at most the
-- expected scene role. Debug parts keep none of the three roles. Wrong
-- scene roles are dropped. Skip and in-place repair do not carry a
-- replacement tag list, so an unowned name collision is left unchanged.

local TrainingSceneRepair = {}

TrainingSceneRepair.RequiredClass = "Part"

-- Finite scene-role set. Owned children are reconciled to exactly one of
-- these, or to none for debug parts. Tags outside this set are never
-- added or removed by the plan.
TrainingSceneRepair.SceneRoleTags = { "TrainingEntrance", "TrainingExit", "TrainingReturnSpawn" }

local ROLE_SET = {
	TrainingEntrance = true,
	TrainingExit = true,
	TrainingReturnSpawn = true,
}

export type TagPlan = {
	add: { string },
	remove: { string },
}

export type ChildState = {
	className: string,
	owned: boolean,
}

export type RepairAction = "create" | "repair" | "replace" | "skip"

export type RepairDecision = {
	action: RepairAction,
	warning: string?,
}

-- `tags` is set only for action "replace": the tags to add after the new
-- Part is configured and parented. Nil for create, in-place repair, and
-- skip. An unowned collision therefore has no tag rewrite in the plan.
export type ClassReplacementPlan = {
	action: RepairAction,
	warning: string?,
	tags: { string }?,
}

-- `expectedTag` nil means a debug part that must carry none of the three
-- scene roles. Other tags in `currentTags` are left out of both lists.
function TrainingSceneRepair.reconcileRoleTags(currentTags: { string }, expectedTag: string?): TagPlan
	if expectedTag ~= nil and ROLE_SET[expectedTag] ~= true then
		error(`scene role tag "{expectedTag}" is outside the finite role set`, 2)
	end

	local present: { [string]: boolean } = {}
	for _, tag in currentTags do
		present[tag] = true
	end

	local add: { string } = {}
	local remove: { string } = {}
	if expectedTag ~= nil and present[expectedTag] ~= true then
		table.insert(add, expectedTag)
	end
	for _, role in TrainingSceneRepair.SceneRoleTags do
		if present[role] == true and role ~= expectedTag then
			table.insert(remove, role)
		end
	end
	return { add = add, remove = remove }
end

-- Applies a tag plan to a tag list. Used by tests to simulate a second
-- repair. Bootstrap performs the same add/remove against CollectionService.
function TrainingSceneRepair.applyRoleTags(currentTags: { string }, plan: TagPlan): { string }
	local removeSet: { [string]: boolean } = {}
	for _, tag in plan.remove do
		removeSet[tag] = true
	end

	local nextTags: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, tag in currentTags do
		if removeSet[tag] ~= true and seen[tag] ~= true then
			table.insert(nextTags, tag)
			seen[tag] = true
		end
	end
	for _, tag in plan.add do
		if seen[tag] ~= true then
			table.insert(nextTags, tag)
			seen[tag] = true
		end
	end
	return nextTags
end

-- `existing` nil means the child name is absent. Owned non-Part children
-- are replaced. Unowned name collisions are skipped and never described as
-- a class rebuild.
function TrainingSceneRepair.decideChildRepair(name: string, containerName: string, existing: ChildState?): RepairDecision
	if existing == nil then
		return { action = "create" }
	end

	if existing.owned ~= true then
		return {
			action = "skip",
			warning = `[Combat] Training scene bootstrap found an unowned object named "{name}" (class={existing.className}) under {containerName}; leaving it unchanged and skipping repair for this child.`,
		}
	end

	if existing.className ~= TrainingSceneRepair.RequiredClass then
		return {
			action = "replace",
			warning = `[Combat] Training scene bootstrap found an owned "{name}" whose class is {existing.className}, not {TrainingSceneRepair.RequiredClass}; replacing it with a {TrainingSceneRepair.RequiredClass} and restoring scene settings.`,
		}
	end

	return { action = "repair" }
end

-- Tags the new Part should carry after an owned class replacement.
-- Non-role tags stay, in their original order. The finite role set keeps
-- only `expectedTag` (or none, when that is nil). Wrong scene roles are
-- not copied onto the replacement.
function TrainingSceneRepair.replacementTags(currentTags: { string }, expectedTag: string?): { string }
	return TrainingSceneRepair.applyRoleTags(currentTags, TrainingSceneRepair.reconcileRoleTags(currentTags, expectedTag))
end

-- Combines the class decision with the replacement tag list. Callers that
-- skip or repair in place get no `tags` field, so they cannot apply a
-- rebuilt tag set to an object this plan did not replace.
function TrainingSceneRepair.planClassReplacement(
	name: string,
	containerName: string,
	existing: ChildState?,
	currentTags: { string },
	expectedTag: string?
): ClassReplacementPlan
	local decision = TrainingSceneRepair.decideChildRepair(name, containerName, existing)
	if decision.action ~= "replace" then
		return {
			action = decision.action,
			warning = decision.warning,
		}
	end

	return {
		action = "replace",
		warning = decision.warning,
		tags = TrainingSceneRepair.replacementTags(currentTags, expectedTag),
	}
end

return TrainingSceneRepair
