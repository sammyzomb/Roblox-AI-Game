--!strict
-- Pure training-session state machine (Task #23 correction increment).
--
-- Extracted out of TrainingGroundService so the exact lifecycle rules -
-- entering only from a valid prior state, restoring the *original* ruleset
-- (not a hardcoded default) on exit/death/disconnect, and rejecting server
-- mutations while training - are unit-testable without any live Roblox
-- services, and so the service and the tests can never drift apart.
--
-- This module has no knowledge of Players, CombatService, or Roblox at all;
-- it only tracks per-id session records. The service wraps it and supplies
-- the actual CombatService calls (SetRuleset/ResetVitals) as side effects.

local TrainingSession = {}
TrainingSession.__index = TrainingSession

export type Record = {
	Training: boolean,
	PriorRuleset: string,
}

export type Session = {
	_records: { [string]: Record },
}

function TrainingSession.new(): Session
	return setmetatable({ _records = {} }, TrainingSession) :: any
end

function TrainingSession.IsTraining(self: Session, id: string): boolean
	local record = self._records[id]
	return record ~= nil and record.Training == true
end

-- Returns the ruleset a player was on before entering training, or nil if
-- they are not currently training.
function TrainingSession.PriorRuleset(self: Session, id: string): string?
	local record = self._records[id]
	if record and record.Training then
		return record.PriorRuleset
	end
	return nil
end

-- Begins a training session. `currentRuleset` must be the combatant's
-- ruleset *right now* (before switching to Training) so Exit/death/
-- disconnect can restore it correctly instead of assuming "PvE". Re-entering
-- while already training keeps the originally captured prior ruleset (does
-- not overwrite it with "Training" from a stale second call).
function TrainingSession.Enter(self: Session, id: string, currentRuleset: string)
	local record = self._records[id]
	if record and record.Training then
		-- Already training: idempotent, keep the original PriorRuleset.
		return
	end
	self._records[id] = { Training = true, PriorRuleset = currentRuleset }
end

-- Ends a training session and returns the ruleset that should be restored.
-- Returns nil (and does nothing) if the id was not training.
function TrainingSession.Exit(self: Session, id: string): string?
	local record = self._records[id]
	if record == nil or not record.Training then
		return nil
	end
	self._records[id] = nil
	return record.PriorRuleset
end

-- Same contract as Exit, for death/disconnect cleanup paths that need to
-- restore the prior ruleset rather than merely clearing a flag.
function TrainingSession.OnDeathOrDisconnect(self: Session, id: string): string?
	return self:Exit(id)
end

return TrainingSession
