DarkPassengerCaseCatalog = DarkPassengerCaseCatalog or {}
DarkPassengerCaseCatalogOrder = DarkPassengerCaseCatalogOrder or {}

DarkPassengerCaseCatalog.convenient_accident = {
    id = "convenient_accident",
    weight = 1,
    constraints = {
        region = "kutnohorsko",
        settlement = "pritoky",
    },
    crime_profile = {
        innocent_victim = "vojtech",
        method = "murder_disguised_as_fall",
        cover_story = "drunken_accident",
    },
    rumors = {
        {
            id = "pritoky_innkeeper_strong_suspicion",
            purpose = "strong_suspicion",
            source_stance = "afraid",
            weight = 1,
            confidence = 20,
            next_lead = "vojtech_belongings",
            prompt_key = "dp_evidence_ask_unease",
            notification = "Корчмарь рассказал о смерти батрака Войтеха, которую слишком поспешно сочли несчастным случаем.",
        },
    },
    evidence_steps = {
        {
            id = "vojtech_belongings",
            kind = "document",
            confidence = 30,
            next_lead = "tavern_witness",
        },
        {
            id = "tavern_witness",
            kind = "dialogue",
            confidence = 20,
            next_lead = "reveal_target",
        },
    },
}

local found = false
for _, caseId in ipairs(DarkPassengerCaseCatalogOrder) do
    if caseId == "convenient_accident" then
        found = true
        break
    end
end
if not found then
    table.insert(DarkPassengerCaseCatalogOrder, "convenient_accident")
end

