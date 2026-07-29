DarkPassengerWitness = DarkPassengerWitness or {}

DarkPassengerWitness.SCHEMA_VERSION = 1

DarkPassengerWitness.STATE_UNREPORTED = "UNREPORTED"
DarkPassengerWitness.STATE_REPORTED = "REPORTED"
DarkPassengerWitness.STATE_SILENCED_BEFORE_REPORT =
    "SILENCED_BEFORE_REPORT"
DarkPassengerWitness.STATE_SILENCED_AFTER_REPORT =
    "SILENCED_AFTER_REPORT"
DarkPassengerWitness.STATE_LOST = "LOST"

DarkPassengerWitness.STATE_TO_CODE = {
    [DarkPassengerWitness.STATE_UNREPORTED] = 1,
    [DarkPassengerWitness.STATE_REPORTED] = 2,
    [DarkPassengerWitness.STATE_SILENCED_BEFORE_REPORT] = 3,
    [DarkPassengerWitness.STATE_SILENCED_AFTER_REPORT] = 4,
    [DarkPassengerWitness.STATE_LOST] = 5,
}
DarkPassengerWitness.CODE_TO_STATE = {
    [1] = DarkPassengerWitness.STATE_UNREPORTED,
    [2] = DarkPassengerWitness.STATE_REPORTED,
    [3] = DarkPassengerWitness.STATE_SILENCED_BEFORE_REPORT,
    [4] = DarkPassengerWitness.STATE_SILENCED_AFTER_REPORT,
    [5] = DarkPassengerWitness.STATE_LOST,
}
DarkPassengerWitness.DEATH_TRANSITIONS = {
    [DarkPassengerWitness.STATE_UNREPORTED] =
        DarkPassengerWitness.STATE_SILENCED_BEFORE_REPORT,
    [DarkPassengerWitness.STATE_REPORTED] =
        DarkPassengerWitness.STATE_SILENCED_AFTER_REPORT,
}

DarkPassengerWitness.KEYS = {
    schema = "dp_witness_schema_version",
    recordCount = "dp_witness_record_count",
    nextRecordId = "dp_witness_next_record_id",
    activeCaseGeneration = "dp_witness_active_case_generation",
    activeRegionCode = "dp_witness_active_region_code",
    activeSettlementCode = "dp_witness_active_settlement_code",
    activeTargetSlot = "dp_witness_active_target_slot",
    noisyLocked = "dp_witness_noisy_locked",
    notificationEmitted = "dp_witness_notification_emitted",
}
DarkPassengerWitness.RECORD_PREFIX = "dp_witness_v1_"
DarkPassengerWitness.RECORD_FIELDS = {
    "identity_high",
    "identity_low",
    "case_generation",
    "region_code",
    "settlement_code",
    "target_slot",
    "evidence_code",
    "identified",
    "state_code",
    "incident_time",
    "report_time",
    "death_time",
    "death_x",
    "death_y",
    "death_z",
    "death_attributed",
}

DarkPassengerWitness.records = DarkPassengerWitness.records or {}
DarkPassengerWitness.index = DarkPassengerWitness.index or {}
DarkPassengerWitness.recordCount =
    tonumber(DarkPassengerWitness.recordCount) or 0
DarkPassengerWitness.nextRecordId =
    tonumber(DarkPassengerWitness.nextRecordId) or 1
DarkPassengerWitness.activeCaseGeneration =
    tonumber(DarkPassengerWitness.activeCaseGeneration) or 0
DarkPassengerWitness.noisyLocked =
    DarkPassengerWitness.noisyLocked == true
DarkPassengerWitness.notificationEmitted =
    DarkPassengerWitness.notificationEmitted == true

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][Witness] " .. tostring(message)
        )
    end
end

local function NumberOr(value, fallback)
    local parsed = tonumber(value)
    if parsed == nil then return fallback end
    return parsed
end

local function BoolValue(value)
    return value == true or NumberOr(value, 0) == 1
end

local function ReadGlobal(key)
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, valueOrError = pcall(function()
        return Variables.GetGlobal(key)
    end)
    if not ok then
        Log(
            "persistence read failed key=" .. tostring(key) ..
            " error=" .. tostring(valueOrError)
        )
        return nil
    end
    return tonumber(valueOrError)
end

local function WriteGlobal(key, value)
    if Variables == nil or Variables.SetGlobal == nil then return false end
    local ok, resultOrError = pcall(function()
        return Variables.SetGlobal(key, NumberOr(value, 0))
    end)
    if not ok then
        Log(
            "persistence write failed key=" .. tostring(key) ..
            " error=" .. tostring(resultOrError)
        )
    end
    return ok
end

local function StableCode(value)
    local text = tostring(value or "")
    local code = 5381
    for index = 1, #text do
        code = (code * 33 + string.byte(text, index)) % 2147483647
    end
    return code
end

local function CaseCode(value)
    if type(value) == "number" then return value end
    return StableCode(value)
end

local function RecordKey(recordId, field)
    return DarkPassengerWitness.RECORD_PREFIX ..
        tostring(recordId) .. "_" .. tostring(field)
end

local function IdentityKey(identityHigh, identityLow, generation)
    return tostring(NumberOr(generation, 0)) .. ":" ..
        tostring(NumberOr(identityHigh, 0)) .. ":" ..
        tostring(NumberOr(identityLow, 0))
end

local function IndexRecord(record)
    DarkPassengerWitness.index[
        IdentityKey(
            record.identityHigh,
            record.identityLow,
            record.caseGeneration
        )
    ] = record.id
end

local function FindRecord(identityHigh, identityLow, generation)
    local key = IdentityKey(
        identityHigh,
        identityLow,
        generation or DarkPassengerWitness.activeCaseGeneration
    )
    local recordId = DarkPassengerWitness.index[key]
    if recordId == nil then return nil end
    return DarkPassengerWitness.records[recordId]
end

function DarkPassengerWitness.GetRecord(
    identityHigh,
    identityLow,
    generation
)
    return FindRecord(identityHigh, identityLow, generation)
end

local function PersistRecord(record)
    local values = {
        identity_high = record.identityHigh,
        identity_low = record.identityLow,
        case_generation = record.caseGeneration,
        region_code = record.regionCode,
        settlement_code = record.settlementCode,
        target_slot = record.targetSlot,
        evidence_code = record.evidenceCode,
        identified = record.identified and 1 or 0,
        state_code =
            DarkPassengerWitness.STATE_TO_CODE[record.state] or 0,
        incident_time = record.incidentTime,
        report_time = record.reportTime,
        death_time = record.deathTime,
        death_x = record.deathX,
        death_y = record.deathY,
        death_z = record.deathZ,
        death_attributed = record.deathAttributed and 1 or 0,
    }
    local allWritten = true
    for _, field in ipairs(DarkPassengerWitness.RECORD_FIELDS) do
        if not WriteGlobal(
            RecordKey(record.id, field),
            values[field]
        ) then
            allWritten = false
        end
    end
    return allWritten
end

function DarkPassengerWitness.IdentityFromWuid(wuid)
    local text = tostring(wuid or "")
    local hex = string.match(text, "([0-9A-Fa-f]+)$")
    if hex == nil or #hex < 16 then return nil, nil end
    hex = string.sub(hex, #hex - 15)
    local identityHigh = tonumber(string.sub(hex, 1, 8), 16)
    local identityLow = tonumber(string.sub(hex, 9, 16), 16)
    return identityHigh, identityLow
end

function DarkPassengerWitness.Persist(record)
    local keys = DarkPassengerWitness.KEYS
    local writes = {
        { keys.schema, DarkPassengerWitness.SCHEMA_VERSION },
        { keys.recordCount, DarkPassengerWitness.recordCount },
        { keys.nextRecordId, DarkPassengerWitness.nextRecordId },
        {
            keys.activeCaseGeneration,
            DarkPassengerWitness.activeCaseGeneration,
        },
        {
            keys.activeRegionCode,
            NumberOr(DarkPassengerWitness.activeRegionCode, 0),
        },
        {
            keys.activeSettlementCode,
            NumberOr(DarkPassengerWitness.activeSettlementCode, 0),
        },
        {
            keys.activeTargetSlot,
            NumberOr(DarkPassengerWitness.activeTargetSlot, 0),
        },
        { keys.noisyLocked, DarkPassengerWitness.noisyLocked and 1 or 0 },
        {
            keys.notificationEmitted,
            DarkPassengerWitness.notificationEmitted and 1 or 0,
        },
    }
    local allWritten = true
    for _, entry in ipairs(writes) do
        if not WriteGlobal(entry[1], entry[2]) then
            allWritten = false
        end
    end
    if record ~= nil and not PersistRecord(record) then
        allWritten = false
    end
    return allWritten
end

function DarkPassengerWitness.Restore(reason)
    local keys = DarkPassengerWitness.KEYS
    if ReadGlobal(keys.schema) ~= DarkPassengerWitness.SCHEMA_VERSION then
        Log("restore skipped reason=" .. tostring(reason) .. " state=missing")
        return false
    end

    DarkPassengerWitness.recordCount = math.max(
        0,
        NumberOr(ReadGlobal(keys.recordCount), 0)
    )
    DarkPassengerWitness.nextRecordId = math.max(
        DarkPassengerWitness.recordCount + 1,
        NumberOr(
            ReadGlobal(keys.nextRecordId),
            DarkPassengerWitness.recordCount + 1
        )
    )
    DarkPassengerWitness.activeCaseGeneration = math.max(
        0,
        NumberOr(ReadGlobal(keys.activeCaseGeneration), 0)
    )
    DarkPassengerWitness.activeRegionCode =
        NumberOr(ReadGlobal(keys.activeRegionCode), 0)
    DarkPassengerWitness.activeSettlementCode =
        NumberOr(ReadGlobal(keys.activeSettlementCode), 0)
    DarkPassengerWitness.activeTargetSlot =
        NumberOr(ReadGlobal(keys.activeTargetSlot), 0)
    DarkPassengerWitness.noisyLocked =
        NumberOr(ReadGlobal(keys.noisyLocked), 0) == 1
    DarkPassengerWitness.notificationEmitted =
        NumberOr(ReadGlobal(keys.notificationEmitted), 0) == 1
    DarkPassengerWitness.records = {}
    DarkPassengerWitness.index = {}

    for recordId = 1, DarkPassengerWitness.recordCount do
        local state = DarkPassengerWitness.CODE_TO_STATE[
            NumberOr(ReadGlobal(RecordKey(recordId, "state_code")), 0)
        ]
        if state ~= nil then
            local record = {
                id = recordId,
                identityHigh = NumberOr(
                    ReadGlobal(RecordKey(recordId, "identity_high")),
                    0
                ),
                identityLow = NumberOr(
                    ReadGlobal(RecordKey(recordId, "identity_low")),
                    0
                ),
                caseGeneration = NumberOr(
                    ReadGlobal(RecordKey(recordId, "case_generation")),
                    0
                ),
                regionCode = NumberOr(
                    ReadGlobal(RecordKey(recordId, "region_code")),
                    0
                ),
                settlementCode = NumberOr(
                    ReadGlobal(RecordKey(recordId, "settlement_code")),
                    0
                ),
                targetSlot = NumberOr(
                    ReadGlobal(RecordKey(recordId, "target_slot")),
                    0
                ),
                evidenceCode = NumberOr(
                    ReadGlobal(RecordKey(recordId, "evidence_code")),
                    0
                ),
                identified =
                    NumberOr(
                        ReadGlobal(RecordKey(recordId, "identified")),
                        0
                    ) == 1,
                state = state,
                incidentTime = NumberOr(
                    ReadGlobal(RecordKey(recordId, "incident_time")),
                    0
                ),
                reportTime = NumberOr(
                    ReadGlobal(RecordKey(recordId, "report_time")),
                    0
                ),
                deathTime = NumberOr(
                    ReadGlobal(RecordKey(recordId, "death_time")),
                    0
                ),
                deathX = NumberOr(
                    ReadGlobal(RecordKey(recordId, "death_x")),
                    0
                ),
                deathY = NumberOr(
                    ReadGlobal(RecordKey(recordId, "death_y")),
                    0
                ),
                deathZ = NumberOr(
                    ReadGlobal(RecordKey(recordId, "death_z")),
                    0
                ),
                deathAttributed =
                    NumberOr(
                        ReadGlobal(
                            RecordKey(recordId, "death_attributed")
                        ),
                        0
                    ) == 1,
            }
            DarkPassengerWitness.records[recordId] = record
            IndexRecord(record)
        end
    end

    Log(
        "restored reason=" .. tostring(reason) ..
        " records=" .. tostring(DarkPassengerWitness.recordCount) ..
        " generation=" ..
        tostring(DarkPassengerWitness.activeCaseGeneration) ..
        " noisy_locked=" .. tostring(DarkPassengerWitness.noisyLocked)
    )
    return true
end

function DarkPassengerWitness.BeginCase(
    generation,
    region,
    settlement,
    targetSlot
)
    DarkPassengerWitness.activeCaseGeneration =
        math.max(0, NumberOr(generation, 0))
    DarkPassengerWitness.activeRegionCode = CaseCode(region)
    DarkPassengerWitness.activeSettlementCode = CaseCode(settlement)
    DarkPassengerWitness.activeTargetSlot = NumberOr(targetSlot, 0)
    DarkPassengerWitness.noisyLocked = false
    DarkPassengerWitness.notificationEmitted = false
    DarkPassengerWitness.Persist()
    Log(
        "begin generation=" ..
        tostring(DarkPassengerWitness.activeCaseGeneration) ..
        " target=" .. tostring(DarkPassengerWitness.activeTargetSlot)
    )
    return true
end

function DarkPassengerWitness.Confirm(
    identityHigh,
    identityLow,
    evidenceCode,
    identified,
    incidentTime,
    deathX,
    deathY,
    deathZ
)
    local generation = DarkPassengerWitness.activeCaseGeneration
    if generation <= 0 then return nil end
    local high = NumberOr(identityHigh, -1)
    local low = NumberOr(identityLow, -1)
    if high < 0 or low < 0 then return nil end

    local existing = FindRecord(high, low, generation)
    if existing ~= nil then
        if BoolValue(identified) and not existing.identified then
            existing.identified = true
            DarkPassengerWitness.Persist(existing)
        end
        return existing
    end

    local recordId = DarkPassengerWitness.nextRecordId
    local record = {
        id = recordId,
        identityHigh = high,
        identityLow = low,
        caseGeneration = generation,
        regionCode =
            NumberOr(DarkPassengerWitness.activeRegionCode, 0),
        settlementCode =
            NumberOr(DarkPassengerWitness.activeSettlementCode, 0),
        targetSlot =
            NumberOr(DarkPassengerWitness.activeTargetSlot, 0),
        evidenceCode = NumberOr(evidenceCode, 0),
        identified = BoolValue(identified),
        state = DarkPassengerWitness.STATE_UNREPORTED,
        incidentTime = NumberOr(incidentTime, 0),
        reportTime = 0,
        deathTime = 0,
        deathX = NumberOr(deathX, 0),
        deathY = NumberOr(deathY, 0),
        deathZ = NumberOr(deathZ, 0),
        deathAttributed = false,
    }
    DarkPassengerWitness.records[recordId] = record
    DarkPassengerWitness.recordCount =
        math.max(DarkPassengerWitness.recordCount, recordId)
    DarkPassengerWitness.nextRecordId = recordId + 1
    IndexRecord(record)
    DarkPassengerWitness.Persist(record)
    Log(
        "confirmed record=" .. tostring(recordId) ..
        " identity=" .. IdentityKey(high, low, generation) ..
        " evidence=" .. tostring(record.evidenceCode)
    )
    return record
end

function DarkPassengerWitness.MarkReported(
    identityHigh,
    identityLow,
    reportTime
)
    local record = FindRecord(identityHigh, identityLow)
    if record == nil then return false end
    if record.state == DarkPassengerWitness.STATE_UNREPORTED then
        record.state = DarkPassengerWitness.STATE_REPORTED
    elseif record.state ==
           DarkPassengerWitness.STATE_SILENCED_BEFORE_REPORT then
        record.state = DarkPassengerWitness.STATE_SILENCED_AFTER_REPORT
    end
    record.reportTime = math.max(
        record.reportTime or 0,
        NumberOr(reportTime, 0)
    )
    DarkPassengerWitness.noisyLocked = true
    DarkPassengerWitness.Persist(record)
    Log("reported record=" .. tostring(record.id))
    return true
end

function DarkPassengerWitness.MarkDead(
    identityHigh,
    identityLow,
    deathTime,
    deathX,
    deathY,
    deathZ,
    attributed
)
    local record = FindRecord(identityHigh, identityLow)
    if record == nil then return false end
    local nextState =
        DarkPassengerWitness.DEATH_TRANSITIONS[record.state]
    local changed = nextState ~= nil
    if changed then record.state = nextState end
    record.deathTime = math.max(
        record.deathTime or 0,
        NumberOr(deathTime, 0)
    )
    record.deathX = NumberOr(deathX, record.deathX or 0)
    record.deathY = NumberOr(deathY, record.deathY or 0)
    record.deathZ = NumberOr(deathZ, record.deathZ or 0)
    record.deathAttributed =
        record.deathAttributed == true or BoolValue(attributed)
    DarkPassengerWitness.Persist(record)
    Log(
        "dead record=" .. tostring(record.id) ..
        " state=" .. tostring(record.state) ..
        " attributed=" .. tostring(record.deathAttributed)
    )
    return true, changed, record
end

function DarkPassengerWitness.MarkLost(identityHigh, identityLow)
    local record = FindRecord(identityHigh, identityLow)
    if record == nil then return false end
    if record.state == DarkPassengerWitness.STATE_UNREPORTED then
        record.state = DarkPassengerWitness.STATE_LOST
        DarkPassengerWitness.Persist(record)
    end
    return true
end

function DarkPassengerWitness.LockNoisy(reason)
    if not DarkPassengerWitness.noisyLocked then
        DarkPassengerWitness.noisyLocked = true
        DarkPassengerWitness.Persist()
    end
    Log("noisy locked reason=" .. tostring(reason))
    return true
end

function DarkPassengerWitness.SetNotificationEmitted()
    DarkPassengerWitness.notificationEmitted = true
    return DarkPassengerWitness.Persist()
end

function DarkPassengerWitness.GetCaseOutcome(generation)
    local requestedGeneration =
        NumberOr(generation, DarkPassengerWitness.activeCaseGeneration)
    if requestedGeneration ==
           DarkPassengerWitness.activeCaseGeneration and
       DarkPassengerWitness.noisyLocked then
        return "noisy"
    end

    local witnessCount = 0
    local everyWitnessControlled = true
    for _, record in pairs(DarkPassengerWitness.records) do
        if record.caseGeneration == requestedGeneration then
            witnessCount = witnessCount + 1
            if record.state ~=
               DarkPassengerWitness.STATE_SILENCED_BEFORE_REPORT then
                everyWitnessControlled = false
            end
        end
    end
    if witnessCount == 0 then return "clean" end
    if everyWitnessControlled then return "controlled" end
    return "noisy"
end

function DarkPassengerWitness.Status()
    local generation = DarkPassengerWitness.activeCaseGeneration
    local active = {}
    for _, record in pairs(DarkPassengerWitness.records) do
        if record.caseGeneration == generation then
            table.insert(active, record)
        end
    end
    table.sort(active, function(left, right)
        return left.id < right.id
    end)
    Log(
        "status generation=" .. tostring(generation) ..
        " records=" .. tostring(#active) ..
        " noisy_locked=" .. tostring(DarkPassengerWitness.noisyLocked) ..
        " outcome=" ..
        tostring(DarkPassengerWitness.GetCaseOutcome(generation))
    )
    for _, record in ipairs(active) do
        Log(
            "record id=" .. tostring(record.id) ..
            " identity=" ..
            tostring(record.identityHigh) .. ":" ..
            tostring(record.identityLow) ..
            " state=" .. tostring(record.state) ..
            " evidence=" .. tostring(record.evidenceCode) ..
            " identified=" .. tostring(record.identified)
        )
    end
    return {
        generation = generation,
        records = active,
        noisyLocked = DarkPassengerWitness.noisyLocked,
        notificationEmitted =
            DarkPassengerWitness.notificationEmitted,
        outcome =
            DarkPassengerWitness.GetCaseOutcome(generation),
    }
end

local function SplitArgs(argsLine)
    local parts = {}
    for token in tostring(argsLine or ""):gmatch("%S+") do
        table.insert(parts, token)
    end
    return parts
end

function DarkPassengerWitness.DebugConfirm(argsLine)
    local args = SplitArgs(argsLine)
    return DarkPassengerWitness.Confirm(
        args[1],
        args[2],
        args[3],
        args[4],
        args[5]
    ) ~= nil
end

function DarkPassengerWitness.DebugReport(argsLine)
    local args = SplitArgs(argsLine)
    return DarkPassengerWitness.MarkReported(
        args[1],
        args[2],
        args[3]
    )
end

function DarkPassengerWitness.DebugDead(argsLine)
    local args = SplitArgs(argsLine)
    return DarkPassengerWitness.MarkDead(
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
        args[6],
        args[7]
    )
end

function DarkPassengerWitness.DebugLost(argsLine)
    local args = SplitArgs(argsLine)
    return DarkPassengerWitness.MarkLost(args[1], args[2])
end
