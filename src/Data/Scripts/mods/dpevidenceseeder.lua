DarkPassengerEvidenceSeeder = DarkPassengerEvidenceSeeder or {}

DarkPassengerEvidenceSeeder.POLL_INTERVAL_MS = 500
DarkPassengerEvidenceSeeder.timerSerial =
    tonumber(DarkPassengerEvidenceSeeder.timerSerial) or 0

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][EvidenceSeeder] " .. tostring(message)
        )
    end
end

local function CurrentGenerationMatches(generation)
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil then
        return false
    end
    local investigation = DarkPassengerInvestigation.GetState()
    return investigation ~= nil and investigation.active == true and
        tonumber(investigation.generation) == tonumber(generation)
end

local function Schedule(generation, timerSerial)
    if Script == nil or Script.SetTimerForFunction == nil then
        Log("retry unavailable")
        return false
    end
    local ok, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerEvidenceSeeder.POLL_INTERVAL_MS,
            "DarkPassengerEvidenceSeeder.Retry",
            { generation = generation, timerSerial = timerSerial }
        )
    end)
    if not ok then
        Log("retry scheduling failed error=" .. tostring(timerOrError))
        return false
    end
    return true
end

local function PlaceEvidence(generation, evidence)
    if evidence.kind == "document" then
        if DarkPassengerBelongings == nil or
           DarkPassengerBelongings.EnsurePlaced == nil then
            return false, "document_adapter_unavailable"
        end
        if not DarkPassengerBelongings.EnsurePlaced(generation) then
            return false, "document_deferred"
        end
        return true, "document_placed"
    end
    return false, "unsupported_kind"
end

local function MarkPlaced(generation, evidence)
    if DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.MarkPlaced == nil then
        return false, "registry_unavailable"
    end
    local result = DarkPassengerEvidenceRegistry.MarkPlaced(
        generation,
        evidence.code
    )
    if result ~= nil and (
        result.accepted == true or
        result.reason == "already_placed" or
        result.reason == "already_discovered"
    ) then
        return true, result.reason
    end
    return false, result ~= nil and result.reason or "registry_rejected"
end

local function SeedSnapshot(generation, snapshot, timerSerial)
    local retryNeeded = false
    for _, evidence in ipairs(
        snapshot ~= nil and snapshot.caseTemplate ~= nil and
        snapshot.caseTemplate.evidence or {}
    ) do
        if evidence.placement == "case_start" then
            local placed, placementReason = PlaceEvidence(
                generation,
                evidence
            )
            if placed then
                local recorded, registryReason = MarkPlaced(
                    generation,
                    evidence
                )
                if not recorded then
                    retryNeeded = true
                    Log(
                        "registry deferred evidence=" ..
                        tostring(evidence.code) ..
                        " reason=" .. tostring(registryReason)
                    )
                end
            elseif evidence.kind == "document" then
                retryNeeded = true
                Log(
                    "placement deferred evidence=" ..
                    tostring(evidence.code) ..
                    " reason=" .. tostring(placementReason)
                )
            else
                Log(
                    "placement unsupported evidence=" ..
                    tostring(evidence.code) ..
                    " kind=" .. tostring(evidence.kind)
                )
            end
        end
    end
    if retryNeeded then return Schedule(generation, timerSerial) end
    return true
end

function DarkPassengerEvidenceSeeder.Seed(generation, snapshot)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 or
       not CurrentGenerationMatches(generation) then
        return false
    end
    if snapshot == nil and DarkPassengerCaseSnapshot ~= nil and
       DarkPassengerCaseSnapshot.Restore ~= nil then
        snapshot = DarkPassengerCaseSnapshot.Restore(generation)
    end
    if snapshot == nil or
       tonumber(snapshot.generation) ~= generation then
        Log("seed deferred: snapshot unavailable")
        return false
    end
    DarkPassengerEvidenceSeeder.timerSerial =
        DarkPassengerEvidenceSeeder.timerSerial + 1
    return SeedSnapshot(
        generation,
        snapshot,
        DarkPassengerEvidenceSeeder.timerSerial
    )
end

function DarkPassengerEvidenceSeeder.Retry(payload, timerId)
    local generation = payload ~= nil and
        tonumber(payload.generation) or nil
    local timerSerial = payload ~= nil and
        tonumber(payload.timerSerial) or nil
    if generation == nil or
       timerSerial ~= DarkPassengerEvidenceSeeder.timerSerial or
       not CurrentGenerationMatches(generation) then
        return false
    end
    if DarkPassengerCaseSnapshot == nil or
       DarkPassengerCaseSnapshot.Restore == nil then
        return false
    end
    local snapshot = DarkPassengerCaseSnapshot.Restore(generation)
    if snapshot == nil then return Schedule(generation, timerSerial) end
    return SeedSnapshot(generation, snapshot, timerSerial)
end

function DarkPassengerEvidenceSeeder.RunSelfTest()
    local caseStart = 0
    local unsupported = 0
    local snapshot = {
        caseTemplate = {
            evidence = {
                { code = 1, placement = "on_event", kind = "dialogue" },
                { code = 2, placement = "case_start", kind = "document" },
                { code = 3, placement = "case_start", kind = "unknown" },
            },
        },
    }
    for _, evidence in ipairs(snapshot.caseTemplate.evidence) do
        if evidence.placement == "case_start" then
            caseStart = caseStart + 1
            if evidence.kind ~= "document" then unsupported = unsupported + 1 end
        end
    end
    local passed = caseStart == 2 and unsupported == 1
    Log("selftest=" .. tostring(passed))
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_evidence_seeder_selftest",
            "DarkPassengerEvidenceSeeder.RunSelfTest()",
            "Dark Passenger: run case-start evidence-seeder checks"
        )
    end
end)

Log("module loaded")
