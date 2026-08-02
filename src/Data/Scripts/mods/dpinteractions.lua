DarkPassengerInteractions = DarkPassengerInteractions or {}

DarkPassengerInteractions.providers =
    DarkPassengerInteractions.providers or {}
DarkPassengerInteractions._providerOrder =
    DarkPassengerInteractions._providerOrder or {}
DarkPassengerInteractions._classHooks =
    DarkPassengerInteractions._classHooks or {}

local actionClassNames = { "NPC", "NPC_Female", "NPC_NAI" }

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][Interactions] " .. tostring(message)
        )
    end
end

local function ContainsProvider(name)
    for _, registeredName in ipairs(
        DarkPassengerInteractions._providerOrder
    ) do
        if registeredName == name then return true end
    end
    return false
end

function DarkPassengerInteractions.RegisterProvider(name, provider)
    if type(name) ~= "string" or name == "" or
       type(provider) ~= "function" then
        return false
    end
    if not ContainsProvider(name) then
        table.insert(DarkPassengerInteractions._providerOrder, name)
    end
    DarkPassengerInteractions.providers[name] = provider
    return true
end

function DarkPassengerInteractions.UnregisterProvider(name)
    if DarkPassengerInteractions.providers[name] == nil then return false end
    DarkPassengerInteractions.providers[name] = nil
    for index, registeredName in ipairs(
        DarkPassengerInteractions._providerOrder
    ) do
        if registeredName == name then
            table.remove(DarkPassengerInteractions._providerOrder, index)
            break
        end
    end
    return true
end

function DarkPassengerInteractions.Dispatch(
    entity,
    user,
    firstFast,
    output
)
    if type(output) ~= "table" then output = {} end
    for _, name in ipairs(DarkPassengerInteractions._providerOrder) do
        local provider = DarkPassengerInteractions.providers[name]
        if type(provider) == "function" then
            local ok, errorMessage = pcall(
                provider,
                entity,
                user,
                firstFast,
                output
            )
            if not ok then
                Log(
                    "provider failed name=" .. tostring(name) ..
                    " error=" .. tostring(errorMessage)
                )
            end
        end
    end
    return output
end

local function RestoreLegacyBurialHooks()
    if DarkPassengerBurial == nil or
       type(DarkPassengerBurial._actionClassHooks) ~= "table" then
        return
    end
    for className, hook in pairs(
        DarkPassengerBurial._actionClassHooks
    ) do
        local classTable = _G ~= nil and _G[className] or nil
        if type(classTable) == "table" and
           type(hook) == "table" and
           type(hook.wrapper) == "function" and
           type(hook.original) == "function" and
           classTable.GetActions == hook.wrapper then
            classTable.GetActions = hook.original
            Log("restored legacy burial hook class=" .. className)
        end
    end
    DarkPassengerBurial._actionClassHooks = nil
end

local function InstallClassActionHook(className, classTable)
    if type(classTable) ~= "table" or
       type(classTable.GetActions) ~= "function" then
        return false
    end

    local hook = DarkPassengerInteractions._classHooks[className]
    if type(hook) ~= "table" then
        hook = {}
        DarkPassengerInteractions._classHooks[className] = hook
    end
    if type(hook.wrapper) == "function" and
       classTable.GetActions == hook.wrapper then
        return true
    end

    hook.original = classTable.GetActions
    local wrapper = function(self, user, firstFast)
        local output = hook.original(self, user, firstFast)
        return DarkPassengerInteractions.Dispatch(
            self,
            user,
            firstFast,
            output
        )
    end
    hook.wrapper = wrapper
    classTable.GetActions = wrapper
    Log(className .. ".GetActions hook installed")
    return true
end

function DarkPassengerInteractions.InstallActionHook()
    RestoreLegacyBurialHooks()
    local installed = 0
    for _, className in ipairs(actionClassNames) do
        local classTable = _G ~= nil and _G[className] or nil
        if InstallClassActionHook(className, classTable) then
            installed = installed + 1
        else
            Log(className .. ".GetActions hook unavailable")
        end
    end
    return installed > 0
end

function DarkPassengerInteractions.RunSelfTest()
    local name = "__dp_interactions_selftest"
    local calls = 0
    DarkPassengerInteractions.RegisterProvider(name, function()
        calls = calls + 100
    end)
    DarkPassengerInteractions.RegisterProvider(name, function()
        calls = calls + 1
    end)
    DarkPassengerInteractions.Dispatch(nil, nil, false, {})
    DarkPassengerInteractions.UnregisterProvider(name)
    local passed = calls == 1
    Log("selftest=" .. tostring(passed) .. " calls=" .. tostring(calls))
    return passed
end

DarkPassengerInteractions.InstallActionHook()
Log("module loaded")
