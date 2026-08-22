# CaseKit Native Quest Items Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Дать StoryPack явный выбор `quest`/`loot` для каждого физического предмета и сделать постоянное невесомое трофей-перо.

**Architecture:** StoryPack — SSOT семантики предмета; materializer переносит контракт в CaseVariant; KCD2 backend регистрирует item row и выбирает Lua либо XML placement. Lua отвечает за динамический выбор, XML — за нативное создание quest item.

**Tech Stack:** PowerShell 7, JSON StoryPack, KCD2 XML quest graph/item tables, Lua runtime.

---

1. Добавить падающие authoring/materializer/compiler/runtime тесты.
2. Ввести обязательный `action.item.classification` для физических evidence modules.
3. Перенести item contract в compiled evidence и native runtime catalog.
4. Генерировать `IsQuestItem=true` и XML placement для `quest`; сохранить Lua path для `loot`.
5. Сделать `bird-feather`: `quest`, `permanent`, `Weight=0`.
6. Перевести две текущие документы-улики на `quest`/`case`.
7. Прогнать targeted, full suite, build и проверить собранный pak.
8. Обновить README и существующие Wiki-страницы; подготовить live-canary.

## Реализованный итог

- обязательные `classification` и `retention` проходят весь authoring pipeline;
- `quest` создаётся XML-графом, `loot` остаётся на Lua inventory API;
- один transient signal обслуживает один уникальный item class;
- два документа и общее невесомое трофей-перо дают три production-сигнала;
- защитный каталог погребения автоматически включает скомпилированные quest items;
- structural canary генерирует signal IDs выше 255; live-canary ещё требуется.

Нерешённые вопросы: нет.
