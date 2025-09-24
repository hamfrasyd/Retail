
WeakAurasSaved = {
["dynamicIconCache"] = {
},
["editor_tab_spaces"] = 4,
["displays"] = {
["Warrior: Racial (Orc)"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["names"] = {
},
["type"] = "spell",
["unit"] = "player",
["unevent"] = "auto",
["subeventPrefix"] = "SPELL",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Blood Fury",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["subeventSuffix"] = "_CAST_START",
["duration"] = "1",
["use_track"] = true,
["spellName"] = 20572,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 18,
["multi"] = {
[14] = true,
[18] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_class"] = true,
["race"] = {
["single"] = "Orc",
["multi"] = {
["Troll"] = true,
["Orc"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_class_and_spec"] = false,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_petbattle"] = false,
["use_race"] = true,
["size"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["desaturate"] = false,
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["keepAspectRatio"] = false,
["useTooltip"] = false,
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["config"] = {
},
["icon"] = true,
["width"] = 34,
["anchorFrameParent"] = false,
["authorOptions"] = {
},
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Racial (Orc)",
["color"] = {
1,
1,
1,
1,
},
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["alpha"] = 1,
["uid"] = "ucPgxF7amgH",
["inverse"] = true,
["parent"] = "Warrior » Primary Bar",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Storm Bolt"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 107570,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Storm Bolt",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["type"] = "aura2",
["auranames"] = {
"446035",
},
["debuffType"] = "HELPFUL",
["useName"] = true,
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowScale"] = 1,
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["glow"] = false,
["glowXOffset"] = 0,
["glowDuration"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_class"] = true,
["use_spellknown"] = true,
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_class_and_spec"] = false,
["use_exact_spellknown"] = true,
["spellknown"] = 107570,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "eKYFPcy4VVt",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Storm Bolt",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078432083129883,
0.2352941334247589,
0.2313725650310516,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = -2,
["variable"] = "AND",
["checks"] = {
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 0,
},
{
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Shield Wall"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"871",
},
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
},
["useExactSpellId"] = false,
["names"] = {
"Remorseless Winter",
},
["event"] = "Health",
["subeventSuffix"] = "_CAST_START",
["use_specific_unit"] = false,
["ownOnly"] = true,
["spellIds"] = {
},
["useName"] = true,
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["unit"] = "player",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = true,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[581] = true,
},
},
["talent"] = {
["multi"] = {
[112864] = true,
[112176] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["covenant"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
},
},
["use_petbattle"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["difficulty"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["desaturate"] = false,
["source"] = "import",
["selfPoint"] = "CENTER",
["cooldown"] = true,
["conditions"] = {
},
["authorOptions"] = {
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["parent"] = "Prot Warrior Defensives",
["uid"] = "6PonofrvuxV",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 4, 0)\nend",
["width"] = 34,
["anchorFrameParent"] = false,
["alpha"] = 1,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Shield Wall",
["keepAspectRatio"] = false,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["displayIcon"] = 1129420,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Potion"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["auranames"] = {
"431932",
"431925",
},
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
"3710924",
},
["unit"] = "player",
["duration"] = "1",
["event"] = "Health",
["unevent"] = "timed",
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
["spellIds"] = {
},
["type"] = "aura2",
["useExactSpellId"] = false,
["combineMatches"] = "showLowest",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\n    return t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[72] = true,
[577] = true,
[253] = true,
[103] = true,
[254] = true,
[259] = true,
[268] = true,
[250] = true,
[581] = true,
[260] = true,
[71] = true,
[73] = true,
[104] = true,
[261] = true,
[269] = true,
[251] = true,
[66] = true,
},
},
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["itemequiped"] = {
158712,
},
["faction"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["desaturate"] = false,
["parent"] = "Prot Warrior Buffs",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["progressSource"] = {
-1,
"",
},
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Potion",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["width"] = 28,
["zoom"] = 0.3,
["uid"] = "uBAKze0GfKL",
["inverse"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "fade",
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "slideright",
},
},
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior Spell Alerts"] = {
["controlledChildren"] = {
"Prot Warrior: Revenge! Left",
"Prot Warrior: Revenge! Right",
},
["borderBackdrop"] = "Blizzard Tooltip",
["xOffset"] = 0,
["preferToUpdate"] = false,
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["names"] = {
},
},
["untrigger"] = {
},
},
},
["internalVersion"] = 86,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["subRegions"] = {
},
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["backdropColor"] = {
1,
1,
1,
0.5,
},
["source"] = "import",
["scale"] = 1,
["border"] = false,
["borderEdge"] = "Square Full White",
["regionType"] = "group",
["borderSize"] = 2,
["uid"] = "Yw2icS)H04v",
["borderOffset"] = 4,
["selfPoint"] = "CENTER",
["tocversion"] = 110200,
["id"] = "Prot Warrior Spell Alerts",
["alpha"] = 1,
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["borderInset"] = 1,
["groupIcon"] = "626008",
["config"] = {
},
["conditions"] = {
},
["information"] = {
},
["parent"] = "Warrior » Spell Alerts",
},
["Fury Warrior: Signet of the Priory"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["spellId"] = {
"49206",
},
["auranames"] = {
"443531",
},
["matchesShowOn"] = "showOnActive",
["use_sourceNpcId"] = false,
["use_totemType"] = true,
["spellName"] = {
"",
},
["use_debuffClass"] = false,
["subeventSuffix"] = "_SUMMON",
["event"] = "Combat Log",
["use_spellId"] = true,
["use_sourceUnit"] = true,
["combineMatches"] = "showLowest",
["use_track"] = true,
["useGroup_count"] = false,
["use_absorbMode"] = true,
["genericShowOn"] = "showOnCooldown",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["type"] = "aura2",
["custom_hide"] = "timed",
["unevent"] = "timed",
["use_sourceName"] = false,
["duration"] = "25",
["debuffType"] = "HELPFUL",
["totemType"] = 1,
["realSpellName"] = "",
["use_spellName"] = false,
["spellIds"] = {
},
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["sourceUnit"] = "player",
["use_unit"] = true,
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["class"] = {
["single"] = "DEATHKNIGHT",
["multi"] = {
["DEATHKNIGHT"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[252] = true,
},
},
["talent"] = {
["multi"] = {
[96311] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["itemequiped"] = {
219308,
},
["faction"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["conditions"] = {
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["keepAspectRatio"] = false,
["uid"] = "9zPwN2VmBV6",
["desaturate"] = false,
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = false,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Signet of the Priory",
["zoom"] = 0.3,
["frameStrata"] = 3,
["width"] = 28,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = false,
["parent"] = "Fury Warrior Buffs",
["displayIcon"] = 458967,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Wrecked Debuff"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["custom_hide"] = "timed",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["unit"] = "target",
["event"] = "Health",
["ownOnly"] = true,
["matchesShowOn"] = "showOnActive",
["useName"] = true,
["spellIds"] = {
},
["auranames"] = {
"447513",
},
["subeventPrefix"] = "SPELL",
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HARMFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_format"] = "timed",
["anchorXOffset"] = 0,
["text_text_format_p_time_precision"] = 1,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_format"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["anchorYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112117] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["role"] = {
["multi"] = {
},
},
["use_herotalent"] = false,
["use_class_and_spec"] = true,
["faction"] = {
["multi"] = {
},
},
["herotalent"] = {
["multi"] = {
[117415] = true,
},
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["zoneIds"] = "",
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Arms Warrior Buffs",
["selfPoint"] = "CENTER",
["xOffset"] = 0,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["progressSource"] = {
-1,
"",
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Wrecked Debuff",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "fcQMlKAtean",
["inverse"] = false,
["stickyDuration"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Ravager w/ Unhinged"] = {
["sparkWidth"] = 4,
["iconSource"] = 0,
["xOffset"] = 0,
["adjustedMax"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["backgroundColor"] = {
0,
0,
0,
0,
},
["icon_color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["barColor"] = {
1,
1,
1,
1,
},
["desaturate"] = false,
["sparkOffsetY"] = 0,
["gradientOrientation"] = "HORIZONTAL",
["load"] = {
["use_never"] = false,
["talent"] = {
["multi"] = {
},
},
["not_spellknown"] = 227847,
["use_class_and_spec"] = true,
["spec"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
},
["use_spellknown"] = true,
["use_exact_not_spellknown"] = true,
["class"] = {
["multi"] = {
},
},
["use_not_spellknown"] = true,
["use_exact_spellknown"] = true,
["spellknown"] = 386628,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["texture"] = "Blizzard Raid Bar",
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["spark"] = true,
["tocversion"] = 110200,
["alpha"] = 1,
["sparkColor"] = {
1,
1,
1,
1,
},
["displayIcon"] = 970854,
["sparkOffsetX"] = -1,
["parent"] = "Fury Warrior Buffs",
["adjustedMin"] = "",
["cooldownSwipe"] = true,
["sparkRotationMode"] = "AUTO",
["cooldownEdge"] = false,
["triggers"] = {
{
["trigger"] = {
["type"] = "custom",
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["unit"] = "player",
["names"] = {
},
["custom"] = "function(s,e,tick,count,spellID)\n    if e == \"UNIT_SPELLCAST_SUCCEEDED\" and spellID == 228920 then\n        local haste = GetHaste()/100\n        local dur = 12 / (1 + haste)\n        local tick = dur / 3\n        for i = 1,2 do\n            C_Timer.After(i*tick, function() WeakAuras.ScanEvents(\"UNHINGED\", tick, 3-i) end)\n        end\n        \n        s[\"\"] = {\n            show = true,\n            changed = true,\n            progressType = \"timed\",\n            duration = tick,\n            expirationTime = tick + GetTime(),\n            autoHide = true,\n            stacks = 3\n        }\n        return true\n    elseif e == \"UNHINGED\" and tick then\n        s[\"\"] = {\n            show = true,\n            changed = true,\n            progressType = \"timed\",\n            duration = tick,\n            expirationTime = tick + GetTime(),\n            autoHide = true,\n            stacks = count\n        }\n        return true\n    end\nend\n\n\n\n",
["spellIds"] = {
},
["custom_type"] = "stateupdate",
["check"] = "event",
["subeventPrefix"] = "SPELL",
["events"] = "UNIT_SPELLCAST_SUCCEEDED:player UNHINGED",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t) return t[1] end",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["sparkMirror"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_offset"] = 1,
["anchor_area"] = "bar",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_n_format"] = "none",
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_shadowXOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_format"] = "timed",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_legacy_floor"] = false,
},
},
["height"] = 28,
["textureSource"] = "LSM",
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["source"] = "import",
["preferToUpdate"] = false,
["cooldown"] = true,
["icon_side"] = "RIGHT",
["authorOptions"] = {
},
["uid"] = "8MWuvUnbXZw",
["sparkHeight"] = 12,
["color"] = {
1,
1,
1,
1,
},
["icon"] = false,
["zoom"] = 0.3,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["custom"] = "\n\n",
["do_custom"] = false,
},
},
["anchorFrameType"] = "SELECTFRAME",
["id"] = "Fury Warrior: Ravager w/ Unhinged",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["width"] = 28,
["sparkHidden"] = "NEVER",
["information"] = {
},
["inverse"] = false,
["cooldownTextDisabled"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["barColor2"] = {
1,
1,
0,
1,
},
["config"] = {
},
},
["Fury Warrior: Burst of Power"] = {
["iconSource"] = -1,
["xOffset"] = -100.1,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -114,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["duration"] = "1",
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"437121",
},
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -5,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 16,
["anchorXOffset"] = 0,
["text_text_format_p_time_precision"] = 1,
},
},
["height"] = 32,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112275] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["size"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["faction"] = {
["multi"] = {
},
},
["herotalent"] = {
["multi"] = {
[117404] = true,
},
},
["use_herotalent"] = false,
},
["useAdjustededMax"] = false,
["width"] = 32,
["source"] = "import",
["keepAspectRatio"] = false,
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["selfPoint"] = "CENTER",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Burst of Power",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "7YDEM1xO1qm",
["inverse"] = false,
["parent"] = "Warrior » Emphasized Buffs",
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Deep Wounds"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -39,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["rem"] = "5",
["auranames"] = {
"262115",
},
["use_genericShowOn"] = true,
["genericShowOn"] = "showOnCooldown",
["subeventPrefix"] = "SPELL",
["names"] = {
},
["debuffType"] = "HARMFUL",
["type"] = "aura2",
["useName"] = true,
["matchesShowOn"] = "showOnActive",
["use_targetRequired"] = true,
["subeventSuffix"] = "_CAST_START",
["ownOnly"] = true,
["event"] = "Spell Activation Overlay",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["spellName"] = 5308,
["remOperator"] = "<",
["unit"] = "target",
["use_track"] = true,
["useRem"] = true,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["rem"] = "5",
["auranames"] = {
"262115",
},
["use_genericShowOn"] = true,
["genericShowOn"] = "showOnCooldown",
["unit"] = "target",
["subeventPrefix"] = "SPELL",
["debuffType"] = "HARMFUL",
["spellName"] = 5308,
["showClones"] = false,
["useName"] = true,
["use_targetRequired"] = true,
["subeventSuffix"] = "_CAST_START",
["names"] = {
},
["type"] = "aura2",
["event"] = "Spell Activation Overlay",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["ownOnly"] = true,
["remOperator"] = "<",
["matchesShowOn"] = "showOnMissing",
["use_track"] = true,
["useRem"] = true,
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1] and (t[2] or t[3] or (t[4] and t[5]))\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["glowXOffset"] = 0,
["glowType"] = "Pixel",
["glowThickness"] = 2,
["glowYOffset"] = 0,
["glowColor"] = {
0.73725490196078,
0.12549019607843,
0.035294117647059,
1,
},
["glowLength"] = 10,
["glow"] = false,
["glowDuration"] = 1,
["useGlowColor"] = true,
["glowScale"] = 1,
["glowLines"] = 6,
["glowBorder"] = true,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["use_class"] = true,
["use_spec"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
[202316] = true,
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
},
},
["talent"] = {
["single"] = 7,
["multi"] = {
[7384] = true,
[12294] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
[2] = true,
[3] = true,
},
},
["talent2_extraOption"] = 2,
["covenant"] = {
["single"] = 2,
["multi"] = {
["1"] = true,
["4"] = true,
["3"] = true,
["0"] = true,
},
},
["use_spellknown"] = false,
["use_class_and_spec"] = true,
["talent_extraOption"] = 0,
["use_combat"] = true,
["spellknown"] = 335232,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["preferToUpdate"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["conditions"] = {
{
["check"] = {
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "<=",
["value"] = "4.5",
["variable"] = "expirationTime",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["progressSource"] = {
-1,
"",
},
["xOffset"] = -0.2501220703125,
["uid"] = "EIn4wXgAc4)",
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Deep Wounds",
["alpha"] = 1,
["frameStrata"] = 3,
["width"] = 34,
["parent"] = "Warrior » Emphasized Buffs",
["config"] = {
},
["inverse"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "alphaPulse",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["displayIcon"] = "135358",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["stickyDuration"] = false,
},
["Arms Warrior: Ravager w/ Unhinged"] = {
["sparkWidth"] = 4,
["iconSource"] = 0,
["xOffset"] = 0,
["adjustedMax"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["backgroundColor"] = {
0,
0,
0,
0,
},
["icon_color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["barColor"] = {
1,
1,
1,
1,
},
["desaturate"] = false,
["sparkOffsetY"] = 0,
["gradientOrientation"] = "HORIZONTAL",
["load"] = {
["use_never"] = false,
["talent"] = {
["multi"] = {
},
},
["not_spellknown"] = 227847,
["use_class_and_spec"] = true,
["spec"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
},
["use_spellknown"] = true,
["use_exact_not_spellknown"] = true,
["class"] = {
["multi"] = {
},
},
["use_not_spellknown"] = true,
["use_exact_spellknown"] = true,
["spellknown"] = 386628,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["texture"] = "Blizzard Raid Bar",
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["spark"] = true,
["tocversion"] = 110200,
["alpha"] = 1,
["sparkColor"] = {
1,
1,
1,
1,
},
["displayIcon"] = 970854,
["sparkOffsetX"] = -1,
["parent"] = "Arms Warrior Buffs",
["adjustedMin"] = "",
["cooldownSwipe"] = true,
["sparkRotationMode"] = "AUTO",
["cooldownEdge"] = false,
["triggers"] = {
{
["trigger"] = {
["type"] = "custom",
["custom_type"] = "stateupdate",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["unit"] = "player",
["custom"] = "function(s,e,tick,count,spellID)\n    if e == \"UNIT_SPELLCAST_SUCCEEDED\" and spellID == 228920 then\n        local haste = GetHaste()/100\n        local dur = 12 / (1 + haste)\n        local tick = dur / 3\n        for i = 1,2 do\n            C_Timer.After(i*tick, function() WeakAuras.ScanEvents(\"UNHINGED\", tick, 3-i) end)\n        end\n        \n        s[\"\"] = {\n            show = true,\n            changed = true,\n            progressType = \"timed\",\n            duration = tick,\n            expirationTime = tick + GetTime(),\n            autoHide = true,\n            stacks = 3\n        }\n        return true\n    elseif e == \"UNHINGED\" and tick then\n        s[\"\"] = {\n            show = true,\n            changed = true,\n            progressType = \"timed\",\n            duration = tick,\n            expirationTime = tick + GetTime(),\n            autoHide = true,\n            stacks = count\n        }\n        return true\n    end\nend\n\n\n\n",
["events"] = "UNIT_SPELLCAST_SUCCEEDED:player UNHINGED",
["spellIds"] = {
},
["names"] = {
},
["check"] = "event",
["subeventPrefix"] = "SPELL",
["subeventSuffix"] = "_CAST_START",
["customVariables"] = "\n\n",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t) return t[1] end",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["sparkMirror"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_offset"] = 1,
["anchor_area"] = "bar",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_n_format"] = "none",
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_shadowXOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_format"] = "timed",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_legacy_floor"] = false,
},
},
["height"] = 28,
["textureSource"] = "LSM",
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["source"] = "import",
["preferToUpdate"] = false,
["cooldown"] = true,
["icon_side"] = "RIGHT",
["authorOptions"] = {
},
["uid"] = "Z2OdcpxpM(P",
["sparkHeight"] = 12,
["color"] = {
1,
1,
1,
1,
},
["icon"] = false,
["zoom"] = 0.3,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["custom"] = "\n\n",
["do_custom"] = false,
},
},
["anchorFrameType"] = "SELECTFRAME",
["id"] = "Arms Warrior: Ravager w/ Unhinged",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["width"] = 28,
["sparkHidden"] = "NEVER",
["information"] = {
},
["inverse"] = true,
["cooldownTextDisabled"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["barColor2"] = {
1,
1,
0,
1,
},
["config"] = {
},
},
["Fury Warrior: Onslaught"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 315720,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Onslaught",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["multi"] = {
[382310] = true,
[112295] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 72,
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 315720,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "5rP)H8tlYAL",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Onslaught",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellUsable",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Shield Slam"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 23922,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Shield Slam",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["type"] = "aura2",
["auranames"] = {
"437121",
},
["unit"] = "player",
["useName"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_format"] = 0,
["text_text"] = "%2.s",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_format"] = "timed",
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorXOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_anchorYOffset"] = -5,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["text_text_format_p_time_dynamic_threshold"] = 60,
["anchorYOffset"] = 0,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[394062] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "g8snJC6aQYB",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Shield Slam",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Sudden Death"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -114,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"280776",
},
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowType"] = "Proc",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glow"] = false,
["glowXOffset"] = 0,
["glowThickness"] = 1,
["glowScale"] = 1,
["glowDuration"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_format"] = "timed",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_text_format_p_time_legacy_floor"] = false,
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["anchorXOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
},
},
["height"] = 32,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[2] = true,
[112300] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Warrior » Emphasized Buffs",
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 100.1,
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "yUH91(gLnYv",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Sudden Death",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 32,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "stacks",
["value"] = "2",
["op"] = "==",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Thunderous Roar"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 384318,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Thunderous Roar",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["multi"] = {
[68] = true,
},
},
["use_class_and_spec"] = false,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_class"] = true,
["use_spellknown"] = true,
["use_petbattle"] = false,
["use_spec"] = true,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
true,
},
},
["spellknown"] = 384318,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "TE2ArT11rnq",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Thunderous Roar",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Demolish"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 436358,
["type"] = "spell",
["names"] = {
},
["unevent"] = "auto",
["use_genericShowOn"] = true,
["subeventSuffix"] = "_CAST_START",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Sweeping Strikes",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["duration"] = "1",
["unit"] = "player",
["use_track"] = true,
["use_unit"] = true,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"440989",
},
["unit"] = "player",
["type"] = "aura2",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%2.s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorXOffset"] = 0,
["text_text_format_p_format"] = "timed",
["text_text_format_p_time_precision"] = 1,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_shadowXOffset"] = 0,
["text_anchorYOffset"] = -5,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["text_text_format_p_time_dynamic_threshold"] = 60,
["anchorYOffset"] = 0,
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[384361] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_herotalent"] = false,
["use_class_and_spec"] = true,
["herotalent"] = {
["multi"] = {
[117415] = true,
},
},
["class_and_spec"] = {
["single"] = 73,
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["desaturate"] = false,
["source"] = "import",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["progressSource"] = {
-1,
"",
},
["useTooltip"] = false,
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["authorOptions"] = {
},
["uid"] = "5jp5R(9)U5D",
["parent"] = "Warrior » Primary Bar",
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["xOffset"] = 0,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Demolish",
["frameStrata"] = 3,
["alpha"] = 1,
["width"] = 34,
["useAdjustededMin"] = false,
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078432083129883,
0.2352941334247589,
0.2313725650310516,
1,
},
["property"] = "color",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Unyielding Netherprism"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["showClones"] = true,
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
"1239675",
},
["useExactSpellId"] = false,
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["ownOnly"] = true,
["unit"] = "player",
["auranames"] = {
"1233556",
},
["spellIds"] = {
},
["useName"] = true,
["subeventSuffix"] = "_CAST_START",
["combineMatches"] = "showLowest",
["names"] = {
"Aspect of the Eagle",
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["itemequiped"] = {
242396,
},
["faction"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Arms Warrior Buffs",
["authorOptions"] = {
},
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Unyielding Netherprism",
["alpha"] = 1,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "vIyenLdJuwz",
["inverse"] = false,
["keepAspectRatio"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Colossus Smash Debuff"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -114,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"167105",
},
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HARMFUL",
["custom_hide"] = "timed",
["event"] = "Health",
["ownOnly"] = true,
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["unevent"] = "timed",
["combineMatches"] = "showLowest",
["unit"] = "target",
["duration"] = "1",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 32,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 71,
},
["talent"] = {
["multi"] = {
[112144] = true,
},
},
["talent2"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["role"] = {
["multi"] = {
},
},
["use_talent"] = false,
["difficulty"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = -100.1,
["config"] = {
},
["preferToUpdate"] = false,
["authorOptions"] = {
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["progressSource"] = {
-1,
"",
},
["width"] = 32,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Colossus Smash Debuff",
["alpha"] = 1,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "llel7HmKIfE",
["inverse"] = false,
["stickyDuration"] = false,
["conditions"] = {
},
["cooldown"] = true,
["parent"] = "Warrior » Emphasized Buffs",
},
["Warrior: Kick"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 6552,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Pummel",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "oIrg()CSbWW",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Kick",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Shield Block"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 2565,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Shield Block",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -5,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[394062] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "Aws1GZa8P8Z",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Shield Block",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["op"] = ">",
["variable"] = "AND",
["checks"] = {
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
{
["trigger"] = 1,
["op"] = ">",
["value"] = "0",
["variable"] = "charges",
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "cooldownEdge",
},
{
["value"] = false,
["property"] = "cooldownSwipe",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellUsable",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["value"] = "0",
["variable"] = "charges",
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Trinket 2"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["names"] = {
},
["use_showgcd"] = false,
["itemSlot"] = 14,
["subeventPrefix"] = "SPELL",
["buffShowOn"] = "showOnActive",
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["type"] = "item",
["use_genericShowOn"] = true,
["subeventSuffix"] = "_CAST_START",
["unevent"] = "auto",
["realSpellName"] = 113860,
["event"] = "Cooldown Progress (Equipment Slot)",
["use_exact_spellName"] = true,
["use_itemSlot"] = true,
["use_spellName"] = true,
["spellIds"] = {
},
["use_testForCooldown"] = true,
["use_absorbMode"] = true,
["use_unit"] = true,
["use_track"] = true,
["spellName"] = 113860,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
["itemSlot"] = 14,
},
},
{
["trigger"] = {
["type"] = "custom",
["events"] = "PLAYER_EQUIPMENT_CHANGED",
["custom_type"] = "stateupdate",
["check"] = "event",
["debuffType"] = "HELPFUL",
["custom"] = "function(...) return aura_env:TSU(...) end\n    \n    ",
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["PRIEST"] = true,
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["custom"] = "function aura_env:Init()\n    self.slot = 14\n    self.filteredItemIDs = {\n        [186421] = true,\n        [185304] = true,\n        [185282] = true,\n        [190958] = true,\n        [193757] = true, --Ruby Whelp Shell\n        [194307] = true, --Broodkeeper Promise\n        [193718] = true, --Emerald Coach's Whistle\n        [200563] = true, --Primal Ritual Shell\n        [203729] = true, --Ominous Chromatic Essence\n        [202612] = true, --Screaming Black Dragonscale \n        [178742] = true, --Bottled FLayedwing Toxin\n        [230193] = true, --Mister Lock-N-Stalk\n        [242396] = true, --Unyielding Netherprism  \n        \n    }\nend\n\nfunction aura_env:TSU(allStates, event, arg1)\n    if event == \"PLAYER_EQUIPMENT_CHANGED\" and (not arg1 or arg1 == self.slot) then\n        self.show = not self.filteredItemIDs[GetInventoryItemID(\"player\", self.slot)]\n    end\n    \n    self.changed = true\n    allStates[\"\"] = self\n    return true\nend\n\naura_env:Init()",
["do_custom"] = true,
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "(CGBhAZPwJB",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Trinket 2",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Potion"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["unevent"] = "timed",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["matchesShowOn"] = "showOnActive",
["event"] = "Health",
["useExactSpellId"] = false,
["auranames"] = {
"431932",
"431925",
},
["buffShowOn"] = "showOnActive",
["spellIds"] = {
},
["useName"] = true,
["auraspellids"] = {
"3710924",
},
["combineMatches"] = "showLowest",
["unit"] = "player",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\n    return t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "fade",
["easeStrength"] = 3,
},
["main"] = {
["type"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "slideright",
["easeStrength"] = 3,
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = false,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[72] = true,
[577] = true,
[66] = true,
[103] = true,
[254] = true,
[259] = true,
[71] = true,
[250] = true,
[581] = true,
[260] = true,
[268] = true,
[73] = true,
[104] = true,
[261] = true,
[269] = true,
[251] = true,
[253] = true,
},
},
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["zoneIds"] = "",
["itemequiped"] = {
158712,
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Fury Warrior Buffs",
["selfPoint"] = "CENTER",
["xOffset"] = 0,
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["progressSource"] = {
-1,
"",
},
["icon"] = true,
["uid"] = "GoXW7SCF6if",
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Potion",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Sudden Death"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -114,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"52437",
},
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_format"] = "timed",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_text_format_p_time_legacy_floor"] = false,
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["anchorXOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
},
{
["glowFrequency"] = 0.25,
["glow"] = false,
["useGlowColor"] = false,
["glowScale"] = 1,
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["type"] = "subglow",
["glowXOffset"] = 0,
["glowDuration"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
},
["height"] = 32,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[2] = true,
[112126] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Warrior » Emphasized Buffs",
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 100.1,
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "B0c2gf6UGKB",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Sudden Death",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 32,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "stacks",
["op"] = "==",
["value"] = "2",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.4.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Outburst"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"386478",
},
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["unit"] = "player",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.2,
["type"] = "subglow",
["glowXOffset"] = 0,
["glowType"] = "Pixel",
["glowThickness"] = 2,
["glowYOffset"] = 0,
["glowColor"] = {
0.0078431377187371,
0.77647066116333,
0,
1,
},
["glowLength"] = 6,
["glow"] = false,
["glowDuration"] = 1,
["useGlowColor"] = true,
["glowScale"] = 1,
["glowLines"] = 7,
["glowBorder"] = true,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 16,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -5,
},
},
["height"] = 34,
["load"] = {
["size"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
},
["talent"] = {
["multi"] = {
[112116] = true,
},
},
["talent2"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
true,
[3] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_talent"] = false,
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["zoneIds"] = "",
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = 1,
["property"] = "iconSource",
},
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["parent"] = "Prot Warrior Defensives",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["uid"] = "xApKIXBNhRI",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Outburst",
["selfPoint"] = "CENTER",
["useCooldownModRate"] = true,
["width"] = 34,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = false,
["progressSource"] = {
-1,
"",
},
["displayIcon"] = 236308,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Brutal Finish"] = {
["iconSource"] = 0,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = -114,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"446918",
},
["duration"] = "1",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["custom_hide"] = "timed",
["event"] = "Health",
["unit"] = "player",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["matchesShowOn"] = "showOnActive",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "aura2",
["auranames"] = {
"393931",
},
["debuffType"] = "HELPFUL",
["useName"] = true,
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowType"] = "Proc",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glow"] = true,
["glowXOffset"] = 0,
["glowThickness"] = 1,
["glowScale"] = 1,
["glowDuration"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_precision"] = 1,
["text_text"] = "%2.s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_2.23_format"] = "none",
["text_text_format_p_time_mod_rate"] = true,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 1,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_format"] = 0,
["text_shadowYOffset"] = 0,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "CENTER",
["text_fontSize"] = 19,
["anchorXOffset"] = 0,
["text_text_format_p_time_legacy_floor"] = false,
},
},
["height"] = 32,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112275] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["use_herotalent"] = false,
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["herotalent"] = {
["multi"] = {
[117411] = true,
},
},
["use_class_and_spec"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["alpha"] = 1,
["useAdjustededMax"] = false,
["selfPoint"] = "CENTER",
["source"] = "import",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["conditions"] = {
},
["progressSource"] = {
-1,
"",
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = -100.1,
["uid"] = "Xqz1N7JN3Dv",
["adjustedMin"] = "",
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["cooldownTextDisabled"] = true,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Brutal Finish",
["stickyDuration"] = false,
["frameStrata"] = 3,
["width"] = 32,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = false,
["parent"] = "Warrior » Emphasized Buffs",
["displayIcon"] = 132352,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Thunder Clap"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["names"] = {
},
["type"] = "spell",
["unit"] = "player",
["unevent"] = "auto",
["subeventPrefix"] = "SPELL",
["use_absorbMode"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Thunder Clap",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["subeventSuffix"] = "_CAST_START",
["use_genericShowOn"] = true,
["use_track"] = true,
["spellName"] = 6343,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"435615",
},
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowType"] = "Proc",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glow"] = false,
["glowXOffset"] = 0,
["glowThickness"] = 1,
["glowScale"] = 1,
["glowDuration"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%2.s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_mod_rate"] = true,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = -5,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontType"] = "OUTLINE",
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["anchorXOffset"] = 0,
["text_text_format_p_time_legacy_floor"] = false,
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[394062] = true,
[112205] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["use_petbattle"] = false,
["use_never"] = false,
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 6343,
["size"] = {
["multi"] = {
},
},
},
["alpha"] = 1,
["useAdjustededMax"] = false,
["selfPoint"] = "CENTER",
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useTooltip"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["config"] = {
},
["parent"] = "Warrior » Primary Bar",
["width"] = 34,
["anchorFrameParent"] = false,
["desaturate"] = false,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Thunder Clap",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "U6w24XPxGeF",
["inverse"] = true,
["progressSource"] = {
-1,
"",
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "insufficientResources",
["value"] = 1,
},
["changes"] = {
{
["value"] = {
0.458823561668396,
0.4862745404243469,
0.7176470756530762,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 2,
["variable"] = "stacks",
["value"] = "2",
["op"] = "==",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Externals"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["customText"] = "function()\n    if aura_env.state then\n        local name = \"\"\n        if aura_env.state.unitCaster and not UnitIsUnit(aura_env.state.unitCaster, \"player\") then\n            name = WrapTextInColorCode( WA_Utf8Sub(aura_env.state.casterName, 8), select(4, GetClassColor(select(2, UnitClass(aura_env.state.unitCaster)))) )\n        end\n        return name\n    end\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
["sound"] = "Interface\\Addons\\AtrocityMedia\\Sounds\\Positive.ogg",
["do_sound"] = false,
},
["init"] = {
["do_custom"] = false,
["custom"] = "\n\n",
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["tooltipValueNumber"] = 1,
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["unitExists"] = false,
["use_tooltipValue"] = false,
["debuffType"] = "HELPFUL",
["showClones"] = true,
["useName"] = false,
["auraspellids"] = {
"102342",
"6940",
"199448",
"204018",
"228050",
"1022",
"116849",
"47788",
"33206",
"357170",
},
["fetchTooltip"] = true,
["event"] = "Health",
["useExactSpellId"] = true,
["subeventPrefix"] = "SPELL",
["auranames"] = {
},
["spellIds"] = {
},
["type"] = "aura2",
["names"] = {
},
["useNamePattern"] = false,
["subeventSuffix"] = "_CAST_START",
["useIgnoreName"] = false,
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "1 Pixel",
["border_offset"] = 1,
},
},
["height"] = 34,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
},
["talent"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "DEATHKNIGHT",
["multi"] = {
["DEATHKNIGHT"] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["parent"] = "Prot Warrior Defensives",
["icon"] = true,
["information"] = {
["forceEvents"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["keepAspectRatio"] = false,
["xOffset"] = 0,
["config"] = {
},
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Externals",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["cooldownTextDisabled"] = false,
["uid"] = "lbQyGlJiiwB",
["inverse"] = false,
["adjustedMin"] = "",
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Juggernaut"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"335232",
"383290",
},
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[18] = true,
[17] = true,
[112319] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Arms Warrior Buffs",
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "aEfoF9B4rp1",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Juggernaut",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 28,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Colossus Smash"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 167105,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Colossus Smash",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 71,
},
["talent"] = {
["single"] = 3,
["multi"] = {
[384361] = true,
[112144] = true,
[385512] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_never"] = false,
["talent2"] = {
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button3",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "usb8GUm)3ZM",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Colossus Smash",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
["linked"] = false,
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
["linked"] = false,
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Absorbs"] = {
["iconSource"] = -1,
["parent"] = "Prot Warrior Defensives",
["adjustedMax"] = "",
["customText"] = "function()\n    if aura_env.state then\n        local name = \"\"\n        local absorb = aura_env.state.tooltip1 or \"\"\n        if aura_env.state.unitCaster and not UnitIsUnit(aura_env.state.unitCaster, \"player\") then\n            name = WrapTextInColorCode( WA_Utf8Sub(aura_env.state.casterName, 5), select(4, GetClassColor(select(2, UnitClass(aura_env.state.unitCaster)))) )\n        end        \n        if aura_env.state.spellId and aura_env.state.spellId == 190456 and aura_env.state.tooltip2 then\n            absorb = aura_env.state.tooltip2 --ignore pain has 2 numbers in description\n        end\n        absorb = absorb ~= \"\" and aura_env.formatLargeNumber(absorb) or absorb\n        return name, absorb\n    end\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["tooltipValueNumber"] = 1,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["unitExists"] = false,
["use_tooltipValue"] = false,
["debuffType"] = "HELPFUL",
["showClones"] = true,
["type"] = "aura2",
["useExactSpellId"] = true,
["fetchTooltip"] = true,
["event"] = "Health",
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["spellIds"] = {
},
["names"] = {
},
["useName"] = false,
["auranames"] = {
},
["auraspellids"] = {
},
["useIgnoreName"] = false,
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(trigger)\n    return trigger[1];\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "1 Pixel",
["border_size"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text"] = "%c2",
["text_text_format_p_format"] = "timed",
["text_text_format_unitCaster_abbreviate_max"] = 8,
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_precision"] = 1,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_unitCaster_format"] = "string",
["text_fontSize"] = 14,
["type"] = "subtext",
["text_text_format_p_time_format"] = 0,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_selfPoint"] = "BOTTOM",
["text_anchorYOffset"] = -4,
["text_fontType"] = "OUTLINE",
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_text_format_c2_format"] = "none",
["text_shadowYOffset"] = 0,
["anchor_point"] = "INNER_BOTTOM",
["text_text_format_unitCaster_abbreviate"] = true,
["anchorXOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
},
},
["height"] = 34,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
},
["talent"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["class"] = {
["single"] = "DEATHKNIGHT",
["multi"] = {
["DEATHKNIGHT"] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 34,
["source"] = "import",
["progressSource"] = {
-1,
"",
},
["adjustedMin"] = "",
["information"] = {
["forceEvents"] = true,
},
["displayIcon"] = "",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["preferToUpdate"] = false,
["config"] = {
},
["xOffset"] = 0,
["anchorFrameParent"] = false,
["alpha"] = 1,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["do_custom"] = true,
["custom"] = "aura_env.formatLargeNumber = function(number)\n    if number<1000 then return number end\n    if number<10000 then return string.sub(number,1,1)..\".\"..string.sub(number,2,2)..\"k\"; end\n    if number<100000 then return string.sub(number,1,2)..\".\"..string.sub(number,3,3)..\"k\"; end\n    if number<1000000 then return string.sub(number,1,3)..\"k\"; end\n    if number<10000000 then return string.sub(number,1,1)..\".\"..string.sub(number,2,3)..\"m\"; end\n    if number<100000000 then return string.sub(number,1,2)..\".\"..string.sub(number,3,4)..\"m\"; end\n    return string.sub(number,1,3)..\".\"..string.sub(number,4,5)..\"m\";\nend",
},
},
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Absorbs",
["zoom"] = 0.3,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["useCooldownModRate"] = true,
["uid"] = "Ymtm0VPOYr0",
["inverse"] = false,
["authorOptions"] = {
},
["conditions"] = {
},
["cooldown"] = true,
["selfPoint"] = "CENTER",
},
["Warrior » Emphasized Buffs"] = {
["controlledChildren"] = {
"Prot Warrior: Execute",
"Prot Warrior: Execute (Massacre)",
"Arms Warrior: Execute",
"Arms Warrior: Execute (Massacre)",
"Arms Warrior: Sweeping Strikes Buff",
"Arms Warrior: Colossus Smash Debuff",
"Arms Warrior: Sudden Death",
"Arms Warrior: Slayer Conditions",
"Arms Warrior: Rend",
"Arms Warrior: Deep Wounds",
"Fury Warrior: Brutal Finish",
"Fury Warrior: Burst of Power",
"Fury Warrior: Whirlwind Stacks - Voz",
"Fury Warrior: Sudden Death",
"Fury Warrior: Slayer SD Conditions",
"Fury Warrior: Execute",
"Fury Warrior: Execute (Massacre)",
},
["borderBackdrop"] = "Blizzard Tooltip",
["parent"] = "Warrior",
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["anchorPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["names"] = {
},
},
["untrigger"] = {
},
},
},
["internalVersion"] = 86,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["subRegions"] = {
},
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["backdropColor"] = {
1,
1,
1,
0.5,
},
["scale"] = 1,
["border"] = false,
["borderEdge"] = "Square Full White",
["regionType"] = "group",
["borderSize"] = 2,
["borderInset"] = 1,
["borderOffset"] = 4,
["authorOptions"] = {
},
["tocversion"] = 110200,
["id"] = "Warrior » Emphasized Buffs",
["alpha"] = 1,
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["xOffset"] = 0,
["uid"] = "eYQBRDxFLjE",
["yOffset"] = 0,
["config"] = {
},
["conditions"] = {
},
["information"] = {
},
["selfPoint"] = "CENTER",
},
["Fury Warrior: Improvised Seaforium Pacemaker"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["ownOnly"] = true,
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["debuffType"] = "HELPFUL",
["unit"] = "player",
["event"] = "Health",
["names"] = {
"Aspect of the Eagle",
},
["auranames"] = {
"1218713",
},
["useName"] = true,
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["matchesShowOn"] = "showOnActive",
["combineMatches"] = "showLowest",
["useExactSpellId"] = false,
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slidebottom",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["role"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["itemequiped"] = {
232541,
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
},
["useAdjustededMax"] = false,
["source"] = "import",
["authorOptions"] = {
},
["xOffset"] = 0,
["keepAspectRatio"] = false,
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["selfPoint"] = "CENTER",
["parent"] = "Fury Warrior Buffs",
["uid"] = "qBaperWx)cP",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Improvised Seaforium Pacemaker",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 28,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Unyielding Netherprism"] = {
["iconSource"] = -1,
["parent"] = "Prot Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Aspect of the Eagle",
},
["use_tooltip"] = false,
["custom_hide"] = "timed",
["showClones"] = true,
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
"1239675",
},
["useExactSpellId"] = false,
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["subeventSuffix"] = "_CAST_START",
["ownOnly"] = true,
["unit"] = "player",
["spellIds"] = {
},
["type"] = "aura2",
["auranames"] = {
"1233556",
},
["combineMatches"] = "showLowest",
["subeventPrefix"] = "SPELL",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["role"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["itemequiped"] = {
242396,
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
},
["useAdjustededMax"] = false,
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["xOffset"] = 0,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slidebottom",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["keepAspectRatio"] = false,
["authorOptions"] = {
},
["uid"] = "6y8FAwQeOuL",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Unyielding Netherprism",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28,
["zoom"] = 0.3,
["config"] = {
},
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Bitter Immunity"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 383762,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Bitter Immunity",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 26,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["spec"] = {
["single"] = 3,
["multi"] = {
true,
true,
true,
},
},
["use_never"] = false,
["spellknown"] = 383762,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "LqSUflSaJb1",
["parent"] = "Warrior » Top Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Bitter Immunity",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 26,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Fury Warrior: Thunder Clap"] = {
["iconSource"] = -1,
["parent"] = "Warrior » Primary Bar",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 6343,
["type"] = "spell",
["names"] = {
},
["unevent"] = "auto",
["use_genericShowOn"] = true,
["subeventSuffix"] = "_CAST_START",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Thunder Clap",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["duration"] = "1",
["unit"] = "player",
["use_track"] = true,
["use_unit"] = true,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["type"] = "aura2",
["auranames"] = {
"435615",
},
["unit"] = "player",
["useName"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowType"] = "Proc",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glow"] = false,
["glowXOffset"] = 0,
["glowThickness"] = 1,
["glowScale"] = 1,
["glowDuration"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text_format_s_format"] = "none",
["text_text"] = "%2.s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_format"] = 0,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorXOffset"] = 0,
["text_text_format_p_time_mod_rate"] = true,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_format"] = "timed",
["text_anchorYOffset"] = -5,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["text_text_format_p_time_dynamic_threshold"] = 60,
["anchorYOffset"] = 0,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[73] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[394062] = true,
[112205] = true,
},
},
["use_class_and_spec"] = true,
["use_never"] = false,
["use_talent"] = false,
["use_herotalent"] = false,
["use_spellknown"] = false,
["talent2"] = {
},
["herotalent"] = {
["multi"] = {
[117400] = true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 6343,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["desaturate"] = false,
["source"] = "import",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["useTooltip"] = false,
["progressSource"] = {
-1,
"",
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["authorOptions"] = {
},
["uid"] = "Wulgqdrt2aK",
["color"] = {
1,
1,
1,
1,
},
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["useAdjustededMin"] = false,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Thunder Clap",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 34,
["xOffset"] = 0,
["config"] = {
},
["inverse"] = true,
["selfPoint"] = "CENTER",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "insufficientResources",
["value"] = 1,
},
["changes"] = {
{
["value"] = {
0.458823561668396,
0.4862745404243469,
0.7176470756530762,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 2,
["variable"] = "stacks",
["value"] = "2",
["op"] = "==",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Intervene"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 3411,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Intervene",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_petbattle"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spellknown"] = 3411,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "b4)DGppthru",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Intervene",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Fury Warrior: Raging Blow"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 85288,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Raging Blow",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -5,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[112290] = false,
[112265] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["class_and_spec"] = {
["single"] = 72,
},
["use_spellknown"] = false,
["talent2"] = {
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_exact_spellknown"] = false,
["spellknown"] = 85288,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "pIl)ZphUOWJ",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Raging Blow",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["op"] = ">",
["variable"] = "AND",
["checks"] = {
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
{
["trigger"] = 1,
["op"] = ">",
["value"] = "0",
["variable"] = "charges",
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "cooldownEdge",
},
{
["value"] = false,
["property"] = "cooldownSwipe",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["value"] = "0",
["variable"] = "charges",
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Revenge! Right"] = {
["parent"] = "Prot Warrior Spell Alerts",
["preferToUpdate"] = false,
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["type"] = "aura2",
["useStacks"] = true,
["auraspellids"] = {
"5302",
},
["ownOnly"] = true,
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["subeventSuffix"] = "_CAST_START",
["stacks"] = "1",
["spellIds"] = {
},
["unit"] = "player",
["names"] = {
},
["useExactSpellId"] = true,
["stacksOperator"] = ">=",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["animation"] = {
["start"] = {
["type"] = "preset",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["colorR"] = 1,
["scalex"] = 1,
["alphaType"] = "hide",
["colorB"] = 1,
["colorG"] = 1,
["alphaFunc"] = "function()\n    return 0\nend\n",
["use_alpha"] = false,
["type"] = "preset",
["easeType"] = "none",
["preset"] = "fade",
["alpha"] = 0.19,
["y"] = 0,
["x"] = 0,
["duration_type"] = "seconds",
["easeStrength"] = 3,
["rotate"] = 0,
["scaley"] = 1,
["colorA"] = 1,
},
},
["desaturate"] = false,
["rotation"] = 0,
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["height"] = 210,
["rotate"] = false,
["load"] = {
["use_never"] = false,
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["use_class_and_spec"] = true,
["class_and_spec"] = {
["single"] = 73,
},
["class"] = {
["multi"] = {
},
},
["spellknown"] = 79684,
["size"] = {
["multi"] = {
},
},
},
["textureWrapMode"] = "CLAMPTOBLACKADDITIVE",
["source"] = "import",
["mirror"] = true,
["regionType"] = "texture",
["blendMode"] = "BLEND",
["texture"] = "603339",
["uid"] = "ojxYWMkSzmn",
["color"] = {
1,
1,
1,
1,
},
["tocversion"] = 110200,
["id"] = "Prot Warrior: Revenge! Right",
["frameStrata"] = 1,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["width"] = 100,
["config"] = {
},
["xOffset"] = 155,
["authorOptions"] = {
},
["conditions"] = {
},
["information"] = {
},
["selfPoint"] = "CENTER",
},
["Arms Warrior Buffs"] = {
["grow"] = "HORIZONTAL",
["controlledChildren"] = {
"Arms Warrior: Bloodlust",
"Arms Warrior: Potion",
"Arms Warrior: Racials",
"Arms Warrior: Power Infusion",
"Arms Warrior: Signet of the Priory",
"Arms Warrior: Improvised Seaforium Pacemaker",
"Arms Warrior: Cursed Stone Idol",
"Arms Warrior: Araz's Ritual Forge",
"Arms Warrior: Astral Antenna Orb",
"Arms Warrior: Astral Antenna Buff",
"Arms Warrior: Unyielding Netherprism",
"Arms Warrior: Champion's Might",
"Arms Warrior: Bladestorm Buff",
"Arms Warrior: Ravager Buff",
"Arms Warrior: Ravager w/ Unhinged",
"Arms Warrior: Marked for Execution",
"Arms Warrior: Recklessness Buff",
"Arms Warrior: Juggernaut",
"Arms Warrior: Avatar Buff",
"Arms Warrior: Collateral Damage",
"Arms Warrior: Merciless Bonegrinder",
"Arms Warrior: Dance of Death",
"Arms Warrior: Storm of Swords",
"Arms Warrior: Wrecked Debuff",
"Arms Warrior: Test of Might",
},
["borderBackdrop"] = "Blizzard Tooltip",
["authorOptions"] = {
},
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["gridType"] = "RD",
["fullCircle"] = true,
["space"] = 3,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["names"] = {
},
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["internalVersion"] = 86,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["align"] = "CENTER",
["alpha"] = 1,
["yOffset"] = -147,
["selfPoint"] = "CENTER",
["rotation"] = 0,
["rowSpace"] = 1,
["radius"] = 200,
["subRegions"] = {
},
["stagger"] = 0,
["anchorPoint"] = "CENTER",
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["parent"] = "Warrior » Buff Bar",
["backdropColor"] = {
1,
1,
1,
0.5,
},
["borderInset"] = 1,
["animate"] = false,
["arcLength"] = 360,
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["stepAngle"] = 15,
["borderSize"] = 2,
["sort"] = "none",
["sortHybridTable"] = {
["Arms Warrior: Test of Might"] = false,
["Arms Warrior: Avatar Buff"] = false,
["Arms Warrior: Potion"] = false,
["Arms Warrior: Unyielding Netherprism"] = false,
["Arms Warrior: Recklessness Buff"] = false,
["Arms Warrior: Racials"] = false,
["Arms Warrior: Power Infusion"] = false,
["Arms Warrior: Merciless Bonegrinder"] = false,
["Arms Warrior: Araz's Ritual Forge"] = false,
["Arms Warrior: Storm of Swords"] = false,
["Arms Warrior: Wrecked Debuff"] = false,
["Arms Warrior: Dance of Death"] = false,
["Arms Warrior: Improvised Seaforium Pacemaker"] = false,
["Arms Warrior: Bloodlust"] = false,
["Arms Warrior: Signet of the Priory"] = false,
["Arms Warrior: Ravager w/ Unhinged"] = false,
["Arms Warrior: Marked for Execution"] = false,
["Arms Warrior: Ravager Buff"] = false,
["Arms Warrior: Collateral Damage"] = false,
["Arms Warrior: Cursed Stone Idol"] = false,
["Arms Warrior: Bladestorm Buff"] = false,
["Arms Warrior: Astral Antenna Orb"] = false,
["Arms Warrior: Juggernaut"] = false,
["Arms Warrior: Champion's Might"] = false,
["Arms Warrior: Astral Antenna Buff"] = false,
},
["frameStrata"] = 1,
["constantFactor"] = "RADIUS",
["limit"] = 5,
["borderOffset"] = 4,
["config"] = {
},
["tocversion"] = 110200,
["id"] = "Arms Warrior Buffs",
["regionType"] = "dynamicgroup",
["gridWidth"] = 5,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["uid"] = "Jmv81sg9YzZ",
["borderColor"] = {
0,
0,
0,
1,
},
["useLimit"] = false,
["conditions"] = {
},
["information"] = {
},
["xOffset"] = 0.01,
},
["Warrior: Champion's Spear"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 376079,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Champion's Spear",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["DEMONHUNTER"] = true,
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent2"] = {
},
["use_class"] = true,
["use_spellknown"] = true,
["covenant"] = {
["single"] = 1,
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_class_and_spec"] = false,
["use_exact_spellknown"] = true,
["spellknown"] = 376079,
["use_covenant"] = true,
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "LLTAzwSLcQB",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Champion's Spear",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Cursed Stone Idol"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["useExactSpellId"] = false,
["ownOnly"] = true,
["names"] = {
"Aspect of the Eagle",
},
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"1242326",
},
["combineMatches"] = "showLowest",
["unit"] = "player",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["faction"] = {
["multi"] = {
},
},
["itemequiped"] = {
246344,
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Arms Warrior Buffs",
["authorOptions"] = {
},
["progressSource"] = {
-1,
"",
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Cursed Stone Idol",
["zoom"] = 0.3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["uid"] = "byxYdqt1D66",
["inverse"] = false,
["icon"] = true,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Improvised Seaforium Pacemaker"] = {
["iconSource"] = -1,
["parent"] = "Arms Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["debuffType"] = "HELPFUL",
["names"] = {
"Aspect of the Eagle",
},
["event"] = "Health",
["unit"] = "player",
["ownOnly"] = true,
["type"] = "aura2",
["spellIds"] = {
},
["auranames"] = {
"1218713",
},
["useExactSpellId"] = false,
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["faction"] = {
["multi"] = {
},
},
["itemequiped"] = {
232541,
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["stickyDuration"] = false,
["xOffset"] = 0,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["progressSource"] = {
-1,
"",
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Improvised Seaforium Pacemaker",
["alpha"] = 1,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["cooldownTextDisabled"] = false,
["uid"] = "UKoKzo7YvtW",
["inverse"] = false,
["selfPoint"] = "CENTER",
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Execute"] = {
["iconSource"] = -1,
["parent"] = "Warrior » Emphasized Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -71,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = true,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["unit"] = "target",
["use_track"] = true,
["use_genericShowOn"] = true,
["use_unit"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["use_charges"] = false,
["type"] = "unit",
["use_absorbHealMode"] = true,
["subeventSuffix"] = "_CAST_START",
["use_spellCount"] = false,
["percenthealth"] = {
"20",
},
["event"] = "Health",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["use_targetRequired"] = true,
["spellName"] = 163201,
["use_percenthealth"] = true,
["percenthealth_operator"] = {
"<=",
},
["names"] = {
},
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["unit"] = "player",
["use_spellName"] = true,
["spellName"] = 281000,
["genericShowOn"] = "showAlways",
["use_exact_spellName"] = false,
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"280776",
"52437",
},
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[3];\nend",
["activeTriggerMode"] = 2,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["glowXOffset"] = 0,
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowLength"] = 10,
["glow"] = true,
["glowDuration"] = 1,
["useGlowColor"] = false,
["glowScale"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text"] = "FREE",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_text_format_p_time_precision"] = 1,
["text_color"] = {
0,
1,
0.10980392156863,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -15,
["text_text_format_p_time_format"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_fontType"] = "OUTLINE",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchor_point"] = "CENTER",
["text_fontSize"] = 10,
["anchorXOffset"] = 0,
["text_shadowYOffset"] = 0,
},
},
["height"] = 34,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[112168] = false,
[112145] = false,
[132879] = false,
},
},
["use_class_and_spec"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["talent_extraOption"] = 0,
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["use_spec"] = true,
["covenant"] = {
["single"] = 2,
["multi"] = {
["1"] = true,
["4"] = true,
["3"] = true,
["0"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
[2] = true,
[3] = true,
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[71] = true,
},
},
["use_covenant"] = false,
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["preferToUpdate"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["conditions"] = {
{
["check"] = {
["op"] = "<",
["checks"] = {
{
["value"] = 0,
["op"] = "<",
["variable"] = "show",
},
{
["trigger"] = 3,
["variable"] = "show",
["value"] = 0,
},
},
["trigger"] = 2,
["variable"] = "insufficientResources",
["value"] = 1,
},
["linked"] = false,
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
{
["property"] = "sub.2.glow",
},
},
},
{
["check"] = {
["trigger"] = 3,
["variable"] = "show",
["value"] = 1,
},
["linked"] = true,
["changes"] = {
{
["value"] = true,
["property"] = "sub.4.text_visible",
},
},
},
},
["stickyDuration"] = false,
["authorOptions"] = {
},
["uid"] = "4t4LlDNciGQ",
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Execute",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["width"] = 34,
["xOffset"] = 0,
["config"] = {
},
["inverse"] = true,
["keepAspectRatio"] = false,
["displayIcon"] = "135358",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "alphaPulse",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
},
["Fury Warrior: Odyn's Fury"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 385059,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Odyn's Fury",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["multi"] = {
[382310] = true,
[112289] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 72,
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 385059,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "c6LQ49akmpa",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Odyn's Fury",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellUsable",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior Buffs"] = {
["grow"] = "HORIZONTAL",
["controlledChildren"] = {
"Prot Warrior: Bloodlust",
"Prot Warrior: Potion",
"Prot Warrior: Racials",
"Prot Warrior: Power Infusion",
"Prot Warrior: Signet of the Priory",
"Prot Warrior: Tome of Light's Devotion Stacks",
"Prot Warrior: Improvised Seaforium Pacemaker",
"Prot Warrior: Cursed Stone Idol",
"Prot Warrior: Unyielding Netherprism",
"Prot Warrior: Araz's Ritual Forge",
"Prot Warrior: Astral Antenna Orb",
"Prot Warrior: Astral Antenna Buff",
"Prot Warrior: Champion's Might",
"Prot Warrior: Ravager Buff",
"Prot Warrior: Avatar Buff",
"Prot Warrior: Sudden Death",
"Prot Warrior: Seeing Red",
"Prot Warrior: Wrecked",
},
["borderBackdrop"] = "Blizzard Tooltip",
["xOffset"] = 0.01,
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["sortHybridTable"] = {
["Prot Warrior: Seeing Red"] = false,
["Prot Warrior: Unyielding Netherprism"] = false,
["Prot Warrior: Champion's Might"] = false,
["Prot Warrior: Ravager Buff"] = false,
["Prot Warrior: Potion"] = false,
["Prot Warrior: Astral Antenna Buff"] = false,
["Prot Warrior: Bloodlust"] = false,
["Prot Warrior: Signet of the Priory"] = false,
["Prot Warrior: Cursed Stone Idol"] = false,
["Prot Warrior: Tome of Light's Devotion Stacks"] = false,
["Prot Warrior: Wrecked"] = false,
["Prot Warrior: Power Infusion"] = false,
["Prot Warrior: Sudden Death"] = false,
["Prot Warrior: Avatar Buff"] = false,
["Prot Warrior: Racials"] = false,
["Prot Warrior: Astral Antenna Orb"] = false,
["Prot Warrior: Araz's Ritual Forge"] = false,
["Prot Warrior: Improvised Seaforium Pacemaker"] = false,
},
["borderColor"] = {
0,
0,
0,
1,
},
["space"] = 3,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["names"] = {
},
["event"] = "Health",
["subeventPrefix"] = "SPELL",
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["internalVersion"] = 86,
["selfPoint"] = "CENTER",
["align"] = "CENTER",
["alpha"] = 1,
["yOffset"] = -140,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["rotation"] = 0,
["gridType"] = "RD",
["radius"] = 200,
["subRegions"] = {
},
["stagger"] = 0,
["rowSpace"] = 1,
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["authorOptions"] = {
},
["backdropColor"] = {
1,
1,
1,
0.5,
},
["uid"] = "PFm8vFME(hc",
["source"] = "import",
["arcLength"] = 360,
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["stepAngle"] = 15,
["borderSize"] = 2,
["sort"] = "none",
["anchorPoint"] = "CENTER",
["gridWidth"] = 5,
["constantFactor"] = "RADIUS",
["animate"] = false,
["borderOffset"] = 4,
["limit"] = 5,
["tocversion"] = 110200,
["id"] = "Prot Warrior Buffs",
["regionType"] = "dynamicgroup",
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["config"] = {
},
["borderInset"] = 1,
["fullCircle"] = true,
["useLimit"] = false,
["conditions"] = {
},
["information"] = {
},
["parent"] = "Warrior » Buff Bar",
},
["Warrior » PvP Bar"] = {
["grow"] = "HORIZONTAL",
["controlledChildren"] = {
"Warrior: Disarm",
"Warrior: Bodyguard",
"Warrior: Dragon Charge",
"Warrior: Sharpen Blade",
"Warrior: Duel",
"Warrior: Death Wish",
},
["borderBackdrop"] = "Blizzard Tooltip",
["xOffset"] = -0.2,
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["anchorPoint"] = "CENTER",
["fullCircle"] = true,
["space"] = 3,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["subeventPrefix"] = "SPELL",
["unit"] = "player",
["event"] = "Health",
["names"] = {
},
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["radius"] = 200,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["align"] = "CENTER",
["alpha"] = 1,
["authorOptions"] = {
},
["useLimit"] = false,
["rotation"] = 0,
["rowSpace"] = 1,
["sortHybridTable"] = {
["Warrior: Duel"] = false,
["Warrior: Dragon Charge"] = false,
["Warrior: Sharpen Blade"] = false,
["Warrior: Death Wish"] = false,
["Warrior: Bodyguard"] = false,
["Warrior: Disarm"] = false,
},
["subRegions"] = {
},
["stagger"] = 0,
["arcLength"] = 360,
["load"] = {
["talent"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["uid"] = "Gyd0u1FK2x2",
["backdropColor"] = {
1,
1,
1,
0.5,
},
["borderInset"] = 1,
["animate"] = false,
["parent"] = "Warrior",
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["stepAngle"] = 15,
["borderSize"] = 2,
["sort"] = "none",
["gridType"] = "RD",
["frameStrata"] = 1,
["constantFactor"] = "RADIUS",
["regionType"] = "dynamicgroup",
["borderOffset"] = 4,
["selfPoint"] = "CENTER",
["tocversion"] = 110200,
["id"] = "Warrior » PvP Bar",
["limit"] = 5,
["gridWidth"] = 5,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["config"] = {
},
["borderColor"] = {
0,
0,
0,
1,
},
["internalVersion"] = 86,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["yOffset"] = -305,
},
["Warrior: Impending Victory"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 202168,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Impending Victory",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 12,
["multi"] = {
[14] = true,
[12] = true,
[18] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["DEMONHUNTER"] = true,
},
},
["use_class"] = true,
["use_spellknown"] = true,
["use_class_and_spec"] = false,
["use_petbattle"] = false,
["use_never"] = false,
["spec"] = {
["single"] = 3,
["multi"] = {
true,
[3] = true,
},
},
["spellknown"] = 202168,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "2Ne3EtG3TTc",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Impending Victory",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078432083129883,
0.2352941334247589,
0.2313725650310516,
1,
},
["property"] = "color",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Warrior: Avatar"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 107574,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Avatar",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 3,
["multi"] = {
[386285] = true,
[107570] = true,
},
},
["use_class_and_spec"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button3",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "sGDv0XgyXuU",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Avatar",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Slayer SD Conditions"] = {
["iconSource"] = 0,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -79,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["type"] = "custom",
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["unit"] = "player",
["names"] = {
},
["events"] = "UNIT_AURA:player,UNIT_AURA:target,ACTIONBAR_UPDATE_USABLE,PLAYER_TARGET_CHANGED",
["custom"] = "function(allstates, event, ...)\n    local SUDDEN_DEATH = 280776\n    local ASHEN_JUGGERNAUT = 392537\n    local MARKED_FOR_EXECUTION = 445584\n    local EXECUTE = 5308\n    \n    if not C_Spell.IsSpellUsable(EXECUTE) then\n        allstates[\"\"] = nil\n        return true\n    end\n    \n    local function getAuraInfo(spellId)\n        for i = 1, 40 do\n            local aura = C_UnitAuras.GetAuraDataByIndex(\"player\", i, \"HELPFUL\")\n            if not aura then break end\n            if aura.spellId == spellId then return aura end\n        end\n        return nil\n    end\n    \n    local function getTargetDebuffInfo(spellId)\n        for i = 1, 40 do\n            local aura = C_UnitAuras.GetAuraDataByIndex(\"target\", i, \"HARMFUL\")\n            if not aura then break end\n            if aura.spellId == spellId then return aura end\n        end\n        return nil\n    end\n    \n    local sd = getAuraInfo(SUDDEN_DEATH)\n    local aj = getAuraInfo(ASHEN_JUGGERNAUT) \n    local mfe = getTargetDebuffInfo(MARKED_FOR_EXECUTION)\n    \n    local currentTime = GetTime()\n    local sdRemaining = sd and (sd.expirationTime - currentTime) or 0\n    local ajRemaining = aj and (aj.expirationTime - currentTime) or 0\n    local mfeStacks = mfe and mfe.applications or 0\n    \n    local sdUrgent = sd and (sdRemaining < 5 or (sd.applications == 2))\n    local ajUrgent = aj and ajRemaining < 5  \n    local mfeUrgent = sd and mfe and mfeStacks > 1\n    \n    local activeAura, source, spellId\n    if mfeUrgent then\n        activeAura, source, spellId = mfe, \"Marked for Execution\", MARKED_FOR_EXECUTION\n    elseif ajUrgent then\n        activeAura, source, spellId = aj, \"Ashen Juggernaut\", ASHEN_JUGGERNAUT  \n    elseif sdUrgent then\n        activeAura, source, spellId = sd, \"Sudden Death\", SUDDEN_DEATH\n    end\n    \n    if activeAura then\n        allstates[\"\"] = {\n            show = true,\n            changed = true,\n            progressType = \"timed\",\n            duration = activeAura.duration,\n            expirationTime = activeAura.expirationTime,\n            name = source,\n            icon = activeAura.icon,\n            stacks = activeAura.applications or 0,\n            spellId = spellId,\n        }\n    else\n        allstates[\"\"] = nil\n    end\n    \n    return true\nend",
["custom_type"] = "stateupdate",
["check"] = "event",
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowType"] = "Proc",
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowDuration"] = 1,
["glowXOffset"] = 0,
["glowScale"] = 1,
["glow"] = true,
["glowLength"] = 10,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 32,
["load"] = {
["class_and_spec"] = {
["single"] = 72,
},
["talent"] = {
["multi"] = {
[112300] = true,
[112278] = true,
},
},
["class"] = {
["multi"] = {
},
},
["use_talent"] = false,
["use_herotalent"] = false,
["herotalent"] = {
["multi"] = {
[117411] = true,
[117400] = false,
},
},
["spec"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["parent"] = "Warrior » Emphasized Buffs",
["uid"] = "trywivzJXeC",
["desc"] = "Fury Slayer Execute Conditions. Shows the icon of the conditional hit (Sudden Death, Ashen Juggernaut or Marked For Execution and duration remaining on the buff/debuff) and plays the \"kaching\" sound.",
["xOffset"] = 100.1,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["cooldown"] = true,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = {
["sound_type"] = "Play",
["sound"] = "Interface\\Addons\\AtrocityMedia\\Sounds\\Blood.ogg",
["sound_channel"] = "Master",
},
["property"] = "sound",
},
},
},
},
["progressSource"] = {
-1,
"",
},
["preferToUpdate"] = false,
["anchorFrameType"] = "SCREEN",
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["frameStrata"] = 1,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Slayer SD Conditions",
["authorOptions"] = {
},
["alpha"] = 1,
["width"] = 32,
["zoom"] = 0.3,
["config"] = {
},
["inverse"] = false,
["selfPoint"] = "CENTER",
["displayIcon"] = "132344",
["information"] = {
},
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
},
["Arms Warrior: Overpower"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 7384,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Overpower",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -5,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[384361] = true,
[112123] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_never"] = false,
["talent2"] = {
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "5G2(VgkkMue",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Overpower",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["op"] = ">",
["variable"] = "AND",
["checks"] = {
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
{
["trigger"] = 1,
["op"] = ">",
["value"] = "0",
["variable"] = "charges",
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "cooldownEdge",
},
{
["value"] = false,
["property"] = "cooldownSwipe",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["value"] = "0",
["variable"] = "charges",
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Power Infusion"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"10060",
},
["duration"] = "1",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["custom_hide"] = "timed",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["useExactSpellId"] = false,
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["matchesShowOn"] = "showOnActive",
["auraspellids"] = {
},
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["spellIds"] = {
},
["type"] = "aura2",
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["subeventPrefix"] = "SPELL",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "fade",
["easeStrength"] = 3,
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "slideright",
["easeStrength"] = 3,
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["race"] = {
["single"] = "Orc",
["multi"] = {
["Orc"] = true,
},
},
["use_itemequiped"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[103] = true,
[253] = true,
[72] = true,
[581] = true,
[268] = true,
[259] = true,
[104] = true,
[250] = true,
[254] = true,
[260] = true,
[71] = true,
[73] = true,
[577] = true,
[261] = true,
[269] = true,
[251] = true,
[66] = true,
},
},
["talent"] = {
["single"] = 20,
["multi"] = {
[20] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["itemequiped"] = {
174500,
},
["role"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["selfPoint"] = "CENTER",
["cooldown"] = true,
["conditions"] = {
},
["color"] = {
1,
1,
1,
1,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["uid"] = "93Ena2NJzTx",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["width"] = 28,
["anchorFrameParent"] = false,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Power Infusion",
["keepAspectRatio"] = false,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["parent"] = "Prot Warrior Buffs",
["config"] = {
},
["inverse"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["displayIcon"] = 1305160,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Shockwave"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 46968,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Shockwave",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[394062] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_spellknown"] = true,
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_class_and_spec"] = false,
["use_exact_spellknown"] = true,
["spellknown"] = 46968,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "dAEj6lrt6gh",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Shockwave",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Fury Warrior: Power Infusion"] = {
["iconSource"] = -1,
["parent"] = "Fury Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"10060",
},
["duration"] = "1",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useExactSpellId"] = false,
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
},
["unit"] = "player",
["matchesShowOn"] = "showOnActive",
["event"] = "Health",
["unevent"] = "timed",
["useGroup_count"] = false,
["debuffType"] = "HELPFUL",
["spellIds"] = {
},
["useName"] = true,
["subeventSuffix"] = "_CAST_START",
["combineMatches"] = "showLowest",
["subeventPrefix"] = "SPELL",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "fade",
},
["main"] = {
["type"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = false,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[103] = true,
[253] = true,
[72] = true,
[581] = true,
[268] = true,
[259] = true,
[104] = true,
[250] = true,
[254] = true,
[260] = true,
[71] = true,
[73] = true,
[577] = true,
[261] = true,
[269] = true,
[251] = true,
[66] = true,
},
},
["talent"] = {
["single"] = 20,
["multi"] = {
[20] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["zoneIds"] = "",
["pvptalent"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["race"] = {
["single"] = "Orc",
["multi"] = {
["Orc"] = true,
},
},
["itemequiped"] = {
174500,
},
["faction"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["selfPoint"] = "CENTER",
["source"] = "import",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 1305160,
["xOffset"] = 0,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Power Infusion",
["desaturate"] = false,
["alpha"] = 1,
["width"] = 28,
["authorOptions"] = {
},
["uid"] = "Id78Fs0ohW7",
["inverse"] = false,
["keepAspectRatio"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior » Buff Bar"] = {
["controlledChildren"] = {
"Prot Warrior Defensives",
"Prot Warrior Buffs",
"Fury Warrior Buffs",
"Arms Warrior Buffs",
},
["borderBackdrop"] = "Blizzard Tooltip",
["parent"] = "Warrior",
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["anchorPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["names"] = {
},
["event"] = "Health",
["subeventPrefix"] = "SPELL",
},
["untrigger"] = {
},
},
},
["internalVersion"] = 86,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["subRegions"] = {
},
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["backdropColor"] = {
1,
1,
1,
0.5,
},
["source"] = "import",
["scale"] = 1,
["border"] = false,
["borderEdge"] = "Square Full White",
["regionType"] = "group",
["borderSize"] = 2,
["borderInset"] = 1,
["borderOffset"] = 4,
["authorOptions"] = {
},
["tocversion"] = 110200,
["id"] = "Warrior » Buff Bar",
["frameStrata"] = 1,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["xOffset"] = 0,
["config"] = {
},
["yOffset"] = 0,
["uid"] = "tJVUwwtGUOq",
["conditions"] = {
},
["information"] = {
},
["selfPoint"] = "CENTER",
},
["Warrior: Unyielding Netherprism Stacks"] = {
["iconSource"] = -1,
["parent"] = "Warrior » Primary Bar",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["auranames"] = {
"1239675",
},
["matchesShowOn"] = "showAlways",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["itemSlot"] = 13,
["use_unit"] = true,
["names"] = {
},
["duration"] = "1",
["debuffType"] = "HELPFUL",
["use_trackcharge"] = false,
["buffShowOn"] = "showOnActive",
["spellName"] = 113860,
["type"] = "aura2",
["useName"] = true,
["subeventSuffix"] = "_CAST_START",
["unevent"] = "auto",
["realSpellName"] = 113860,
["event"] = "Cooldown Progress (Equipment Slot)",
["use_exact_spellName"] = true,
["use_itemSlot"] = true,
["use_spellName"] = true,
["spellIds"] = {
},
["use_testForCooldown"] = true,
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["use_absorbMode"] = true,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
["itemSlot"] = 14,
},
},
["disjunctive"] = "all",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorYOffset"] = 0,
["type"] = "subtext",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_color"] = {
0,
1,
0.1098039299249649,
1,
},
["text_font"] = "Expressway",
["text_shadowXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontType"] = "OUTLINE",
["text_text_format_p_time_format"] = 0,
["anchor_point"] = "CENTER",
["text_fontSize"] = 20,
["anchorXOffset"] = 0,
["text_text_format_p_time_mod_rate"] = true,
},
{
["glowFrequency"] = 0.2,
["glow"] = false,
["useGlowColor"] = true,
["glowType"] = "Pixel",
["glowLength"] = 14,
["glowYOffset"] = 0,
["glowColor"] = {
0,
1,
0.1098039299249649,
1,
},
["type"] = "subglow",
["glowXOffset"] = 0,
["glowDuration"] = 1,
["glowScale"] = 1,
["glowThickness"] = 2,
["glowLines"] = 5,
["glowBorder"] = true,
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 258,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["class"] = {
["single"] = "DRUID",
["multi"] = {
["PRIEST"] = true,
["DEMONHUNTER"] = true,
},
},
["use_class"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
true,
},
},
["use_itemequiped"] = true,
["itemequiped"] = {
242396,
},
["use_never"] = false,
["use_spec"] = false,
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 34,
["source"] = "import",
["useAdjustededMin"] = false,
["keepAspectRatio"] = false,
["cooldown"] = false,
["stickyDuration"] = false,
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "HN9(mFSOo(T",
["authorOptions"] = {
},
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Unyielding Netherprism Stacks",
["cooldownTextDisabled"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["xOffset"] = 0,
["config"] = {
},
["inverse"] = true,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["custom"] = "\n\n",
["do_custom"] = false,
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "stacks",
["op"] = "==",
["value"] = "0",
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "stacks",
["op"] = "==",
["value"] = "18",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.4.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Enrage Timer"] = {
["sparkWidth"] = 5,
["iconSource"] = -1,
["authorOptions"] = {
{
["type"] = "input",
["useDesc"] = false,
["width"] = 1,
["key"] = "classBarNamePattern",
["name"] = "Class Bar Name Pattern",
["multiline"] = false,
["length"] = 10,
["default"] = "Warrior » Primary Bar",
["useLength"] = false,
},
{
["type"] = "number",
["key"] = "minWidth",
["default"] = 243,
["name"] = "Minimum Width",
["useDesc"] = false,
["width"] = 1,
},
},
["adjustedMax"] = "",
["yOffset"] = -170,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["backgroundColor"] = {
0.2431372702121735,
0.2431372702121735,
0.2431372702121735,
1,
},
["fontFlags"] = "OUTLINE",
["icon_color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["selfPoint"] = "CENTER",
["barColor"] = {
0.4862745404243469,
0.4862745404243469,
0.4862745404243469,
1,
},
["desaturate"] = false,
["sparkOffsetY"] = 0,
["gradientOrientation"] = "HORIZONTAL",
["load"] = {
["zoneIds"] = "",
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["talent"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["MONK"] = true,
["ROGUE"] = true,
},
},
["talent2"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 72,
},
["size"] = {
["multi"] = {
},
},
},
["smoothProgress"] = false,
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["texture"] = "Atrocity",
["zoom"] = 0,
["auto"] = true,
["tocversion"] = 110200,
["alpha"] = 1,
["sparkColor"] = {
1,
0.9921568627451,
0.9921568627451,
1,
},
["sparkOffsetX"] = 0,
["color"] = {
},
["adjustedMin"] = "",
["sparkRotationMode"] = "AUTO",
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Стойкость к боли",
},
["powertype"] = 3,
["use_hand"] = true,
["subeventPrefix"] = "SPELL",
["hand"] = "main",
["debuffType"] = "HELPFUL",
["use_unit"] = true,
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["duration"] = "1",
["use_tooltip"] = false,
["event"] = "Swing Timer",
["type"] = "aura2",
["custom_hide"] = "timed",
["use_powertype"] = true,
["spellIds"] = {
190456,
},
["auranames"] = {
"184362",
},
["unevent"] = "auto",
["combineMatches"] = "showLowest",
["unit"] = "player",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = 1,
},
["internalVersion"] = 86,
["useAdjustedMin"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["backdropInFront"] = false,
["sparkMirror"] = false,
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["anchor_area"] = "bar",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = true,
["glowType"] = "Pixel",
["glowLength"] = 10,
["glow"] = false,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowThickness"] = 1,
["glowXOffset"] = 0,
["glowScale"] = 1,
["glowDuration"] = 1,
["anchor_area"] = "bar",
["glowLines"] = 8,
["glowBorder"] = true,
},
},
["height"] = 12,
["textureSource"] = "LSM",
["sparkBlendMode"] = "ADD",
["backdropColor"] = {
1,
1,
1,
0,
},
["source"] = "import",
["preferToUpdate"] = false,
["barColor2"] = {
1,
1,
0,
1,
},
["useAdjustedMax"] = false,
["spark"] = false,
["anchorFrameFrame"] = "WeakAuras:Class » Warrior » Primary Bar",
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["borderInFront"] = true,
["uid"] = "Bi4a)jXOnFc",
["icon_side"] = "RIGHT",
["config"] = {
["classBarNamePattern"] = "Warrior » Primary Bar",
["minWidth"] = 145,
},
["useAdjustededMax"] = false,
["sparkHeight"] = 18,
["actions"] = {
["start"] = {
},
["finish"] = {
["do_glow"] = false,
["do_sound"] = false,
["glow_action"] = "hide",
},
["init"] = {
["custom"] = "function aura_env:Init()\n    local ctx = self.region.arcCustomContext\n    if not ctx then\n        ctx = {}\n        self.region.arcCustomContext = ctx\n    end\n    \n    local classBar = self:GetClassBarName()\n    local parentRegion = WeakAuras.GetRegion(classBar)\n    if not parentRegion then\n        print(self.id, \"could not find WA:\", classBar)\n        return\n    end\n    \n    ctx.parentRegion = parentRegion\n    ctx.minWidth = self.config.minWidth\n    ctx.region = self.region\n    \n    if not ctx.hooked then\n        hooksecurefunc(ctx.parentRegion, \"SetWidth\", function(_, width)\n                ctx.region:SetRegionWidth(max(ctx.minWidth, width))\n        end)\n        ctx.hooked = true\n    end\nend\n\nfunction aura_env:GetClassBarName()\n    local classNames = {\"Warrior\", \"Paladin\", \"Hunter\", \"Rogue\", \"Priest\", \"Death Knight\",\n    \"Shaman\", \"Mage\", \"Warlock\", \"Monk\", \"Druid\", \"Demon Hunter\",\"Evoker\"}\n    local class = select(2, UnitClass(\"player\"))\n    for i, name in ipairs(classNames) do\n        if class == name:gsub(\" \", \"\"):upper() then\n            return self.config.classBarNamePattern:format(name)\n        end\n    end\nend\n\naura_env:Init()",
["do_custom"] = true,
},
},
["width"] = 145,
["borderBackdrop"] = "None",
["parent"] = "Warrior",
["id"] = "Fury Warrior: Enrage Timer",
["sparkHidden"] = "BOTH",
["icon"] = false,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["customTextUpdate"] = "update",
["progressSource"] = {
-1,
"",
},
["inverse"] = false,
["sparkDesature"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "expirationTime",
["value"] = "1",
["op"] = "<=",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.4.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["xOffset"] = 0,
},
["Arms Warrior: Marked for Execution"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HARMFUL",
["custom_hide"] = "timed",
["event"] = "Health",
["ownOnly"] = true,
["duration"] = "1",
["useName"] = true,
["spellIds"] = {
},
["auranames"] = {
"445584",
},
["unit"] = "target",
["combineMatches"] = "showLowest",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["unevent"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.2,
["type"] = "subglow",
["useGlowColor"] = true,
["glowScale"] = 1,
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
0.8980392813682556,
0,
1,
},
["glowType"] = "Pixel",
["glowThickness"] = 1,
["glow"] = false,
["glowXOffset"] = 0,
["glowDuration"] = 1,
["glowLines"] = 4,
["glowBorder"] = true,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_precision"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112275] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["size"] = {
["multi"] = {
},
},
["use_herotalent"] = false,
["race"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["faction"] = {
["multi"] = {
},
},
["herotalent"] = {
["multi"] = {
[117411] = true,
},
},
["difficulty"] = {
["multi"] = {
},
},
},
["alpha"] = 1,
["useAdjustededMax"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["source"] = "import",
["keepAspectRatio"] = false,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "stacks",
["op"] = "==",
["value"] = "3",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["parent"] = "Arms Warrior Buffs",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["config"] = {
},
["xOffset"] = 0,
["width"] = 28,
["anchorFrameParent"] = false,
["stickyDuration"] = false,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Marked for Execution",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["selfPoint"] = "CENTER",
["uid"] = "JS)RXwmG4Cr",
["inverse"] = false,
["adjustedMin"] = "",
["displayIcon"] = 237569,
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Astral Antenna Orb"] = {
["iconSource"] = 0,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1239640",
},
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useName"] = false,
["use_debuffClass"] = false,
["useExactSpellId"] = true,
["buffShowOn"] = "showOnActive",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Aspect of the Eagle",
},
["ownOnly"] = true,
["type"] = "aura2",
["spellIds"] = {
},
["useGroup_count"] = false,
["unit"] = "player",
["combineMatches"] = "showLowest",
["auraspellids"] = {
"1239640",
},
["subeventSuffix"] = "_CAST_START",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["use_class_and_spec"] = true,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["itemequiped"] = {
242395,
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 332402,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["parent"] = "Arms Warrior Buffs",
["config"] = {
},
["xOffset"] = 0,
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Astral Antenna Orb",
["cooldownTextDisabled"] = false,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["desaturate"] = false,
["uid"] = "26SHhnYSvfE",
["inverse"] = false,
["icon"] = true,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Disarm"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["subeventPrefix"] = "SPELL",
["type"] = "spell",
["unit"] = "player",
["subeventSuffix"] = "_CAST_START",
["names"] = {
},
["duration"] = "1",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Disarm",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["unevent"] = "auto",
["use_genericShowOn"] = true,
["use_track"] = true,
["spellName"] = 236077,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[334046] = true,
},
},
["use_class_and_spec"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["class"] = {
["single"] = "SHAMAN",
["multi"] = {
["DEMONHUNTER"] = true,
["SHAMAN"] = true,
},
},
["use_petbattle"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class_and_spec"] = {
["single"] = 263,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_spec"] = false,
["pvptalent"] = {
},
["use_exact_spellknown"] = false,
["spellknown"] = 236077,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28.7,
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["parent"] = "Warrior » PvP Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Disarm",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "eyBXEHIORwM",
["inverse"] = true,
["color"] = {
1,
1,
1,
1,
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["cooldown"] = true,
["desaturate"] = false,
},
["Prot Warrior: Shield Block Timer"] = {
["sparkWidth"] = 5,
["iconSource"] = -1,
["authorOptions"] = {
{
["type"] = "input",
["useDesc"] = false,
["width"] = 1,
["key"] = "classBarNamePattern",
["name"] = "Class Bar Name Pattern",
["multiline"] = false,
["length"] = 10,
["default"] = "Warrior » Primary Bar",
["useLength"] = false,
},
{
["type"] = "number",
["key"] = "minWidth",
["default"] = 243,
["name"] = "Minimum Width",
["useDesc"] = false,
["width"] = 1,
},
},
["adjustedMax"] = "",
["yOffset"] = -172,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["backgroundColor"] = {
0.2431372702121735,
0.2431372702121735,
0.2431372702121735,
1,
},
["fontFlags"] = "OUTLINE",
["icon_color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["selfPoint"] = "CENTER",
["barColor"] = {
0.4862745404243469,
0.4862745404243469,
0.4862745404243469,
1,
},
["desaturate"] = false,
["sparkOffsetY"] = 0,
["gradientOrientation"] = "HORIZONTAL",
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["use_class_and_spec"] = true,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
},
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["MONK"] = true,
["ROGUE"] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["smoothProgress"] = false,
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["texture"] = "Atrocity",
["zoom"] = 0,
["auto"] = true,
["tocversion"] = 110200,
["alpha"] = 1,
["sparkColor"] = {
1,
0.9921568627451,
0.9921568627451,
1,
},
["sparkOffsetX"] = 0,
["color"] = {
},
["adjustedMin"] = "",
["sparkRotationMode"] = "AUTO",
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"132404",
},
["ownOnly"] = true,
["names"] = {
"Стойкость к боли",
},
["powertype"] = 3,
["use_unit"] = true,
["use_powertype"] = true,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["event"] = "Power",
["useName"] = true,
["unevent"] = "auto",
["matchesShowOn"] = "showOnActive",
["spellIds"] = {
190456,
},
["custom_hide"] = "timed",
["duration"] = "1",
["combineMatches"] = "showLowest",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = 1,
},
["internalVersion"] = 86,
["useAdjustedMin"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["backdropInFront"] = false,
["sparkMirror"] = false,
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
["text_shadowColor"] = {
},
["text_color"] = {
},
},
{
["type"] = "subborder",
["text_color"] = {
},
["border_color"] = {
0,
0,
0,
1,
},
["text_shadowColor"] = {
},
["border_edge"] = "Square Full White",
["border_offset"] = 1,
["anchor_area"] = "bar",
["border_size"] = 1,
["border_visible"] = true,
},
},
["height"] = 8,
["textureSource"] = "LSM",
["sparkBlendMode"] = "ADD",
["backdropColor"] = {
1,
1,
1,
0,
},
["source"] = "import",
["preferToUpdate"] = false,
["barColor2"] = {
1,
1,
0,
1,
},
["useAdjustedMax"] = false,
["spark"] = false,
["anchorFrameFrame"] = "WeakAuras:Class » Warrior » Primary Bar",
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["borderInFront"] = true,
["uid"] = "hOwDOuEha77",
["icon_side"] = "RIGHT",
["config"] = {
["classBarNamePattern"] = "Warrior » Primary Bar",
["minWidth"] = 145,
},
["useAdjustededMax"] = false,
["sparkHeight"] = 18,
["actions"] = {
["start"] = {
},
["finish"] = {
["do_glow"] = false,
["do_sound"] = false,
["glow_action"] = "hide",
},
["init"] = {
["custom"] = "function aura_env:Init()\n    local ctx = self.region.arcCustomContext\n    if not ctx then\n        ctx = {}\n        self.region.arcCustomContext = ctx\n    end\n    \n    local classBar = self:GetClassBarName()\n    local parentRegion = WeakAuras.GetRegion(classBar)\n    if not parentRegion then\n        print(self.id, \"could not find WA:\", classBar)\n        return\n    end\n    \n    ctx.parentRegion = parentRegion\n    ctx.minWidth = self.config.minWidth\n    ctx.region = self.region\n    \n    if not ctx.hooked then\n        hooksecurefunc(ctx.parentRegion, \"SetWidth\", function(_, width)\n                ctx.region:SetRegionWidth(max(ctx.minWidth, width))\n        end)\n        ctx.hooked = true\n    end\nend\n\nfunction aura_env:GetClassBarName()\n    local classNames = {\"Warrior\", \"Paladin\", \"Hunter\", \"Rogue\", \"Priest\", \"Death Knight\",\n    \"Shaman\", \"Mage\", \"Warlock\", \"Monk\", \"Druid\", \"Demon Hunter\",\"Evoker\"}\n    local class = select(2, UnitClass(\"player\"))\n    for i, name in ipairs(classNames) do\n        if class == name:gsub(\" \", \"\"):upper() then\n            return self.config.classBarNamePattern:format(name)\n        end\n    end\nend\n\naura_env:Init()",
["do_custom"] = true,
},
},
["width"] = 145,
["borderBackdrop"] = "None",
["parent"] = "Warrior",
["id"] = "Prot Warrior: Shield Block Timer",
["sparkHidden"] = "BOTH",
["icon"] = false,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["customTextUpdate"] = "update",
["progressSource"] = {
-1,
"",
},
["inverse"] = false,
["sparkDesature"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["xOffset"] = 0,
},
["Warrior: Leap"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 6544,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Heroic Leap",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"375234",
},
["unit"] = "player",
["type"] = "aura2",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["glow"] = false,
["useGlowColor"] = false,
["glowScale"] = 1,
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["glowDuration"] = 1,
["type"] = "subglow",
["glowXOffset"] = 0,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -3,
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_never"] = false,
["spellknown"] = 6544,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "37EI)TeycQ4",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Leap",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["variable"] = "AND",
["checks"] = {
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
{
["trigger"] = 1,
["op"] = ">",
["value"] = "0",
["variable"] = "charges",
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "cooldownEdge",
},
{
["property"] = "cooldownSwipe",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["value"] = "0",
["variable"] = "charges",
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Warrior: Dragon Charge"] = {
["iconSource"] = -1,
["parent"] = "Warrior » PvP Bar",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["subeventPrefix"] = "SPELL",
["type"] = "spell",
["unit"] = "player",
["subeventSuffix"] = "_CAST_START",
["names"] = {
},
["duration"] = "1",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Dragon Charge",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["unevent"] = "auto",
["use_genericShowOn"] = true,
["use_track"] = true,
["spellName"] = 206572,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 263,
["multi"] = {
[73] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[334046] = true,
},
},
["class"] = {
["single"] = "SHAMAN",
["multi"] = {
["DEMONHUNTER"] = true,
["SHAMAN"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["use_class_and_spec"] = false,
["use_petbattle"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["use_never"] = false,
["pvptalent"] = {
},
["use_spec"] = false,
["use_exact_spellknown"] = false,
["spellknown"] = 206572,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28.7,
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["authorOptions"] = {
},
["anchorFrameParent"] = false,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Dragon Charge",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "0bWThjQFVZq",
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["cooldown"] = true,
["stickyDuration"] = false,
},
["Prot Warrior: Araz's Ritual Forge"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1232802",
},
["matchesShowOn"] = "showOnActive",
["names"] = {
"Aspect of the Eagle",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["useExactSpellId"] = false,
["ownOnly"] = true,
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["type"] = "aura2",
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["unit"] = "player",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["itemequiped"] = {
242402,
},
["faction"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Prot Warrior Buffs",
["progressSource"] = {
-1,
"",
},
["color"] = {
1,
1,
1,
1,
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Araz's Ritual Forge",
["alpha"] = 1,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "DscEFbWvDaG",
["inverse"] = false,
["icon"] = true,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Araz's Ritual Forge"] = {
["iconSource"] = -1,
["parent"] = "Fury Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["ownOnly"] = true,
["names"] = {
"Aspect of the Eagle",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["custom_hide"] = "timed",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["matchesShowOn"] = "showOnActive",
["useExactSpellId"] = false,
["auranames"] = {
"1232802",
},
["spellIds"] = {
},
["type"] = "aura2",
["subeventSuffix"] = "_CAST_START",
["combineMatches"] = "showLowest",
["unit"] = "player",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slidebottom",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["role"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["itemequiped"] = {
242402,
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["color"] = {
1,
1,
1,
1,
},
["progressSource"] = {
-1,
"",
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["selfPoint"] = "CENTER",
["authorOptions"] = {
},
["uid"] = "yeqmQs8BvSp",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Araz's Ritual Forge",
["frameStrata"] = 3,
["alpha"] = 1,
["width"] = 28,
["zoom"] = 0.3,
["config"] = {
},
["inverse"] = false,
["icon"] = true,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Sweeping Strikes Buff"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -79,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["duration"] = "1",
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"260708",
},
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["glowFrequency"] = 0.2,
["glow"] = true,
["useGlowColor"] = true,
["glowType"] = "Pixel",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["type"] = "subglow",
["glowThickness"] = 2,
["glowDuration"] = 1,
["glowXOffset"] = 0,
["glowScale"] = 0.8,
["glowLines"] = 4,
["glowBorder"] = true,
},
},
["height"] = 32,
["load"] = {
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
},
["talent"] = {
["single"] = 6,
["multi"] = {
[260708] = true,
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["ingroup"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["zoneIds"] = "",
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = -100.1,
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["parent"] = "Warrior » Emphasized Buffs",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 32,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Sweeping Strikes Buff",
["frameStrata"] = 3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "m9nXSiQyEMY",
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Spell Reflection Buff"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Remorseless Winter",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["auraspellids"] = {
},
["use_specific_unit"] = false,
["event"] = "Health",
["unit"] = "player",
["ownOnly"] = true,
["useName"] = true,
["spellIds"] = {
},
["auranames"] = {
"23920",
},
["subeventPrefix"] = "SPELL",
["combineMatches"] = "showLowest",
["useExactSpellId"] = false,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 34,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = true,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[581] = true,
},
},
["talent"] = {
["multi"] = {
[112864] = true,
[112253] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["covenant"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["use_petbattle"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
},
},
},
["alpha"] = 1,
["useAdjustededMax"] = false,
["desaturate"] = false,
["source"] = "import",
["actions"] = {
["start"] = {
["message_type"] = "SAY",
["do_message"] = true,
["message"] = "» REFLECT",
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 1129420,
["xOffset"] = 0,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["parent"] = "Prot Warrior Defensives",
["config"] = {
},
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 4, 0)\nend",
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Spell Reflection Buff",
["selfPoint"] = "CENTER",
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["uid"] = "4oKdKbpJYpY",
["inverse"] = false,
["progressSource"] = {
-1,
"",
},
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Rage Bar"] = {
["overlays"] = {
{
0,
0,
0,
0.6000000238418579,
},
{
0.4862745098039216,
0.4862745098039216,
0.4862745098039216,
1,
},
},
["iconSource"] = -1,
["authorOptions"] = {
{
["type"] = "input",
["useDesc"] = false,
["width"] = 1,
["key"] = "classBarNamePattern",
["default"] = "%s » Primary Bar",
["multiline"] = false,
["length"] = 10,
["name"] = "Class Bar Name Pattern",
["useLength"] = false,
},
{
["type"] = "number",
["default"] = 243,
["key"] = "minWidth",
["name"] = "Minimum Width",
["useDesc"] = false,
["width"] = 1,
},
},
["adjustedMax"] = "",
["yOffset"] = 28,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["icon"] = false,
["icon_color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["selfPoint"] = "CENTER",
["barColor"] = {
0.7803922295570374,
0.1372549086809158,
0.1843137294054031,
1,
},
["desaturate"] = false,
["sparkOffsetY"] = 0,
["gradientOrientation"] = "HORIZONTAL",
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = false,
["class_and_spec"] = {
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["class"] = {
["multi"] = {
},
},
["zoneIds"] = "",
},
["customAnchor"] = "function()\nreturn WeakAuras.GetRegion(aura_env:GetClassBarName())\nend",
["smoothProgress"] = false,
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["overlayclip"] = true,
["texture"] = "Atrocity",
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["auto"] = true,
["tocversion"] = 110200,
["alpha"] = 1,
["uid"] = "ORsHA3nCAe(",
["sparkOffsetX"] = 0,
["parent"] = "Warrior",
["adjustedMin"] = "",
["sparkRotationMode"] = "AUTO",
["triggers"] = {
{
["trigger"] = {
["use_absorbMode"] = true,
["genericShowOn"] = "showOnCooldown",
["use_unit"] = true,
["use_class"] = false,
["powertype"] = 1,
["names"] = {
},
["unit"] = "player",
["use_genericShowOn"] = true,
["use_powertype"] = true,
["spellName"] = 0,
["duration"] = "1",
["type"] = "unit",
["custom_type"] = "stateupdate",
["subeventSuffix"] = "_CAST_START",
["events"] = "UNIT_POWER_FREQUENT:player UNIT_SPELLCAST_START:player UNIT_SPELLCAST_STOP:player UNIT_DISPLAYPOWER:player UNIT_MAXPOWER:player UNIT_AURA:player PLAYER_SPECIALIZATION_CHANGED SPELLS_CHANGED",
["debuffType"] = "HELPFUL",
["event"] = "Power",
["unevent"] = "auto",
["realSpellName"] = 0,
["use_spellName"] = true,
["spellIds"] = {
},
["subeventPrefix"] = "SPELL",
["check"] = "event",
["class"] = "MONK",
["use_track"] = true,
["customVariables"] = "{\n    additionalProgress = 2,\n    value = true,\n    total = true,\n    percent = {\n        type = \"number\",\n        display = \"Percent\",\n    },\n    type = {\n        display = \"Power Type\",\n        type = \"select\",\n        values = {\n            [0] = \"Mana\", \n            [1] = \"Rage\", \n            [2] = \"Focus\",\n            [3] = \"Energy\",\n            [6] = \"Runic Power\",\n            [8] = \"Astral Power\",\n            [11] = \"Maelstrom\",\n            [13] = \"Insanity\",\n            [17] = \"Fury\",\n            [18] = \"Pain\",\n        },   \n    },\n}\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "unit",
["use_absorbHealMode"] = true,
["use_unit"] = true,
["unit"] = "vehicle",
["use_absorbMode"] = true,
["event"] = "Power",
["use_specific_unit"] = true,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["use_specId"] = true,
["type"] = "unit",
["use_absorbHealMode"] = true,
["use_genericShowOn"] = true,
["event"] = "Class/Spec",
["unit"] = "player",
["specId"] = {
["single"] = 72,
},
["genericShowOn"] = "showOnCooldown",
["use_absorbMode"] = true,
["use_spellName"] = true,
["use_unit"] = true,
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\n  return t[1] or t[2];\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "alphaPulse",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["type"] = "subborder",
["border_offset"] = 1,
["anchor_area"] = "bar",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text"] = "%p",
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["rotateText"] = "NONE",
["text_color"] = {
1,
1,
1,
1,
},
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_text_format_change_format"] = "none",
["text_fontSize"] = 18,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_n_format"] = "none",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_text_format_short_format"] = "none",
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["type"] = "subtext",
["text_anchorXOffset"] = 3,
["text_font"] = "Expressway",
["text_anchorYOffset"] = 3,
["text_text_format_1.percentpower_format"] = "none",
["text_fontType"] = "OUTLINE",
["text_text_format_percent_decimal_precision"] = 1,
["text_text_format_percent_format"] = "none",
["text_shadowXOffset"] = 0,
["anchor_point"] = "INNER_CENTER",
["text_text_format_p_time_format"] = 0,
["anchorXOffset"] = 0,
["text_text_format_p_time_mod_rate"] = true,
},
},
["height"] = 16,
["textureSource"] = "LSM",
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["source"] = "import",
["anchorFrameFrame"] = "WeakAuras:Global » ActionBar 1 Melee",
["preferToUpdate"] = false,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["icon_side"] = "RIGHT",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["custom"] = "function aura_env:Init()\n    local ctx = self.region.arcCustomContext\n    if not ctx then\n        ctx = {}\n        self.region.arcCustomContext = ctx\n    end\n    \n    local classBar = self:GetClassBarName()\n    local parentRegion = WeakAuras.GetRegion(classBar)\n    if not parentRegion then\n        print(self.id, \"could not find WA:\", classBar)\n        return\n    end\n    \n    ctx.parentRegion = parentRegion\n    ctx.minWidth = self.config.minWidth\n    ctx.region = self.region\n    \n    if not ctx.hooked then\n        hooksecurefunc(ctx.parentRegion, \"SetWidth\", function(_, width)\n                ctx.region:SetRegionWidth(max(ctx.minWidth, width))\n        end)\n        ctx.hooked = true\n    end\nend\n\nfunction aura_env:GetClassBarName()\n    local classNames = {\"Warrior\", \"Paladin\", \"Hunter\", \"Rogue\", \"Priest\", \"Death Knight\",\n    \"Shaman\", \"Mage\", \"Warlock\", \"Monk\", \"Druid\", \"Demon Hunter\",\"Evoker\"}\n    local class = select(2, UnitClass(\"player\"))\n    for i, name in ipairs(classNames) do\n        if class == name:gsub(\" \", \"\"):upper() then\n            return self.config.classBarNamePattern:format(name)\n        end\n    end\nend\n\naura_env:Init()",
["do_custom"] = true,
},
},
["sparkWidth"] = 5,
["sparkHeight"] = 21,
["customText"] = "\n\n",
["overlaysTexture"] = {
"Atrocity",
"Atrocity",
},
["config"] = {
["classBarNamePattern"] = "%s » Primary Bar",
["minWidth"] = 145,
},
["backgroundColor"] = {
0.2431372702121735,
0.2431372702121735,
0.2431372702121735,
1,
},
["sparkHidden"] = "BOTH",
["id"] = "Warrior: Rage Bar",
["width"] = 145,
["frameStrata"] = 3,
["anchorFrameType"] = "CUSTOM",
["spark"] = false,
["xOffset"] = 0,
["inverse"] = false,
["sparkColor"] = {
1,
1,
1,
1,
},
["orientation"] = "HORIZONTAL",
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["variable"] = "AND",
["checks"] = {
{
["trigger"] = 3,
["variable"] = "show",
["value"] = 1,
},
{
["trigger"] = 1,
["variable"] = "power",
["value"] = "80",
["op"] = ">=",
},
},
},
["changes"] = {
{
["value"] = {
0.0470588281750679,
1,
0,
1,
},
["property"] = "sub.4.text_color",
},
},
},
},
["barColor2"] = {
1,
1,
0,
1,
},
["zoom"] = 0,
},
["Prot Warrior: Ravager"] = {
["iconSource"] = -1,
["parent"] = "Warrior » Primary Bar",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["names"] = {
},
["type"] = "spell",
["unit"] = "player",
["unevent"] = "auto",
["subeventPrefix"] = "SPELL",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Thunderous Roar",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["subeventSuffix"] = "_CAST_START",
["duration"] = "1",
["use_track"] = true,
["spellName"] = 228920,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[68] = true,
[112304] = true,
},
},
["use_class_and_spec"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_talent"] = false,
["use_talent2"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["use_never"] = false,
["use_spec"] = true,
["spec"] = {
["single"] = 3,
["multi"] = {
true,
},
},
["talent2"] = {
["multi"] = {
[132880] = true,
},
},
["spellknown"] = 384318,
["size"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["keepAspectRatio"] = false,
["internalVersion"] = 86,
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["authorOptions"] = {
},
["config"] = {
},
["color"] = {
1,
1,
1,
1,
},
["width"] = 34,
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Ravager",
["useAdjustededMin"] = false,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["xOffset"] = 0,
["uid"] = "ZNiDOrtaxLf",
["inverse"] = true,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Sweeping Strikes"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 260708,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Sweeping Strikes",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[384361] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 71,
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Secondary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "QTobRdJ8kg3",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Sweeping Strikes",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 28.7,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Enraged Regeneration"] = {
["iconSource"] = -1,
["parent"] = "Warrior » Top Bar",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["type"] = "spell",
["names"] = {
},
["subeventSuffix"] = "_CAST_START",
["use_unit"] = true,
["duration"] = "1",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Enraged Regeneration",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["unevent"] = "auto",
["use_absorbMode"] = true,
["use_track"] = true,
["spellName"] = 184364,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["useName"] = true,
["useExactSpellId"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["auranames"] = {
"265144",
},
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[2]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["glow"] = false,
["glowDuration"] = 1,
["glowScale"] = 1,
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowType"] = "buttonOverlay",
["glowXOffset"] = 0,
["useGlowColor"] = false,
["type"] = "subglow",
["glowThickness"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 26,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
[112264] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[71] = true,
[72] = true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 26,
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["stickyDuration"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["selfPoint"] = "CENTER",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Enraged Regeneration",
["zoom"] = 0.3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "qwQDXmoIZPd",
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
["checks"] = {
{
["value"] = 1,
["variable"] = "onCooldown",
},
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Shattering Throw"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 64382,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Shattering Throw",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showOnCooldown",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 18,
["multi"] = {
[14] = true,
[18] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_class"] = true,
["use_spellknown"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["use_class_and_spec"] = false,
["use_never"] = false,
["spellknown"] = 64382,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "ynfvcblJOIy",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Shattering Throw",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078432083129883,
0.2352941334247589,
0.2313725650310516,
1,
},
["property"] = "color",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Battle-Scarred Veteran"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"386397",
},
["matchesShowOn"] = "showOnActive",
["names"] = {
"Remorseless Winter",
},
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
},
["useExactSpellId"] = false,
["unit"] = "player",
["event"] = "Health",
["subeventSuffix"] = "_CAST_START",
["use_specific_unit"] = false,
["ownOnly"] = true,
["spellIds"] = {
},
["useName"] = true,
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["subeventPrefix"] = "SPELL",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 34,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = true,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[581] = true,
},
},
["talent"] = {
["multi"] = {
[112864] = true,
[112307] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["covenant"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["difficulty"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["source"] = "import",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["conditions"] = {
},
["parent"] = "Prot Warrior Defensives",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["uid"] = "T4(EW)CvoAT",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 4, 0)\nend",
["width"] = 34,
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Battle-Scarred Veteran",
["stickyDuration"] = false,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = false,
["keepAspectRatio"] = false,
["displayIcon"] = 1129420,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Demoralizing Shout"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 1160,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Demoralizing Shout",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 3,
["multi"] = {
[386164] = true,
[112159] = true,
[394062] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 1160,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button3",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "GTAxu8jKvTT",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Demoralizing Shout",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Bladestorm"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 227847,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = true,
["realSpellName"] = "Bladestorm",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["type"] = "aura2",
["auranames"] = {
"445606",
},
["debuffType"] = "HELPFUL",
["useName"] = true,
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_precision"] = 1,
["text_text_format_s_format"] = "none",
["text_text"] = "%2.s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_format"] = "timed",
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_mod_rate"] = true,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_format"] = 0,
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = -5,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontType"] = "OUTLINE",
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["anchorXOffset"] = 0,
["text_text_format_p_time_legacy_floor"] = false,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 3,
["multi"] = {
[384361] = true,
[385512] = true,
[112314] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_talent"] = false,
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_class_and_spec"] = true,
["class_and_spec"] = {
["single"] = 71,
},
["talent2"] = {
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button3",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "ZMDK)cdecIW",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Bladestorm",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Rend"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -113,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"772",
},
["matchesShowOn"] = "showAlways",
["genericShowOn"] = "showOnCooldown",
["unit"] = "target",
["debuffType"] = "HARMFUL",
["useName"] = true,
["spellName"] = 5308,
["subeventSuffix"] = "_CAST_START",
["names"] = {
},
["ownOnly"] = true,
["event"] = "Spell Activation Overlay",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["type"] = "aura2",
["subeventPrefix"] = "SPELL",
["use_genericShowOn"] = true,
["use_track"] = true,
["use_targetRequired"] = true,
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.2,
["type"] = "subglow",
["glowXOffset"] = 0,
["glowType"] = "Pixel",
["glowThickness"] = 2,
["glowYOffset"] = 0,
["glowColor"] = {
0.73725490196078,
0.12549019607843,
0.035294117647059,
1,
},
["glowLength"] = 12,
["glow"] = false,
["glowDuration"] = 1,
["useGlowColor"] = true,
["glowScale"] = 1,
["glowLines"] = 4,
["glowBorder"] = true,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[112136] = true,
},
},
["use_class_and_spec"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["talent_extraOption"] = 0,
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
[2] = true,
[3] = true,
},
},
["use_spec"] = true,
["covenant"] = {
["single"] = 2,
["multi"] = {
["1"] = true,
["4"] = true,
["3"] = true,
["0"] = true,
},
},
["use_combat"] = true,
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["preferToUpdate"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "buffed",
["value"] = 0,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "<=",
["value"] = "4.5",
["variable"] = "expirationTime",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["progressSource"] = {
-1,
"",
},
["xOffset"] = 0,
["uid"] = "eHd6luqHWnf",
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Rend",
["alpha"] = 1,
["frameStrata"] = 3,
["width"] = 34,
["parent"] = "Warrior » Emphasized Buffs",
["config"] = {
},
["inverse"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "alphaPulse",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["displayIcon"] = "135358",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["stickyDuration"] = false,
},
["Prot Warrior: Astral Antenna Orb"] = {
["iconSource"] = 0,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1239640",
},
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useName"] = false,
["use_debuffClass"] = false,
["useExactSpellId"] = true,
["buffShowOn"] = "showOnActive",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Aspect of the Eagle",
},
["ownOnly"] = true,
["type"] = "aura2",
["spellIds"] = {
},
["useGroup_count"] = false,
["unit"] = "player",
["combineMatches"] = "showLowest",
["auraspellids"] = {
"1239640",
},
["subeventSuffix"] = "_CAST_START",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["use_class_and_spec"] = true,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["itemequiped"] = {
242395,
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 332402,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["parent"] = "Prot Warrior Buffs",
["config"] = {
},
["xOffset"] = 0,
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Astral Antenna Orb",
["cooldownTextDisabled"] = false,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["desaturate"] = false,
["uid"] = "d(2Ombdc8Wp",
["inverse"] = false,
["keepAspectRatio"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Swing Timer"] = {
["sparkWidth"] = 5,
["iconSource"] = -1,
["authorOptions"] = {
{
["type"] = "input",
["useDesc"] = false,
["width"] = 1,
["key"] = "classBarNamePattern",
["name"] = "Class Bar Name Pattern",
["multiline"] = false,
["length"] = 10,
["default"] = "Warrior » Primary Bar",
["useLength"] = false,
},
{
["type"] = "number",
["key"] = "minWidth",
["default"] = 243,
["name"] = "Minimum Width",
["useDesc"] = false,
["width"] = 1,
},
},
["adjustedMax"] = "",
["yOffset"] = -170,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["backgroundColor"] = {
0.2431372702121735,
0.2431372702121735,
0.2431372702121735,
1,
},
["fontFlags"] = "OUTLINE",
["icon_color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["selfPoint"] = "CENTER",
["barColor"] = {
0.4862745404243469,
0.4862745404243469,
0.4862745404243469,
1,
},
["desaturate"] = false,
["sparkOffsetY"] = 0,
["gradientOrientation"] = "HORIZONTAL",
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["use_class_and_spec"] = true,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
},
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["MONK"] = true,
["ROGUE"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["smoothProgress"] = false,
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["texture"] = "Atrocity",
["zoom"] = 0,
["auto"] = true,
["tocversion"] = 110200,
["alpha"] = 1,
["sparkColor"] = {
1,
0.9921568627451,
0.9921568627451,
1,
},
["sparkOffsetX"] = 0,
["color"] = {
},
["adjustedMin"] = "",
["sparkRotationMode"] = "AUTO",
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"772",
},
["duration"] = "1",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["use_hand"] = true,
["unit"] = "target",
["use_unit"] = true,
["hand"] = "main",
["debuffType"] = "HARMFUL",
["matchesShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "auto",
["use_powertype"] = true,
["buffShowOn"] = "showOnActive",
["event"] = "Swing Timer",
["subeventSuffix"] = "_CAST_START",
["type"] = "unit",
["names"] = {
"Стойкость к боли",
},
["spellIds"] = {
190456,
},
["ownOnly"] = true,
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["custom_hide"] = "timed",
["powertype"] = 3,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "spell",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["unit"] = "player",
["realSpellName"] = "Mortal Strike",
["use_spellName"] = true,
["debuffType"] = "HELPFUL",
["event"] = "Cooldown Progress (Spell)",
["use_track"] = true,
["spellName"] = 12294,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "unit",
["use_hostility"] = true,
["use_absorbMode"] = true,
["event"] = "Unit Characteristics",
["hostility"] = "hostile",
["use_unit"] = true,
["use_absorbHealMode"] = true,
["unit"] = "target",
["use_attackable"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "unit",
["use_absorbHealMode"] = true,
["use_incombat"] = true,
["unit"] = "player",
["use_absorbMode"] = true,
["event"] = "Conditions",
["use_unit"] = true,
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\n    return t[3] and t[4] and (t[1] or t[2])\nend",
["activeTriggerMode"] = 1,
},
["internalVersion"] = 86,
["useAdjustedMin"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["backdropInFront"] = false,
["sparkMirror"] = false,
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["anchor_area"] = "bar",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 12,
["textureSource"] = "LSM",
["sparkBlendMode"] = "ADD",
["backdropColor"] = {
1,
1,
1,
0,
},
["source"] = "import",
["preferToUpdate"] = false,
["barColor2"] = {
1,
1,
0,
1,
},
["useAdjustedMax"] = false,
["spark"] = false,
["anchorFrameFrame"] = "WeakAuras:Class » Warrior » Primary Bar",
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["borderInFront"] = true,
["uid"] = "gfXWFb974tX",
["icon_side"] = "RIGHT",
["config"] = {
["classBarNamePattern"] = "Warrior » Primary Bar",
["minWidth"] = 145,
},
["useAdjustededMax"] = false,
["sparkHeight"] = 10,
["actions"] = {
["start"] = {
},
["finish"] = {
["do_glow"] = false,
["do_sound"] = false,
["glow_action"] = "hide",
},
["init"] = {
["custom"] = "function aura_env:Init()\n    local ctx = self.region.arcCustomContext\n    if not ctx then\n        ctx = {}\n        self.region.arcCustomContext = ctx\n    end\n    \n    local classBar = self:GetClassBarName()\n    local parentRegion = WeakAuras.GetRegion(classBar)\n    if not parentRegion then\n        print(self.id, \"could not find WA:\", classBar)\n        return\n    end\n    \n    ctx.parentRegion = parentRegion\n    ctx.minWidth = self.config.minWidth\n    ctx.region = self.region\n    \n    if not ctx.hooked then\n        hooksecurefunc(ctx.parentRegion, \"SetWidth\", function(_, width)\n                ctx.region:SetRegionWidth(max(ctx.minWidth, width))\n        end)\n        ctx.hooked = true\n    end\nend\n\nfunction aura_env:GetClassBarName()\n    local classNames = {\"Warrior\", \"Paladin\", \"Hunter\", \"Rogue\", \"Priest\", \"Death Knight\",\n    \"Shaman\", \"Mage\", \"Warlock\", \"Monk\", \"Druid\", \"Demon Hunter\",\"Evoker\"}\n    local class = select(2, UnitClass(\"player\"))\n    for i, name in ipairs(classNames) do\n        if class == name:gsub(\" \", \"\"):upper() then\n            return self.config.classBarNamePattern:format(name)\n        end\n    end\nend\n\naura_env:Init()",
["do_custom"] = true,
},
},
["width"] = 145,
["borderBackdrop"] = "None",
["parent"] = "Warrior",
["id"] = "Arms Warrior: Swing Timer",
["sparkHidden"] = "BOTH",
["icon"] = false,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["customTextUpdate"] = "update",
["progressSource"] = {
-1,
"",
},
["inverse"] = true,
["sparkDesature"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["variable"] = "OR",
["checks"] = {
{
["trigger"] = 1,
["variable"] = "show",
["value"] = 0,
},
{
["trigger"] = 2,
["variable"] = "spellInRange",
["value"] = 0,
},
},
},
["changes"] = {
{
["value"] = {
0.78039215686275,
0.13725490196078,
0.1843137254902,
1,
},
["property"] = "barColor",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["xOffset"] = 0,
},
["Fury Warrior: Whirlwind Stacks - Voz"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["customText"] = "function()\n    return (aura_env.whirlwindStacks and aura_env.whirlwindStacks > 0) and aura_env.whirlwindStacks or \"\"\nend",
["yOffset"] = -76,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["cooldownEdge"] = true,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["type"] = "custom",
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["unit"] = "player",
["names"] = {
},
["events"] = "UNIT_SPELLCAST_SUCCEEDED:player,CLEU:SPELL_AURA_APPLIED,CLEU:SPELL_AURA_APPLIED_DOSE,CLEU:SPELL_AURA_REFRESH,CLEU:SPELL_AURA_REMOVED,CLEU:SPELL_AURA_REMOVED_DOSE",
["spellIds"] = {
},
["subeventPrefix"] = "SPELL",
["custom_type"] = "stateupdate",
["custom"] = "--TSU\n--UNIT_SPELLCAST_SUCCEEDED:player,CLEU:SPELL_AURA_APPLIED,CLEU:SPELL_AURA_APPLIED_DOSE,CLEU:SPELL_AURA_REFRESH,CLEU:SPELL_AURA_REMOVED,CLEU:SPELL_AURA_REMOVED_DOSE\nfunction(states, event, ...)\n    if event == \"OPTIONS\" then\n        return false\n    end\n    if event == \"STATUS\" then\n        return false\n    end\n    \n    local whirlwindBuffId = 85739\n    local rampageId = 184367\n    \n    local function Show(offsetStacks)\n        local whirlwindAura = C_UnitAuras.GetPlayerAuraBySpellID(whirlwindBuffId)\n        local stacks = (whirlwindAura and whirlwindAura.applications or 0) + (offsetStacks or 0)\n        aura_env.whirlwindStacks = stacks\n        states[rampageId] = {\n            show = stacks > 0,\n            changed = true,\n            progressType = \"static\",\n            stacks = stacks,\n            value = stacks,\n        }\n    end\n    \n    if event == \"UNIT_SPELLCAST_SUCCEEDED\" then\n        local _, _, spellID = ...\n        if spellID == rampageId then\n            Show(-1)\n        end\n    elseif event == \"COMBAT_LOG_EVENT_UNFILTERED\" then\n        local _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, spellID = ...\n        if spellID == whirlwindBuffId and sourceGUID == UnitGUID(\"player\") then\n            if subEvent == \"SPELL_AURA_APPLIED\" then\n                Show()\n            elseif subEvent == \"SPELL_AURA_APPLIED_DOSE\" then\n                Show()\n            elseif subEvent == \"SPELL_AURA_REFRESH\" then\n                Show()\n            elseif subEvent == \"SPELL_AURA_REMOVED\" then\n                Show()\n            elseif subEvent == \"SPELL_AURA_REMOVED_DOSE\" then\n                Show()\n            end\n        end\n    end\n    \n    return true\nend",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["version"] = 1,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%c",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_c_format"] = "none",
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_anchorXOffset"] = 0,
["text_text_format_1.charges_format"] = "none",
["text_font"] = "Expressway",
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = 0,
["text_visible"] = true,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_color"] = {
0,
1,
0.3137255012989044,
1,
},
["text_text_format_2.stacks_format"] = "none",
["anchor_point"] = "CENTER",
["text_fontSize"] = 20,
["anchorXOffset"] = 0,
["anchorYOffset"] = 0,
},
{
["border_size"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = true,
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
0,
0.05882353335618973,
1,
},
["glowDuration"] = 1,
["glowXOffset"] = 0,
["glowLength"] = 10,
["glow"] = false,
["glowScale"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
},
["height"] = 34,
["load"] = {
["use_never"] = false,
["class_and_spec"] = {
["single"] = 72,
},
["talent"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["progressSource"] = {
-1,
"",
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["displayIcon"] = 132369,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["preferToUpdate"] = false,
["config"] = {
},
["alpha"] = 1,
["parent"] = "Warrior » Emphasized Buffs",
["cooldownTextDisabled"] = false,
["semver"] = "1.0.0",
["tocversion"] = 110200,
["id"] = "Fury Warrior: Whirlwind Stacks - Voz",
["zoom"] = 0.3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["uid"] = "6ZwUaDAOuOn",
["inverse"] = false,
["adjustedMin"] = "",
["conditions"] = {
},
["cooldown"] = false,
["xOffset"] = 0,
},
["Warrior: Duel"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 236273,
["type"] = "spell",
["names"] = {
},
["subeventSuffix"] = "_CAST_START",
["duration"] = "1",
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Duel",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["use_unit"] = true,
["use_track"] = true,
["unit"] = "player",
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[334046] = true,
},
},
["use_class_and_spec"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["class"] = {
["single"] = "SHAMAN",
["multi"] = {
["SHAMAN"] = true,
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class_and_spec"] = {
["single"] = 263,
["multi"] = {
[71] = true,
},
},
["pvptalent"] = {
},
["use_spec"] = false,
["use_exact_spellknown"] = false,
["spellknown"] = 236273,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["icon"] = true,
["uid"] = "XmDMv3KptU5",
["xOffset"] = 0,
["anchorFrameParent"] = false,
["alpha"] = 1,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Duel",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["width"] = 28.7,
["parent"] = "Warrior » PvP Bar",
["config"] = {
},
["inverse"] = true,
["authorOptions"] = {
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Fury Warrior: Execute (Massacre)"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -113,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["unit"] = "target",
["subeventPrefix"] = "SPELL",
["percenthealth_operator"] = {
"<=",
},
["use_absorbMode"] = true,
["names"] = {
},
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["use_charges"] = false,
["type"] = "unit",
["use_absorbHealMode"] = true,
["subeventSuffix"] = "_CAST_START",
["use_spellCount"] = false,
["percenthealth"] = {
"35",
},
["event"] = "Health",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["use_targetRequired"] = true,
["spellName"] = 163201,
["use_percenthealth"] = true,
["use_track"] = true,
["use_unit"] = true,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["unit"] = "player",
["use_spellName"] = true,
["debuffType"] = "HELPFUL",
["genericShowOn"] = "showAlways",
["use_exact_spellName"] = false,
["use_track"] = true,
["spellName"] = 5308,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["unit"] = "player",
["use_spellName"] = true,
["spellName"] = 5308,
["genericShowOn"] = "showOnCooldown",
["use_exact_spellName"] = false,
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[3];\nend",
["activeTriggerMode"] = 2,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "alphaPulse",
["duration_type"] = "seconds",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 34,
["load"] = {
["use_covenant"] = false,
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[112145] = false,
[112279] = true,
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["talent_extraOption"] = 0,
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["use_class_and_spec"] = true,
["use_spec"] = true,
["covenant"] = {
["single"] = 2,
["multi"] = {
["1"] = true,
["4"] = true,
["3"] = true,
["0"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
[2] = true,
[3] = true,
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[71] = true,
},
},
["zoneIds"] = "",
},
["useAdjustededMax"] = false,
["width"] = 34,
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["preferToUpdate"] = false,
["stickyDuration"] = false,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["displayIcon"] = "135358",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["authorOptions"] = {
},
["config"] = {
},
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Execute (Massacre)",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["parent"] = "Warrior » Emphasized Buffs",
["uid"] = "DOsfNBghwVY",
["inverse"] = true,
["keepAspectRatio"] = false,
["conditions"] = {
{
["check"] = {
["trigger"] = 2,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["op"] = "<",
["checks"] = {
{
["value"] = 0,
["op"] = "<",
["variable"] = "show",
},
{
["value"] = 0,
["variable"] = "show",
},
},
["trigger"] = 2,
["variable"] = "insufficientResources",
["value"] = 1,
},
["linked"] = false,
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
},
},
},
["cooldown"] = true,
["selfPoint"] = "CENTER",
},
["Prot Warrior: Shield Charge"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 385952,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Shield Charge",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["multi"] = {
[386034] = true,
[112173] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 385952,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "aaQTKsmMrrW",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Shield Charge",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078432083129883,
0.2352941334247589,
0.2313725650310516,
1,
},
["property"] = "color",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Recklessness Buff"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1719",
},
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112228] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["progressSource"] = {
-1,
"",
},
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["desaturate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["authorOptions"] = {
},
["uid"] = ")WJEpHy31gV",
["adjustedMin"] = "",
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Recklessness Buff",
["frameStrata"] = 3,
["alpha"] = 1,
["width"] = 28,
["parent"] = "Arms Warrior Buffs",
["config"] = {
},
["inverse"] = false,
["color"] = {
1,
1,
1,
1,
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Racials"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["unit"] = "player",
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["names"] = {
"Overwhelming Power",
},
["event"] = "Health",
["unevent"] = "timed",
["subeventPrefix"] = "SPELL",
["useName"] = true,
["spellIds"] = {
},
["auranames"] = {
"26297",
"33697",
"273104",
"274740",
"274742",
"274739",
"274741",
"20572",
},
["ownOnly"] = true,
["combineMatches"] = "showLowest",
["matchesShowOn"] = "showOnActive",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_precision"] = 1,
["text_text"] = "H",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorYOffset"] = 0,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
0,
1,
0,
1,
},
["text_font"] = "Expressway",
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_text_format_p_time_format"] = 0,
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_mod_rate"] = true,
},
},
["height"] = 28,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[257] = true,
[256] = true,
},
},
["talent"] = {
["single"] = 7,
["multi"] = {
[7] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["talent2"] = {
["multi"] = {
},
},
["race"] = {
["single"] = "Troll",
["multi"] = {
["Troll"] = true,
["Orc"] = true,
["DarkIronDwarf"] = true,
["MagharOrc"] = true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["use_race"] = false,
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["preferToUpdate"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["stickyDuration"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["progressSource"] = {
-1,
"",
},
["uid"] = "dGdb68E59PY",
["parent"] = "Arms Warrior Buffs",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["adjustedMin"] = "",
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Racials",
["zoom"] = 0.3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["alpha"] = 1,
["config"] = {
},
["inverse"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "fade",
["easeStrength"] = 3,
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "slideright",
["easeStrength"] = 3,
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["value"] = "274740",
["variable"] = "spellId",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274742",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "V",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274739",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "C",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274741",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "M",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["color"] = {
1,
1,
1,
1,
},
},
["Prot Warrior: Racials"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["unit"] = "player",
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["names"] = {
"Overwhelming Power",
},
["event"] = "Health",
["unevent"] = "timed",
["subeventPrefix"] = "SPELL",
["useName"] = true,
["spellIds"] = {
},
["auranames"] = {
"26297",
"33697",
"273104",
"274740",
"274742",
"274739",
"274741",
"20572",
},
["ownOnly"] = true,
["combineMatches"] = "showLowest",
["matchesShowOn"] = "showOnActive",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_precision"] = 1,
["text_text"] = "H",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorYOffset"] = 0,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
0,
1,
0,
1,
},
["text_font"] = "Expressway",
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_text_format_p_time_format"] = 0,
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_mod_rate"] = true,
},
},
["height"] = 28,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[257] = true,
[256] = true,
},
},
["talent"] = {
["single"] = 7,
["multi"] = {
[7] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["talent2"] = {
["multi"] = {
},
},
["race"] = {
["single"] = "Troll",
["multi"] = {
["Troll"] = true,
["Orc"] = true,
["DarkIronDwarf"] = true,
["MagharOrc"] = true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["use_race"] = false,
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["preferToUpdate"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["stickyDuration"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["progressSource"] = {
-1,
"",
},
["uid"] = "fLT71aH43xk",
["parent"] = "Prot Warrior Buffs",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["adjustedMin"] = "",
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Racials",
["zoom"] = 0.3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["alpha"] = 1,
["config"] = {
},
["inverse"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "fade",
["easeStrength"] = 3,
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "slideright",
["easeStrength"] = 3,
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["value"] = "274740",
["variable"] = "spellId",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274742",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "V",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274739",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "C",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274741",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "M",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["color"] = {
1,
1,
1,
1,
},
},
["Prot Warrior: Champion's Might"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["rem"] = "0",
["auranames"] = {
"311193",
},
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["duration"] = "1",
["unit"] = "target",
["ownOnly"] = true,
["custom_hide"] = "timed",
["useExactSpellId"] = true,
["useName"] = false,
["use_debuffClass"] = false,
["auraspellids"] = {
"376080",
},
["type"] = "aura2",
["unevent"] = "timed",
["event"] = "Health",
["buffShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["subeventSuffix"] = "_CAST_START",
["spellIds"] = {
},
["useGroup_count"] = false,
["remOperator"] = ">",
["combineMatches"] = "showLowest",
["debuffType"] = "HARMFUL",
["useRem"] = false,
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = 1,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.2,
["glow"] = true,
["useGlowColor"] = true,
["glowType"] = "Pixel",
["glowLength"] = 8,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["type"] = "subglow",
["glowThickness"] = 1,
["glowDuration"] = 1,
["glowXOffset"] = 0,
["glowScale"] = 1,
["glowLines"] = 4,
["glowBorder"] = true,
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112180] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["item_bonusid_equipped"] = "",
["use_item_bonusid_equipped"] = false,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["source"] = "import",
["progressSource"] = {
-1,
"",
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 3565453,
["parent"] = "Prot Warrior Buffs",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["config"] = {
},
["authorOptions"] = {
},
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["desaturate"] = false,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Champion's Might",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 28,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["uid"] = "zhgd9uKRxGy",
["inverse"] = false,
["adjustedMin"] = "",
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Bladestorm"] = {
["iconSource"] = -1,
["parent"] = "Warrior » Primary Bar",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["type"] = "spell",
["names"] = {
},
["subeventSuffix"] = "_CAST_START",
["use_unit"] = true,
["duration"] = "1",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Ravager",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["unevent"] = "auto",
["use_absorbMode"] = true,
["use_track"] = true,
["spellName"] = 227847,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%2.s",
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_format"] = "timed",
["text_text_format_p_time_dynamic_threshold"] = 60,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_anchorYOffset"] = -5,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontType"] = "OUTLINE",
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["anchorXOffset"] = 0,
["text_text_format_p_time_format"] = 0,
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[72] = true,
},
},
["talent"] = {
["multi"] = {
[119139] = true,
[386034] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["use_petbattle"] = false,
["use_never"] = false,
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 228920,
["size"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["config"] = {
},
["authorOptions"] = {
},
["width"] = 34,
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Bladestorm",
["progressSource"] = {
-1,
"",
},
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["xOffset"] = 0,
["uid"] = "3OeNiBrlpJ4",
["inverse"] = true,
["selfPoint"] = "CENTER",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Stance"] = {
["outline"] = "OUTLINE",
["xOffset"] = 0,
["displayText"] = "Switch Stance",
["yOffset"] = 80,
["anchorPoint"] = "CENTER",
["displayText_format_p_time_format"] = 0,
["customTextUpdate"] = "event",
["automaticWidth"] = "Auto",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"386164",
},
["use_genericShowOn"] = true,
["genericShowOn"] = "showOnCooldown",
["use_unit"] = true,
["spellName"] = 97744,
["debuffType"] = "HELPFUL",
["useName"] = true,
["subeventPrefix"] = "SPELL",
["unevent"] = "auto",
["matchesShowOn"] = "showOnActive",
["use_absorbMode"] = true,
["event"] = "Cooldown Progress (Spell)",
["type"] = "aura2",
["realSpellName"] = "See Quest Invis 4",
["use_spellName"] = true,
["spellIds"] = {
},
["unit"] = "player",
["subeventSuffix"] = "_CAST_START",
["duration"] = "1",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showOnCooldown",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t) \nreturn t[1] and t[2] \nend",
["activeTriggerMode"] = -10,
},
["displayText_format_p_format"] = "timed",
["displayText_format_p_time_legacy_floor"] = true,
["wordWrap"] = "WordWrap",
["font"] = "Expressway",
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["load"] = {
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
},
["talent"] = {
["multi"] = {
[102004] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["size"] = {
["multi"] = {
["party"] = true,
["ten"] = true,
["twentyfive"] = true,
["twenty"] = true,
["fortyman"] = true,
},
},
["use_class_and_spec"] = true,
["ingroup"] = {
["multi"] = {
["raid"] = true,
},
},
["class"] = {
["single"] = "PRIEST",
["multi"] = {
["PRIEST"] = true,
},
},
["zoneIds"] = "",
},
["displayText_format_s_format"] = "none",
["fontSize"] = 18,
["source"] = "import",
["shadowXOffset"] = 1,
["selfPoint"] = "CENTER",
["anchorFrameFrame"] = "ElvUF_Player",
["regionType"] = "text",
["preferToUpdate"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
},
["displayText_format_p_time_precision"] = 1,
["displayText_format_p_time_dynamic_threshold"] = 3,
["displayText_format_p_time_mod_rate"] = true,
["config"] = {
},
["justify"] = "CENTER",
["tocversion"] = 110200,
["id"] = "Prot Warrior: Stance",
["parent"] = "Warrior",
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["color"] = {
0.9137255549430847,
0.1647058874368668,
0.1490196138620377,
1,
},
["uid"] = "UkiugSCjQkI",
["authorOptions"] = {
},
["shadowYOffset"] = -1,
["shadowColor"] = {
0,
0,
0,
0,
},
["fixedWidth"] = 98,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["internalVersion"] = 86,
},
["Arms Warrior: Demolish"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["type"] = "spell",
["names"] = {
},
["subeventSuffix"] = "_CAST_START",
["use_unit"] = true,
["duration"] = "1",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Sweeping Strikes",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["unevent"] = "auto",
["use_absorbMode"] = true,
["use_track"] = true,
["spellName"] = 436358,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"440989",
},
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%2.s",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_format"] = "timed",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = -5,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontType"] = "OUTLINE",
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["anchorXOffset"] = 0,
["text_text_format_p_time_legacy_floor"] = false,
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[384361] = true,
},
},
["use_class_and_spec"] = true,
["use_herotalent"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["herotalent"] = {
["multi"] = {
[117415] = true,
},
},
["class_and_spec"] = {
["single"] = 71,
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
},
["alpha"] = 1,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["parent"] = "Warrior » Primary Bar",
["config"] = {
},
["xOffset"] = 0,
["width"] = 34,
["anchorFrameParent"] = false,
["useAdjustededMin"] = false,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Demolish",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "wscRmNR3iXO",
["inverse"] = true,
["selfPoint"] = "CENTER",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078432083129883,
0.2352941334247589,
0.2313725650310516,
1,
},
["property"] = "color",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Current Stance"] = {
["iconSource"] = -1,
["parent"] = "Warrior",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 50,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["type"] = "aura2",
["useExactSpellId"] = true,
["matchesShowOn"] = "showOnActive",
["event"] = "Health",
["names"] = {
},
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["auraspellids"] = {
"386208",
},
["subeventPrefix"] = "SPELL",
["unit"] = "player",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "aura2",
["useExactSpellId"] = true,
["matchesShowOn"] = "showOnMissing",
["event"] = "Health",
["names"] = {
},
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["auraspellids"] = {
"386164",
"386196",
"386208",
},
["subeventPrefix"] = "SPELL",
["unit"] = "player",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_absorbHealMode"] = true,
["use_absorbMode"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_unit"] = true,
["realSpellName"] = "Battle Stance",
["use_spellName"] = true,
["debuffType"] = "HELPFUL",
["genericShowOn"] = "showOnCooldown",
["use_genericShowOn"] = true,
["unit"] = "player",
["use_track"] = true,
["spellName"] = 386164,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_absorbHealMode"] = true,
["use_absorbMode"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_unit"] = true,
["realSpellName"] = "Battle Stance",
["use_spellName"] = true,
["spellName"] = 386196,
["genericShowOn"] = "showOnCooldown",
["use_genericShowOn"] = true,
["unit"] = "player",
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[2]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text"] = "%3.p",
["text_text_format_3.p_time_format"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["rotateText"] = "NONE",
["text_color"] = {
1,
0.2000000178813934,
0.2000000178813934,
1,
},
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontSize"] = 16,
["anchorXOffset"] = 0,
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["text_text_format_3.p_time_precision"] = 1,
["type"] = "subtext",
["text_anchorXOffset"] = 0,
["text_font"] = "Expressway",
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_3.p_time_mod_rate"] = true,
["text_text_format_3.p_time_dynamic_threshold"] = 0,
["text_text_format_p_time_format"] = 0,
["text_text_format_p_time_precision"] = 1,
["text_text_format_3.p_format"] = "timed",
["text_text_format_3.p_time_legacy_floor"] = false,
["anchor_point"] = "CENTER",
["text_anchorYOffset"] = 1,
["text_text_format_p_time_dynamic_threshold"] = 0,
["text_fontType"] = "OUTLINE",
},
{
["text_text_format_p_time_format"] = 0,
["text_text"] = "%4.p",
["text_text_format_3.p_time_format"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_fixedWidth"] = 64,
["text_text_format_4.p_time_mod_rate"] = true,
["text_text_format_p_time_legacy_floor"] = false,
["rotateText"] = "NONE",
["text_color"] = {
1,
0.2000000178813934,
0.2000000178813934,
1,
},
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontSize"] = 16,
["anchorXOffset"] = 0,
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fontType"] = "OUTLINE",
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["text_text_format_3.p_time_precision"] = 1,
["text_text_format_p_time_dynamic_threshold"] = 0,
["text_text_format_4.p_format"] = "timed",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 0,
["text_text_format_4.p_time_format"] = 0,
["text_font"] = "Expressway",
["text_anchorYOffset"] = 1,
["text_text_format_3.p_time_mod_rate"] = true,
["text_text_format_4.p_time_dynamic_threshold"] = 0,
["text_text_format_p_time_precision"] = 1,
["text_text_format_3.p_time_dynamic_threshold"] = 3,
["text_text_format_3.p_format"] = "timed",
["text_text_format_4.p_time_legacy_floor"] = false,
["anchor_point"] = "CENTER",
["text_text_format_4.p_time_precision"] = 1,
["text_text_format_3.p_time_legacy_floor"] = false,
["text_text_format_p_time_mod_rate"] = true,
},
},
["height"] = 36,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[71] = true,
[72] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["useAdjustededMin"] = false,
["icon"] = true,
["cooldown"] = true,
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["desaturate"] = false,
["selfPoint"] = "CENTER",
["xOffset"] = 0,
["uid"] = "PS)WoSO280y",
["frameStrata"] = 3,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Current Stance",
["zoom"] = 0.3,
["useCooldownModRate"] = true,
["width"] = 36,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["keepAspectRatio"] = false,
["conditions"] = {
{
["check"] = {
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Skullsplitter"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 260643,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Skullsplitter",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["multi"] = {
[385512] = true,
[112133] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 71,
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 260643,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button3",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "LrRa7lrd(wb",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Skullsplitter",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Death Wish"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 199261,
["type"] = "spell",
["unit"] = "player",
["unevent"] = "auto",
["use_genericShowOn"] = true,
["subeventSuffix"] = "_CAST_START",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Death Wish",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_absorbMode"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[334046] = true,
},
},
["use_class_and_spec"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["class"] = {
["single"] = "SHAMAN",
["multi"] = {
["SHAMAN"] = true,
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class_and_spec"] = {
["single"] = 263,
["multi"] = {
[72] = true,
},
},
["pvptalent"] = {
},
["use_spec"] = false,
["use_exact_spellknown"] = false,
["spellknown"] = 199261,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["icon"] = true,
["uid"] = "L0ikEVjEM1L",
["authorOptions"] = {
},
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Death Wish",
["alpha"] = 1,
["frameStrata"] = 3,
["width"] = 28.7,
["xOffset"] = 0,
["config"] = {
},
["inverse"] = true,
["parent"] = "Warrior » PvP Bar",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Warrior: Bodyguard"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 213871,
["type"] = "spell",
["names"] = {
},
["subeventSuffix"] = "_CAST_START",
["use_genericShowOn"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Bodyguard",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_absorbMode"] = true,
["use_unit"] = true,
["use_track"] = true,
["unit"] = "player",
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[334046] = true,
},
},
["use_class_and_spec"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["class"] = {
["single"] = "SHAMAN",
["multi"] = {
["SHAMAN"] = true,
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class_and_spec"] = {
["single"] = 263,
["multi"] = {
[73] = true,
},
},
["pvptalent"] = {
},
["use_spec"] = false,
["use_exact_spellknown"] = false,
["spellknown"] = 213871,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "NFXx6I2HyzA",
["parent"] = "Warrior » PvP Bar",
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Bodyguard",
["alpha"] = 1,
["frameStrata"] = 3,
["width"] = 28.7,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Astral Antenna Buff"] = {
["iconSource"] = 0,
["parent"] = "Prot Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = false,
["use_debuffClass"] = false,
["auraspellids"] = {
"1239641",
},
["custom_hide"] = "timed",
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["ownOnly"] = true,
["unit"] = "player",
["auranames"] = {
"1239641",
},
["spellIds"] = {
},
["type"] = "aura2",
["useExactSpellId"] = true,
["combineMatches"] = "showLowest",
["names"] = {
"Aspect of the Eagle",
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowYOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -3,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_format"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["race"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["itemequiped"] = {
242395,
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slidebottom",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["color"] = {
1,
1,
1,
1,
},
["cooldown"] = true,
["displayIcon"] = "7137575",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["preferToUpdate"] = false,
["uid"] = "sGd6NrkeK31",
["xOffset"] = 0,
["anchorFrameParent"] = false,
["alpha"] = 1,
["stickyDuration"] = false,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Astral Antenna Buff",
["zoom"] = 0.3,
["useCooldownModRate"] = true,
["width"] = 28,
["frameStrata"] = 3,
["config"] = {
},
["inverse"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["progressSource"] = {
-1,
"",
},
},
["Prot Warrior: Taunt"] = {
["iconSource"] = -1,
["parent"] = "Warrior » Secondary Bar",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["buffShowOn"] = "showOnActive",
["type"] = "spell",
["names"] = {
},
["subeventSuffix"] = "_CAST_START",
["subeventPrefix"] = "SPELL",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Taunt",
["use_spellName"] = true,
["spellIds"] = {
},
["unevent"] = "auto",
["use_absorbMode"] = true,
["unit"] = "player",
["use_track"] = true,
["spellName"] = 355,
},
["untrigger"] = {
["genericShowOn"] = "showOnCooldown",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28.6,
["load"] = {
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
},
},
["talent"] = {
["single"] = 12,
["multi"] = {
[18] = true,
[12] = true,
[14] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_class"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["DEMONHUNTER"] = true,
},
},
["use_never"] = false,
["talent2"] = {
},
["use_class_and_spec"] = true,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28.7,
["source"] = "import",
["useAdjustededMin"] = false,
["progressSource"] = {
-1,
"",
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["easeType"] = "none",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["xOffset"] = 0,
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Taunt",
["frameStrata"] = 3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "YBz4ymuDw9g",
["inverse"] = true,
["color"] = {
1,
1,
1,
1,
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078432083129883,
0.2352941334247589,
0.2313725650310516,
1,
},
["property"] = "color",
},
},
},
},
["cooldown"] = true,
["desaturate"] = false,
},
["Arms Warrior: Astral Antenna Buff"] = {
["iconSource"] = 0,
["parent"] = "Arms Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = false,
["use_debuffClass"] = false,
["auraspellids"] = {
"1239641",
},
["custom_hide"] = "timed",
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["ownOnly"] = true,
["unit"] = "player",
["auranames"] = {
"1239641",
},
["spellIds"] = {
},
["type"] = "aura2",
["useExactSpellId"] = true,
["combineMatches"] = "showLowest",
["names"] = {
"Aspect of the Eagle",
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowYOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -3,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_format"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["race"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["itemequiped"] = {
242395,
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slidebottom",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["color"] = {
1,
1,
1,
1,
},
["cooldown"] = true,
["displayIcon"] = "7137575",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["preferToUpdate"] = false,
["uid"] = "bCel21(GTQQ",
["xOffset"] = 0,
["anchorFrameParent"] = false,
["alpha"] = 1,
["stickyDuration"] = false,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Astral Antenna Buff",
["zoom"] = 0.3,
["useCooldownModRate"] = true,
["width"] = 28,
["frameStrata"] = 3,
["config"] = {
},
["inverse"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["progressSource"] = {
-1,
"",
},
},
["Warrior: Fear"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 5246,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Intimidating Shout",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_petbattle"] = false,
["spec"] = {
["single"] = 3,
["multi"] = {
true,
true,
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spellknown"] = 5246,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "KEWi1hqszun",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Fear",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Revenge! Left"] = {
["parent"] = "Prot Warrior Spell Alerts",
["preferToUpdate"] = false,
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["type"] = "aura2",
["useStacks"] = true,
["auraspellids"] = {
"5302",
},
["ownOnly"] = true,
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["subeventSuffix"] = "_CAST_START",
["stacks"] = "1",
["spellIds"] = {
},
["unit"] = "player",
["names"] = {
},
["useExactSpellId"] = true,
["stacksOperator"] = ">=",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["animation"] = {
["start"] = {
["type"] = "preset",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["colorR"] = 1,
["scalex"] = 1,
["alphaType"] = "hide",
["colorB"] = 1,
["colorG"] = 1,
["alphaFunc"] = "function()\n    return 0\nend\n",
["use_alpha"] = false,
["type"] = "preset",
["easeType"] = "none",
["preset"] = "fade",
["alpha"] = 0.19,
["y"] = 0,
["x"] = 0,
["duration_type"] = "seconds",
["easeStrength"] = 3,
["rotate"] = 0,
["scaley"] = 1,
["colorA"] = 1,
},
},
["desaturate"] = false,
["rotation"] = 0,
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["height"] = 210,
["rotate"] = false,
["load"] = {
["class_and_spec"] = {
["single"] = 73,
},
["use_never"] = false,
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["size"] = {
["multi"] = {
},
},
},
["textureWrapMode"] = "CLAMPTOBLACKADDITIVE",
["source"] = "import",
["mirror"] = false,
["regionType"] = "texture",
["blendMode"] = "BLEND",
["texture"] = "603339",
["uid"] = "bpViXzx1pGS",
["color"] = {
1,
1,
1,
1,
},
["tocversion"] = 110200,
["id"] = "Prot Warrior: Revenge! Left",
["frameStrata"] = 1,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["width"] = 100,
["config"] = {
},
["xOffset"] = -155,
["authorOptions"] = {
},
["conditions"] = {
},
["information"] = {
},
["selfPoint"] = "CENTER",
},
["Fury Warrior: Astral Antenna Buff"] = {
["iconSource"] = 0,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1239641",
},
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useName"] = false,
["use_debuffClass"] = false,
["useExactSpellId"] = true,
["buffShowOn"] = "showOnActive",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Aspect of the Eagle",
},
["ownOnly"] = true,
["type"] = "aura2",
["spellIds"] = {
},
["useGroup_count"] = false,
["unit"] = "player",
["combineMatches"] = "showLowest",
["auraspellids"] = {
"1239641",
},
["subeventSuffix"] = "_CAST_START",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["use_class_and_spec"] = true,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["itemequiped"] = {
242395,
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = "7137575",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["progressSource"] = {
-1,
"",
},
["desaturate"] = false,
["config"] = {
},
["parent"] = "Fury Warrior Buffs",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Astral Antenna Buff",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "VSBFyXbNV1d",
["inverse"] = false,
["xOffset"] = 0,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Tome of Light's Devotion Stacks"] = {
["iconSource"] = -1,
["parent"] = "Prot Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"450696",
},
["ownOnly"] = true,
["unit"] = "player",
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["custom_hide"] = "timed",
["event"] = "Health",
["auraspellids"] = {
"459864",
},
["subeventPrefix"] = "SPELL",
["matchesShowOn"] = "showOnActive",
["spellIds"] = {
},
["useName"] = true,
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["names"] = {
"Aspect of the Eagle",
},
["useExactSpellId"] = false,
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 0,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_anchorYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "CENTER",
["text_fontSize"] = 18,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["itemequiped"] = {
219309,
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["authorOptions"] = {
},
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["cooldownTextDisabled"] = true,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Tome of Light's Devotion Stacks",
["zoom"] = 0.3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["useCooldownModRate"] = true,
["uid"] = "I1OBUaCENiY",
["inverse"] = false,
["xOffset"] = 0,
["conditions"] = {
},
["cooldown"] = false,
["preferToUpdate"] = false,
},
["Fury Warrior: Astral Antenna Orb"] = {
["iconSource"] = 0,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1239640",
},
["matchesShowOn"] = "showOnActive",
["names"] = {
"Aspect of the Eagle",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
"1239640",
},
["custom_hide"] = "timed",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["ownOnly"] = true,
["useExactSpellId"] = true,
["useGroup_count"] = false,
["spellIds"] = {
},
["useName"] = false,
["subeventSuffix"] = "_CAST_START",
["combineMatches"] = "showLowest",
["unit"] = "player",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slidebottom",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_anchorYOffset"] = -3,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_shadowXOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["role"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["itemequiped"] = {
242395,
},
["use_class_and_spec"] = true,
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["xOffset"] = 0,
["icon"] = true,
["cooldown"] = true,
["conditions"] = {
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["desaturate"] = false,
["uid"] = "B)6mXXK0PwK",
["keepAspectRatio"] = false,
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["alpha"] = 1,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Astral Antenna Orb",
["cooldownTextDisabled"] = false,
["frameStrata"] = 3,
["width"] = 28,
["parent"] = "Fury Warrior Buffs",
["config"] = {
},
["inverse"] = false,
["color"] = {
1,
1,
1,
1,
},
["displayIcon"] = 332402,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Bladestorm Buff"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"227847",
},
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 6,
["multi"] = {
[6] = true,
[112314] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["spellknown"] = 46924,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Arms Warrior Buffs",
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "RPYMmpTcngd",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Bladestorm Buff",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 28,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Recklessness"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 1719,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Recklessness",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 3,
["multi"] = {
[386285] = true,
[107570] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 72,
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button3",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "ZdSgVAXkd1n",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Recklessness",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Dance of Death"] = {
["iconSource"] = -1,
["parent"] = "Arms Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["unit"] = "player",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["auranames"] = {
"459572",
},
["spellIds"] = {
},
["type"] = "aura2",
["matchesShowOn"] = "showOnActive",
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_format"] = "timed",
["anchorXOffset"] = 0,
["text_text_format_p_time_precision"] = 1,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_format"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_legacy_floor"] = false,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_mod_rate"] = true,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[114639] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["authorOptions"] = {
},
["stickyDuration"] = false,
["icon"] = true,
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["color"] = {
1,
1,
1,
1,
},
["selfPoint"] = "CENTER",
["uid"] = "UQfOh0YsulK",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Dance of Death",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["width"] = 28,
["zoom"] = 0.3,
["config"] = {
},
["inverse"] = false,
["progressSource"] = {
-1,
"",
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Last Stand "] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 12975,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Last Stand",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 26,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[70] = true,
[73] = true,
},
},
["talent"] = {
["single"] = 18,
["multi"] = {
[112163] = true,
[386034] = true,
[394062] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
true,
},
},
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["single"] = "Scourge",
["multi"] = {
["Scourge"] = true,
},
},
["use_never"] = false,
["use_spec"] = true,
["use_class_and_spec"] = true,
["role"] = {
["single"] = "TANK",
["multi"] = {
["TANK"] = true,
},
},
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "VXmmx6qAFMc",
["parent"] = "Warrior » Top Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Last Stand ",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 26,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Devouring Nucleus Debuff"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["debuffType"] = "HARMFUL",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["useExactSpellId"] = false,
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["ownOnly"] = true,
["unit"] = "player",
["auranames"] = {
"1236692",
},
["spellIds"] = {
},
["type"] = "aura2",
["auraspellids"] = {
},
["combineMatches"] = "showLowest",
["names"] = {
"Remorseless Winter",
},
["use_specific_unit"] = false,
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = true,
["glowType"] = "Pixel",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
0.2000000178813934,
0.2745098173618317,
1,
},
["glow"] = true,
["glowXOffset"] = 0,
["glowDuration"] = 1,
["glowScale"] = 1,
["glowThickness"] = 2,
["glowLines"] = 8,
["glowBorder"] = true,
},
},
["height"] = 34,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["use_class_and_spec"] = true,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["use_spec"] = true,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[581] = true,
},
},
["talent"] = {
["multi"] = {
[112864] = true,
[112307] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["race"] = {
["multi"] = {
},
},
["covenant"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["itemequiped"] = {
242404,
},
["difficulty"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["use_petbattle"] = false,
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
},
},
},
["alpha"] = 1,
["useAdjustededMax"] = false,
["keepAspectRatio"] = false,
["source"] = "import",
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 1129420,
["desaturate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 4, 0)\nend",
["config"] = {
},
["parent"] = "Prot Warrior Defensives",
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["xOffset"] = 0,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Devouring Nucleus Debuff",
["selfPoint"] = "CENTER",
["frameStrata"] = 3,
["width"] = 34,
["useCooldownModRate"] = true,
["uid"] = "wRrnUP9Ro3D",
["inverse"] = false,
["color"] = {
1,
1,
1,
1,
},
["conditions"] = {
{
["check"] = {
},
["changes"] = {
{
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior » Spell Alerts"] = {
["controlledChildren"] = {
"Prot Warrior Spell Alerts",
},
["borderBackdrop"] = "Blizzard Tooltip",
["xOffset"] = 0,
["preferToUpdate"] = false,
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["subeventPrefix"] = "SPELL",
["names"] = {
},
["event"] = "Health",
["unit"] = "player",
},
["untrigger"] = {
},
},
},
["internalVersion"] = 86,
["selfPoint"] = "CENTER",
["subRegions"] = {
},
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["backdropColor"] = {
1,
1,
1,
0.5,
},
["source"] = "import",
["scale"] = 1,
["border"] = false,
["borderEdge"] = "Square Full White",
["regionType"] = "group",
["borderSize"] = 2,
["uid"] = "W4RRSPVE3zp",
["borderOffset"] = 4,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["tocversion"] = 110200,
["id"] = "Warrior » Spell Alerts",
["frameStrata"] = 4,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["parent"] = "Warrior",
["borderInset"] = 1,
["groupIcon"] = "626008",
["config"] = {
},
["conditions"] = {
},
["information"] = {
},
["authorOptions"] = {
},
},
["Arms Warrior: Ravager"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["names"] = {
},
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["use_unit"] = true,
["type"] = "spell",
["subeventPrefix"] = "SPELL",
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["duration"] = "1",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Bladestorm",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["unevent"] = "auto",
["use_absorbMode"] = true,
["use_track"] = true,
["spellName"] = 228920,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 3,
["multi"] = {
[384361] = true,
[385512] = true,
[119138] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_talent"] = false,
["use_class_and_spec"] = true,
["class_and_spec"] = {
["single"] = 71,
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["size"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button3",
["regionType"] = "icon",
["authorOptions"] = {
},
["config"] = {
},
["xOffset"] = 0,
["width"] = 34,
["anchorFrameParent"] = false,
["useAdjustededMin"] = false,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Ravager",
["progressSource"] = {
-1,
"",
},
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["uid"] = "nSL9VQzKIbF",
["inverse"] = true,
["parent"] = "Warrior » Primary Bar",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Improvised Seaforium Pacemaker"] = {
["iconSource"] = -1,
["parent"] = "Prot Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["debuffType"] = "HELPFUL",
["names"] = {
"Aspect of the Eagle",
},
["event"] = "Health",
["unit"] = "player",
["ownOnly"] = true,
["type"] = "aura2",
["spellIds"] = {
},
["auranames"] = {
"1218713",
},
["useExactSpellId"] = false,
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["faction"] = {
["multi"] = {
},
},
["itemequiped"] = {
232541,
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["stickyDuration"] = false,
["color"] = {
1,
1,
1,
1,
},
["authorOptions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["progressSource"] = {
-1,
"",
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Improvised Seaforium Pacemaker",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "S10Ui3sIG(E",
["inverse"] = false,
["xOffset"] = 0,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Test of Might"] = {
["iconSource"] = -1,
["parent"] = "Arms Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"385013",
},
["duration"] = "1",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["showClones"] = false,
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["fetchTooltip"] = true,
["event"] = "Health",
["matchesShowOn"] = "showOnActive",
["custom_hide"] = "timed",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["unit"] = "player",
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%tooltip1",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["anchorXOffset"] = 0,
["text_text_format_tooltip1_format"] = "none",
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_tooltip2_format"] = "none",
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[72] = true,
},
},
["item_bonusid_equipped"] = "6960,6963,6966,6969",
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
[112141] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_item_bonusid_equipped"] = false,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["preferToUpdate"] = false,
["icon"] = true,
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["progressSource"] = {
-1,
"",
},
["stickyDuration"] = false,
["xOffset"] = 0,
["uid"] = "P()HBDwOTYd",
["alpha"] = 1,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Test of Might",
["zoom"] = 0.3,
["frameStrata"] = 3,
["width"] = 28,
["selfPoint"] = "CENTER",
["config"] = {
},
["inverse"] = false,
["color"] = {
1,
1,
1,
1,
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["authorOptions"] = {
},
},
["Arms Warrior: Avatar Buff"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"107574",
},
["duration"] = "1",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["buffShowOn"] = "showOnActive",
["unit"] = "player",
["matchesShowOn"] = "showOnActive",
["spellIds"] = {
},
["useName"] = true,
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["subeventPrefix"] = "SPELL",
["unevent"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[107574] = true,
[112232] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["use_class_and_spec"] = true,
["spellknown"] = 107574,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["keepAspectRatio"] = false,
["parent"] = "Arms Warrior Buffs",
["config"] = {
},
["adjustedMin"] = "",
["anchorFrameParent"] = false,
["alpha"] = 1,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Avatar Buff",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "rkuIB)8X6Jk",
["inverse"] = false,
["xOffset"] = 0,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Ravager"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 228920,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Ravager",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["multi"] = {
[386034] = true,
[112256] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[72] = true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["spellknown"] = 228920,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "vF0P(dQMdMO",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Ravager",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Piercing Howl"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 12323,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Piercing Howl",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showOnCooldown",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 12,
["multi"] = {
[14] = true,
[12] = true,
[18] = true,
},
},
["use_class_and_spec"] = false,
["use_spellknown"] = true,
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_petbattle"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["DEMONHUNTER"] = true,
},
},
["spellknown"] = 12323,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "AuYhwpFJ5bm",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Piercing Howl",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Arms Warrior: Power Infusion"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"10060",
},
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useExactSpellId"] = false,
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["subeventPrefix"] = "SPELL",
["duration"] = "1",
["event"] = "Health",
["subeventSuffix"] = "_CAST_START",
["useGroup_count"] = false,
["debuffType"] = "HELPFUL",
["spellIds"] = {
},
["type"] = "aura2",
["auraspellids"] = {
},
["combineMatches"] = "showLowest",
["unit"] = "player",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "fade",
["easeStrength"] = 3,
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "slideright",
["easeStrength"] = 3,
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[103] = true,
[253] = true,
[66] = true,
[254] = true,
[71] = true,
[259] = true,
[73] = true,
[250] = true,
[581] = true,
[260] = true,
[268] = true,
[104] = true,
[577] = true,
[261] = true,
[269] = true,
[251] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 20,
["multi"] = {
[20] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["itemequiped"] = {
174500,
},
["faction"] = {
["multi"] = {
},
},
["race"] = {
["single"] = "Orc",
["multi"] = {
["Orc"] = true,
},
},
},
["alpha"] = 1,
["useAdjustededMax"] = false,
["selfPoint"] = "CENTER",
["source"] = "import",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["conditions"] = {
},
["parent"] = "Arms Warrior Buffs",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["uid"] = "noE5VSeZE2J",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["width"] = 28,
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Power Infusion",
["stickyDuration"] = false,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = false,
["keepAspectRatio"] = false,
["displayIcon"] = 1305160,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Slayer Conditions"] = {
["iconSource"] = 0,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -79,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["type"] = "aura2",
["useStacks"] = false,
["auranames"] = {
"52437",
},
["matchesShowOn"] = "showOnActive",
["event"] = "Health",
["names"] = {
},
["unitExists"] = false,
["subeventSuffix"] = "_CAST_START",
["spellIds"] = {
},
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["ownOnly"] = true,
["useName"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "aura2",
["auraspellids"] = {
"52437",
},
["ownOnly"] = true,
["unit"] = "player",
["useRem"] = true,
["remOperator"] = "<=",
["rem"] = "3",
["useExactSpellId"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "aura2",
["auraspellids"] = {
"383290",
},
["ownOnly"] = true,
["unit"] = "player",
["useRem"] = true,
["remOperator"] = "<=",
["rem"] = "4",
["useExactSpellId"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["debuffType"] = "HARMFUL",
["type"] = "aura2",
["stacksOperator"] = "==",
["useExactSpellId"] = true,
["auraspellids"] = {
"445584",
},
["useStacks"] = true,
["stacks"] = "3",
["unit"] = "target",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["stacksOperator"] = "==",
["useExactSpellId"] = true,
["auraspellids"] = {
"52437",
},
["useStacks"] = true,
["stacks"] = "2",
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1] and (t[2] or t[3] or t[4] or t[5]);\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowType"] = "Proc",
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowDuration"] = 1,
["glowXOffset"] = 0,
["glowScale"] = 1,
["glow"] = false,
["glowLength"] = 10,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 32,
["load"] = {
["use_talent"] = false,
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
},
},
["talent"] = {
["multi"] = {
[112126] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["uid"] = "0TnYmOicDIW",
["authorOptions"] = {
},
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["icon"] = true,
["information"] = {
},
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["variable"] = "OR",
["checks"] = {
{
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
{
["trigger"] = 3,
["variable"] = "show",
["value"] = 1,
},
{
["trigger"] = 4,
["variable"] = "show",
["value"] = 1,
},
{
["trigger"] = 5,
["variable"] = "show",
["value"] = 1,
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
{
["value"] = {
["sound_type"] = "Play",
["sound"] = "Interface\\Addons\\AtrocityMedia\\Sounds\\Blood.ogg",
["sound_channel"] = "Master",
},
["property"] = "sound",
},
},
},
},
["xOffset"] = 100.1,
["progressSource"] = {
-1,
"",
},
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["frameStrata"] = 1,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Slayer Conditions",
["cooldownTextDisabled"] = false,
["alpha"] = 1,
["width"] = 32,
["useCooldownModRate"] = true,
["config"] = {
},
["inverse"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["displayIcon"] = "132344",
["cooldown"] = true,
["parent"] = "Warrior » Emphasized Buffs",
},
["Prot Warrior: Execute (Massacre)"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -71,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = true,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_charges"] = false,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["names"] = {
},
["percenthealth_operator"] = {
"<=",
},
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_trackcharge"] = false,
["spellName"] = 163201,
["use_absorbMode"] = true,
["type"] = "unit",
["use_absorbHealMode"] = true,
["use_targetRequired"] = true,
["use_spellCount"] = false,
["percenthealth"] = {
"35",
},
["event"] = "Health",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
["use_percenthealth"] = true,
["use_track"] = true,
["unit"] = "target",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["unit"] = "player",
["use_spellName"] = true,
["debuffType"] = "HELPFUL",
["genericShowOn"] = "showAlways",
["use_exact_spellName"] = false,
["use_track"] = true,
["spellName"] = 281000,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"280776",
"52437",
},
["unit"] = "player",
["type"] = "aura2",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[3];\nend",
["activeTriggerMode"] = 2,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "alphaPulse",
["duration_type"] = "seconds",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["glowDuration"] = 1,
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowLength"] = 10,
["glowScale"] = 1,
["glowXOffset"] = 0,
["useGlowColor"] = false,
["glow"] = true,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text"] = "FREE",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_text_format_p_format"] = "timed",
["text_color"] = {
0,
1,
0.10980392156863,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_anchorYOffset"] = -15,
["text_text_format_p_time_precision"] = 1,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = false,
["text_text_format_p_time_format"] = 0,
["anchor_point"] = "CENTER",
["text_fontSize"] = 10,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
},
},
["height"] = 34,
["load"] = {
["use_covenant"] = false,
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[112168] = true,
[112145] = true,
[132879] = true,
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["talent_extraOption"] = 0,
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["use_class_and_spec"] = true,
["use_spec"] = true,
["covenant"] = {
["single"] = 2,
["multi"] = {
["1"] = true,
["4"] = true,
["3"] = true,
["0"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
[2] = true,
[3] = true,
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[71] = true,
},
},
["zoneIds"] = "",
},
["useAdjustededMax"] = false,
["width"] = 34,
["source"] = "import",
["parent"] = "Warrior » Emphasized Buffs",
["preferToUpdate"] = false,
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["displayIcon"] = "135358",
["keepAspectRatio"] = false,
["authorOptions"] = {
},
["config"] = {
},
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Execute (Massacre)",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "7pD2L4k6Ig8",
["inverse"] = true,
["selfPoint"] = "CENTER",
["conditions"] = {
{
["check"] = {
["op"] = "<",
["checks"] = {
{
["value"] = 0,
["op"] = "<",
["variable"] = "show",
},
{
["trigger"] = 3,
["variable"] = "show",
["value"] = 0,
},
},
["trigger"] = 2,
["variable"] = "insufficientResources",
["value"] = 1,
},
["linked"] = false,
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
{
["property"] = "sub.2.glow",
},
},
},
{
["check"] = {
["trigger"] = 3,
["variable"] = "show",
["value"] = 1,
},
["linked"] = true,
["changes"] = {
{
["value"] = true,
["property"] = "sub.4.text_visible",
},
},
},
},
["cooldown"] = true,
["desaturate"] = false,
},
["Arms Warrior: Storm of Swords"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"439601",
},
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["unit"] = "player",
["duration"] = "1",
["spellIds"] = {
},
["useName"] = true,
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["anchorYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112119] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["authorOptions"] = {
},
["selfPoint"] = "CENTER",
["xOffset"] = 0,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["parent"] = "Arms Warrior Buffs",
["icon"] = true,
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Storm of Swords",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "UiwouxLJoXB",
["inverse"] = false,
["progressSource"] = {
-1,
"",
},
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Rallying Cry CD"] = {
["outline"] = "OUTLINE",
["xOffset"] = -112,
["displayText_format_p_time_dynamic_threshold"] = 3,
["shadowYOffset"] = 0,
["anchorPoint"] = "CENTER",
["displayText_format_p_time_format"] = 0,
["customTextUpdate"] = "event",
["automaticWidth"] = "Fixed",
["actions"] = {
["start"] = {
["do_sound"] = false,
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["auranames"] = {
"51052",
},
["ownOnly"] = true,
["genericShowOn"] = "showOnCooldown",
["use_unit"] = true,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["type"] = "spell",
["subeventSuffix"] = "_CAST_START",
["unevent"] = "auto",
["subeventPrefix"] = "SPELL",
["names"] = {
},
["event"] = "Cooldown Progress (Spell)",
["use_absorbMode"] = true,
["realSpellName"] = "Stampeding Roar",
["use_spellName"] = true,
["spellIds"] = {
},
["useName"] = true,
["use_genericShowOn"] = true,
["duration"] = "1",
["use_track"] = true,
["spellName"] = 97462,
},
["untrigger"] = {
["genericShowOn"] = "showOnCooldown",
},
},
["activeTriggerMode"] = -10,
},
["displayText_format_p_format"] = "timed",
["displayText_format_p_time_legacy_floor"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["font"] = "Expressway",
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["use_class"] = true,
["use_spellknown"] = true,
["zoneIds"] = "",
["use_class_and_spec"] = false,
["class_and_spec"] = {
["single"] = 70,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["class"] = {
["single"] = "PALADIN",
["multi"] = {
},
},
["spellknown"] = 97462,
["size"] = {
["multi"] = {
},
},
},
["fontSize"] = 11,
["source"] = "import",
["displayText_format_n_format"] = "none",
["shadowXOffset"] = 0,
["selfPoint"] = "LEFT",
["anchorFrameFrame"] = "ElvUF_Player",
["regionType"] = "text",
["preferToUpdate"] = false,
["wordWrap"] = "WordWrap",
["fixedWidth"] = 130,
["displayText_format_p_time_precision"] = 1,
["yOffset"] = 0,
["displayText"] = "RALLY » %p",
["config"] = {
},
["justify"] = "LEFT",
["tocversion"] = 110200,
["id"] = "Warrior: Rallying Cry CD",
["parent"] = "Warrior",
["frameStrata"] = 3,
["anchorFrameType"] = "SELECTFRAME",
["displayText_format_p_time_mod_rate"] = true,
["uid"] = "vGG8bBOOpqD",
["color"] = {
1,
1,
1,
1,
},
["authorOptions"] = {
},
["shadowColor"] = {
0,
0,
0,
0,
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["internalVersion"] = 86,
},
["Arms Warrior: Bloodlust"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"80353",
"2825",
"264667",
"32182",
"381301",
"390386",
"444257",
"466904",
},
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["custom_hide"] = "timed",
["names"] = {
"Time Warp",
"Bloodlust",
"Primal Rage",
"Drums of Rage",
"Drums of Fury",
"Netherwinds",
"Drums of the Mountain",
},
["duration"] = "1",
["spellIds"] = {
},
["useName"] = true,
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["subeventPrefix"] = "SPELL",
["unevent"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[72] = true,
[577] = true,
[103] = true,
[581] = true,
[71] = true,
[259] = true,
[73] = true,
[250] = true,
[254] = true,
[260] = true,
[268] = true,
[104] = true,
[66] = true,
[261] = true,
[269] = true,
[251] = true,
[253] = true,
},
},
["talent"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["use_class_and_spec"] = true,
["use_petbattle"] = false,
["role"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["stickyDuration"] = false,
["parent"] = "Arms Warrior Buffs",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "fade",
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "slideright",
},
},
["icon"] = true,
["config"] = {
},
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Bloodlust",
["alpha"] = 1,
["frameStrata"] = 3,
["width"] = 28,
["zoom"] = 0.3,
["uid"] = "Ql0sw9S85XZ",
["inverse"] = false,
["keepAspectRatio"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Ravager Buff"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["auranames"] = {
"228920",
},
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
[132880] = true,
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 6,
["multi"] = {
[6] = true,
[112304] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["use_talent2"] = false,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["spellknown"] = 46924,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Prot Warrior Buffs",
["stickyDuration"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["progressSource"] = {
-1,
"",
},
["icon"] = true,
["uid"] = "BBms5Cc6ahl",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Ravager Buff",
["alpha"] = 1,
["frameStrata"] = 3,
["width"] = 28,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["xOffset"] = 0,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Cleave"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 845,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Whirlwind",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Spell Activation Overlay",
["unit"] = "player",
["use_spellName"] = true,
["spellName"] = 845,
["genericShowOn"] = "showOnCooldown",
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "aura2",
["auranames"] = {
"7384",
},
["unit"] = "player",
["useName"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowScale"] = 1,
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowType"] = "buttonOverlay",
["glowDuration"] = 1,
["glow"] = false,
["glowXOffset"] = 0,
["glowThickness"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["text_text_format_p_time_format"] = 0,
["text_text"] = "%3.s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorXOffset"] = 0,
["text_text_format_p_time_mod_rate"] = true,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_precision"] = 1,
["text_anchorYOffset"] = -5,
["text_text_format_3.s_format"] = "none",
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_shadowYOffset"] = 0,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_legacy_floor"] = false,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[112147] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_class_and_spec"] = true,
["class_and_spec"] = {
["single"] = 71,
},
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["talent2"] = {
},
["use_spec"] = true,
["spec"] = {
["single"] = 2,
["multi"] = {
true,
},
},
["use_exact_spellknown"] = false,
["spellknown"] = 388903,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "7Hpgv9GtrsF",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Cleave",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellUsable",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Marked for Execution"] = {
["iconSource"] = -1,
["parent"] = "Fury Warrior Buffs",
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["ownOnly"] = true,
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["unit"] = "target",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["event"] = "Health",
["unevent"] = "timed",
["auranames"] = {
"445584",
},
["type"] = "aura2",
["spellIds"] = {
},
["matchesShowOn"] = "showOnActive",
["duration"] = "1",
["combineMatches"] = "showLowest",
["debuffType"] = "HARMFUL",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.2,
["type"] = "subglow",
["useGlowColor"] = true,
["glowScale"] = 1,
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
0.8980392813682556,
0,
1,
},
["glowType"] = "Pixel",
["glowDuration"] = 1,
["glow"] = false,
["glowXOffset"] = 0,
["glowThickness"] = 1,
["glowLines"] = 4,
["glowBorder"] = true,
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112275] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["zoneIds"] = "",
["use_herotalent"] = false,
["role"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["herotalent"] = {
["multi"] = {
[117411] = true,
},
},
["difficulty"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["icon"] = true,
["source"] = "import",
["keepAspectRatio"] = false,
["cooldown"] = true,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "stacks",
["value"] = "3",
["op"] = "==",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["xOffset"] = 0,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "wba3xc43ISM",
["authorOptions"] = {
},
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["stickyDuration"] = false,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Marked for Execution",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28,
["selfPoint"] = "CENTER",
["config"] = {
},
["inverse"] = false,
["adjustedMin"] = "",
["displayIcon"] = "237569",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Sharpen Blade"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["use_unit"] = true,
["type"] = "spell",
["names"] = {
},
["unevent"] = "auto",
["unit"] = "player",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Sharpen Blade",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["use_track"] = true,
["spellName"] = 198817,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 263,
["multi"] = {
[71] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[334046] = true,
},
},
["class"] = {
["single"] = "SHAMAN",
["multi"] = {
["DEMONHUNTER"] = true,
["SHAMAN"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["use_class_and_spec"] = false,
["use_petbattle"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["use_never"] = false,
["pvptalent"] = {
},
["use_spec"] = false,
["use_exact_spellknown"] = false,
["spellknown"] = 198817,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28.7,
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["color"] = {
1,
1,
1,
1,
},
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Sharpen Blade",
["alpha"] = 1,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["parent"] = "Warrior » PvP Bar",
["uid"] = "E5Ah2MqGIGc",
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["cooldown"] = true,
["desaturate"] = false,
},
["Warrior: Spell Reflection"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 23920,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Spell Reflection",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 26,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_never"] = false,
["spellknown"] = 23920,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "uRF5TGh(8E2",
["parent"] = "Warrior » Top Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Spell Reflection",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 26,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Demoralizing Shout Debuff"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1160",
},
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HARMFUL",
["custom_hide"] = "timed",
["event"] = "Health",
["ownOnly"] = true,
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["unevent"] = "timed",
["combineMatches"] = "showLowest",
["unit"] = "target",
["duration"] = "1",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
},
["talent"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["ingroup"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
true,
[3] = true,
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["zoneIds"] = "",
},
["useAdjustededMax"] = false,
["width"] = 34,
["source"] = "import",
["keepAspectRatio"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["authorOptions"] = {
},
["config"] = {
},
["adjustedMin"] = "",
["anchorFrameParent"] = false,
["alpha"] = 1,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Demoralizing Shout Debuff",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "lubiA22Juqo",
["inverse"] = false,
["parent"] = "Prot Warrior Defensives",
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Cursed Stone Idol"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["useExactSpellId"] = false,
["ownOnly"] = true,
["names"] = {
"Aspect of the Eagle",
},
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"1242326",
},
["combineMatches"] = "showLowest",
["unit"] = "player",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["faction"] = {
["multi"] = {
},
},
["itemequiped"] = {
246344,
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["color"] = {
1,
1,
1,
1,
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["stickyDuration"] = false,
["parent"] = "Fury Warrior Buffs",
["keepAspectRatio"] = false,
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Cursed Stone Idol",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "48LD5UjkjxM",
["inverse"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Avatar Buff"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"107574",
},
["duration"] = "1",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["buffShowOn"] = "showOnActive",
["unit"] = "player",
["matchesShowOn"] = "showOnActive",
["spellIds"] = {
},
["useName"] = true,
["useGroup_count"] = false,
["combineMatches"] = "showLowest",
["subeventPrefix"] = "SPELL",
["unevent"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[107574] = true,
[114770] = true,
[112232] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["use_class_and_spec"] = true,
["spellknown"] = 107574,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["keepAspectRatio"] = false,
["parent"] = "Fury Warrior Buffs",
["config"] = {
},
["adjustedMin"] = "",
["anchorFrameParent"] = false,
["alpha"] = 1,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Avatar Buff",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "RkrwVKLuCI9",
["inverse"] = false,
["xOffset"] = 0,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior Buffs"] = {
["arcLength"] = 360,
["controlledChildren"] = {
"Fury Warrior: Bloodlust",
"Fury Warrior: Potion",
"Fury Warrior: Racials",
"Fury Warrior: Power Infusion",
"Fury Warrior: Signet of the Priory",
"Fury Warrior: Improvised Seaforium Pacemaker",
"Fury Warrior: Cursed Stone Idol",
"Fury Warrior: Araz's Ritual Forge",
"Fury Warrior: Astral Antenna Orb",
"Fury Warrior: Astral Antenna Buff",
"Fury Warrior: Unyielding Netherprism",
"Fury Warrior: Champion's Might",
"Fury Warriorr: Bladestorm Buff",
"Fury Warriorr: Ravager Buff",
"Fury Warrior: Ravager w/ Unhinged",
"Fury Warrior: Recklessness Buff",
"Fury Warrior: Avatar Buff",
"Fury Warrior: Odyn's Fury Debuff",
"Fury Warrior: Juggernaut",
"Fury Warrior: Marked for Execution",
},
["borderBackdrop"] = "Blizzard Tooltip",
["parent"] = "Warrior » Buff Bar",
["preferToUpdate"] = false,
["yOffset"] = -147,
["sortHybridTable"] = {
["Fury Warrior: Champion's Might"] = false,
["Fury Warrior: Improvised Seaforium Pacemaker"] = false,
["Fury Warrior: Recklessness Buff"] = false,
["Fury Warrior: Araz's Ritual Forge"] = false,
["Fury Warrior: Potion"] = false,
["Fury Warrior: Power Infusion"] = false,
["Fury Warrior: Unyielding Netherprism"] = false,
["Fury Warrior: Cursed Stone Idol"] = false,
["Fury Warrior: Astral Antenna Orb"] = false,
["Fury Warrior: Marked for Execution"] = false,
["Fury Warrior: Juggernaut"] = false,
["Fury Warriorr: Bladestorm Buff"] = false,
["Fury Warrior: Racials"] = false,
["Fury Warrior: Odyn's Fury Debuff"] = false,
["Fury Warrior: Signet of the Priory"] = false,
["Fury Warrior: Ravager w/ Unhinged"] = false,
["Fury Warrior: Astral Antenna Buff"] = false,
["Fury Warrior: Avatar Buff"] = false,
["Fury Warriorr: Ravager Buff"] = false,
["Fury Warrior: Bloodlust"] = false,
},
["borderColor"] = {
0,
0,
0,
1,
},
["space"] = 3,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["names"] = {
},
["event"] = "Health",
["subeventPrefix"] = "SPELL",
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["internalVersion"] = 86,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["align"] = "CENTER",
["alpha"] = 1,
["xOffset"] = 0.01,
["anchorPoint"] = "CENTER",
["rotation"] = 0,
["fullCircle"] = true,
["rowSpace"] = 1,
["subRegions"] = {
},
["stagger"] = 0,
["radius"] = 200,
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["gridType"] = "RD",
["backdropColor"] = {
1,
1,
1,
0.5,
},
["borderInset"] = 1,
["source"] = "import",
["grow"] = "HORIZONTAL",
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["stepAngle"] = 15,
["borderSize"] = 2,
["sort"] = "none",
["groupIcon"] = "626008",
["gridWidth"] = 5,
["constantFactor"] = "RADIUS",
["limit"] = 5,
["borderOffset"] = 4,
["selfPoint"] = "CENTER",
["tocversion"] = 110200,
["id"] = "Fury Warrior Buffs",
["regionType"] = "dynamicgroup",
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["animate"] = false,
["config"] = {
},
["uid"] = "9LhHZ8Z6(gB",
["useLimit"] = false,
["conditions"] = {
},
["information"] = {
},
["authorOptions"] = {
},
},
["Fury Warrior: Recklessness Buff"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1719",
},
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112281] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["progressSource"] = {
-1,
"",
},
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["desaturate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["authorOptions"] = {
},
["uid"] = "Jn14OJZ6ESi",
["adjustedMin"] = "",
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Recklessness Buff",
["frameStrata"] = 3,
["alpha"] = 1,
["width"] = 28,
["parent"] = "Fury Warrior Buffs",
["config"] = {
},
["inverse"] = false,
["color"] = {
1,
1,
1,
1,
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Cursed Stone Idol"] = {
["iconSource"] = -1,
["parent"] = "Prot Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"1242326",
},
["ownOnly"] = true,
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["unit"] = "player",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["matchesShowOn"] = "showOnActive",
["subeventSuffix"] = "_CAST_START",
["useGroup_count"] = false,
["spellIds"] = {
},
["useName"] = true,
["useExactSpellId"] = false,
["combineMatches"] = "showLowest",
["names"] = {
"Aspect of the Eagle",
},
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["faction"] = {
["multi"] = {
},
},
["itemequiped"] = {
246344,
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["progressSource"] = {
-1,
"",
},
["authorOptions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Cursed Stone Idol",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "3iK5S238JTz",
["inverse"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Signet of the Priory"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["spellId"] = {
"49206",
},
["auranames"] = {
"443531",
},
["duration"] = "25",
["use_sourceNpcId"] = false,
["use_totemType"] = true,
["spellName"] = {
"",
},
["use_debuffClass"] = false,
["subeventSuffix"] = "_SUMMON",
["event"] = "Combat Log",
["use_spellId"] = true,
["use_sourceUnit"] = true,
["combineMatches"] = "showLowest",
["use_track"] = true,
["useGroup_count"] = false,
["use_absorbMode"] = true,
["genericShowOn"] = "showOnCooldown",
["use_unit"] = true,
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["useName"] = true,
["custom_hide"] = "timed",
["unevent"] = "timed",
["subeventPrefix"] = "SPELL",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_genericShowOn"] = true,
["totemType"] = 1,
["realSpellName"] = "",
["use_spellName"] = false,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["matchesShowOn"] = "showOnActive",
["use_sourceName"] = false,
["sourceUnit"] = "player",
["type"] = "aura2",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["class"] = {
["single"] = "DEATHKNIGHT",
["multi"] = {
["DEATHKNIGHT"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[252] = true,
},
},
["talent"] = {
["multi"] = {
[96311] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["faction"] = {
["multi"] = {
},
},
["itemequiped"] = {
219308,
},
["size"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 458967,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["authorOptions"] = {
},
["config"] = {
},
["progressSource"] = {
-1,
"",
},
["anchorFrameParent"] = false,
["alpha"] = 1,
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["auto"] = false,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Signet of the Priory",
["cooldownTextDisabled"] = false,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["parent"] = "Arms Warrior Buffs",
["uid"] = "nZvlEdkkNlw",
["inverse"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Bloodlust"] = {
["iconSource"] = -1,
["parent"] = "Fury Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"80353",
"2825",
"264667",
"32182",
"381301",
"390386",
"444257",
"466904",
},
["duration"] = "1",
["unit"] = "player",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["names"] = {
"Time Warp",
"Bloodlust",
"Primal Rage",
"Drums of Rage",
"Drums of Fury",
"Netherwinds",
"Drums of the Mountain",
},
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["matchesShowOn"] = "showOnActive",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[72] = true,
[577] = true,
[103] = true,
[581] = true,
[71] = true,
[259] = true,
[73] = true,
[250] = true,
[254] = true,
[260] = true,
[268] = true,
[104] = true,
[66] = true,
[261] = true,
[269] = true,
[251] = true,
[253] = true,
},
},
["talent"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["zoneIds"] = "",
},
["useAdjustededMax"] = false,
["source"] = "import",
["authorOptions"] = {
},
["desaturate"] = false,
["xOffset"] = 0,
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "fade",
["easeStrength"] = 3,
},
["main"] = {
["type"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "slideright",
["easeStrength"] = 3,
},
},
["icon"] = true,
["uid"] = "1yRBP8omJrQ",
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Bloodlust",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["keepAspectRatio"] = false,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Juggernaut"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"335232",
"383290",
},
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[18] = true,
[17] = true,
[112278] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Fury Warrior Buffs",
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "C23SDZbAs5I",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Juggernaut",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 28,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Ravager Buff"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["unit"] = "player",
["matchesShowOn"] = "showOnActive",
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"228920",
},
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 6,
["multi"] = {
[6] = true,
[119138] = true,
},
},
["use_petbattle"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["race"] = {
["multi"] = {
},
},
["use_not_spellknown"] = true,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["not_spellknown"] = 386628,
["spellknown"] = 46924,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["stickyDuration"] = false,
["selfPoint"] = "CENTER",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["progressSource"] = {
-1,
"",
},
["icon"] = true,
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Ravager Buff",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "S4y4J0dQvPe",
["inverse"] = false,
["parent"] = "Arms Warrior Buffs",
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Odyn's Fury Debuff"] = {
["iconSource"] = -1,
["parent"] = "Fury Warrior Buffs",
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HARMFUL",
["custom_hide"] = "timed",
["event"] = "Health",
["unevent"] = "timed",
["duration"] = "1",
["ownOnly"] = true,
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"385060",
},
["combineMatches"] = "showLowest",
["unit"] = "target",
["subeventPrefix"] = "SPELL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["use_talent"] = false,
["role"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112289] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["faction"] = {
["multi"] = {
},
},
["herotalent"] = {
["multi"] = {
[117411] = true,
},
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
["zoneIds"] = "",
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["source"] = "import",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = "237569",
["keepAspectRatio"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["adjustedMin"] = "",
["width"] = 28,
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Odyn's Fury Debuff",
["stickyDuration"] = false,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["xOffset"] = 0,
["uid"] = "ffLilX6Jd7O",
["inverse"] = false,
["authorOptions"] = {
},
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Tank Cloak"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 4, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["names"] = {
"Remorseless Winter",
},
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
},
["useExactSpellId"] = false,
["fetchTooltip"] = true,
["event"] = "Health",
["subeventSuffix"] = "_CAST_START",
["use_specific_unit"] = false,
["auranames"] = {
"1223614",
},
["spellIds"] = {
},
["subeventPrefix"] = "SPELL",
["type"] = "aura2",
["combineMatches"] = "showLowest",
["ownOnly"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_precision"] = 1,
["text_selfPoint"] = "AUTO",
["text_text"] = "%1.tooltip2",
["text_text_format_1.tooltip2_pad_mode"] = "left",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_1.tooltip2_pad"] = false,
["text_text_format_1.tooltip2_decimal_precision"] = 1,
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_1.tooltip2_pad_max"] = 8,
["text_text_format_p_format"] = "timed",
["type"] = "subtext",
["text_text_format_1.tooltip2_big_number_format"] = "AbbreviateNumbers",
["text_fontType"] = "OUTLINE",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = -2,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_shadowXOffset"] = 0,
["text_text_format_p_time_format"] = 0,
["anchor_point"] = "INNER_BOTTOM",
["text_fontSize"] = 14,
["text_text_format_1.tooltip2_format"] = "BigNumber",
["anchorXOffset"] = 0,
},
},
["height"] = 34,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["use_class_and_spec"] = true,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["use_spec"] = true,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[581] = true,
[73] = true,
},
},
["talent"] = {
["multi"] = {
[112864] = true,
[112307] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["zoneIds"] = "",
["covenant"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["itemequiped"] = {
235499,
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["icon"] = true,
["source"] = "import",
["authorOptions"] = {
},
["cooldown"] = true,
["conditions"] = {
},
["keepAspectRatio"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["uid"] = "9CccpYrkfuo",
["parent"] = "Prot Warrior Defensives",
["width"] = 34,
["anchorFrameParent"] = false,
["adjustedMin"] = "",
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Tank Cloak",
["frameStrata"] = 3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["selfPoint"] = "CENTER",
["config"] = {
},
["inverse"] = false,
["stickyDuration"] = false,
["displayIcon"] = 1129420,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Last Stand"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Remorseless Winter",
},
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
},
["useExactSpellId"] = false,
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["subeventSuffix"] = "_CAST_START",
["use_specific_unit"] = false,
["ownOnly"] = true,
["spellIds"] = {
},
["type"] = "aura2",
["auranames"] = {
"12975",
},
["combineMatches"] = "showLowest",
["unit"] = "player",
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 34,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
},
},
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = true,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[581] = true,
},
},
["talent"] = {
["multi"] = {
[112864] = true,
[112163] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["covenant"] = {
["single"] = 2,
["multi"] = {
[2] = true,
},
},
["use_class_and_spec"] = true,
["use_petbattle"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["difficulty"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["source"] = "import",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["conditions"] = {
},
["parent"] = "Prot Warrior Defensives",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "IE999GQm8pK",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 4, 0)\nend",
["width"] = 34,
["anchorFrameParent"] = false,
["alpha"] = 1,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Last Stand",
["stickyDuration"] = false,
["frameStrata"] = 3,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = false,
["keepAspectRatio"] = false,
["displayIcon"] = 1129420,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Find Self"] = {
["outline"] = "OUTLINE",
["authorOptions"] = {
},
["displayText"] = "+",
["shadowYOffset"] = 0,
["anchorPoint"] = "TOP",
["displayText_format_p_time_format"] = 0,
["customTextUpdate"] = "event",
["automaticWidth"] = "Auto",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["do_custom_unload"] = false,
["do_custom_load"] = false,
["custom"] = "\n\n",
["do_custom"] = false,
},
},
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["use_absorbHealMode"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["event"] = "Unit Characteristics",
["subeventPrefix"] = "SPELL",
["use_inCombat"] = true,
["spellIds"] = {
},
["use_unit"] = true,
["unit"] = "player",
["names"] = {
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_absorbHealMode"] = true,
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_spellName"] = true,
["spellName"] = 6552,
["use_absorbMode"] = true,
["unit"] = "player",
["event"] = "Cooldown Progress (Spell)",
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["displayText_format_p_time_mod_rate"] = true,
["displayText_format_p_time_legacy_floor"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["font"] = "Expressway",
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["load"] = {
["class_and_spec"] = {
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_never"] = false,
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["use_class_and_spec"] = false,
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["fontSize"] = 36,
["shadowXOffset"] = 0,
["displayText_format_p_format"] = "timed",
["regionType"] = "text",
["displayText_format_p_time_dynamic_threshold"] = 60,
["wordWrap"] = "WordWrap",
["conditions"] = {
{
["check"] = {
["trigger"] = 2,
["variable"] = "spellInRange",
["value"] = 0,
["checks"] = {
{
["trigger"] = 2,
["variable"] = "spellInRange",
["value"] = 0,
},
{
["value"] = 0,
["variable"] = "spellInRange",
},
{
["value"] = 0,
["variable"] = "spellInRange",
},
},
},
["changes"] = {
{
["value"] = {
1,
0,
0.01176470704376698,
1,
},
["property"] = "color",
},
},
},
},
["preferToUpdate"] = false,
["anchorFrameParent"] = false,
["parent"] = "Warrior",
["config"] = {
},
["color"] = {
0,
1,
0.168627455830574,
1,
},
["justify"] = "LEFT",
["tocversion"] = 110200,
["id"] = "Warrior: Find Self",
["selfPoint"] = "CENTER",
["frameStrata"] = 1,
["anchorFrameType"] = "PRD",
["displayText_format_p_time_precision"] = 1,
["uid"] = "hgfTzNqYkAK",
["internalVersion"] = 86,
["yOffset"] = 30,
["shadowColor"] = {
0,
0,
0,
1,
},
["fixedWidth"] = 200,
["information"] = {
},
["xOffset"] = 1,
},
["Prot Warrior: Sudden Death"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["duration"] = "1",
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"280776",
},
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_mod_rate"] = true,
["anchorXOffset"] = 0,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_format"] = 0,
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontType"] = "OUTLINE",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_legacy_floor"] = false,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[2] = true,
[132884] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["parent"] = "Prot Warrior Buffs",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Sudden Death",
["frameStrata"] = 3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "tAQdXQ6Cp5J",
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Champion's Might"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["rem"] = "0",
["auranames"] = {
"311193",
},
["duration"] = "1",
["unit"] = "target",
["use_tooltip"] = false,
["ownOnly"] = true,
["matchesShowOn"] = "showOnActive",
["type"] = "aura2",
["custom_hide"] = "timed",
["unevent"] = "timed",
["useName"] = false,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["useGroup_count"] = false,
["useExactSpellId"] = true,
["event"] = "Health",
["buffShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["auraspellids"] = {
"376080",
},
["spellIds"] = {
},
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["remOperator"] = ">",
["combineMatches"] = "showLowest",
["debuffType"] = "HARMFUL",
["useRem"] = false,
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = 1,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.2,
["glow"] = true,
["useGlowColor"] = true,
["glowType"] = "Pixel",
["glowLength"] = 8,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["type"] = "subglow",
["glowThickness"] = 1,
["glowDuration"] = 1,
["glowXOffset"] = 0,
["glowScale"] = 1,
["glowLines"] = 4,
["glowBorder"] = true,
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["item_bonusid_equipped"] = "",
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
[112180] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_item_bonusid_equipped"] = false,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["desaturate"] = false,
["source"] = "import",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 3565453,
["parent"] = "Arms Warrior Buffs",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["alpha"] = 1,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Champion's Might",
["selfPoint"] = "CENTER",
["useCooldownModRate"] = true,
["width"] = 28,
["authorOptions"] = {
},
["uid"] = "I4mkiZRB8gs",
["inverse"] = false,
["progressSource"] = {
-1,
"",
},
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Trinket"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["itemSlot"] = 13,
["use_unit"] = true,
["debuffType"] = "HELPFUL",
["use_trackcharge"] = false,
["buffShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["type"] = "item",
["use_absorbMode"] = true,
["unevent"] = "auto",
["subeventSuffix"] = "_CAST_START",
["use_itemSlot"] = true,
["event"] = "Cooldown Progress (Equipment Slot)",
["use_exact_spellName"] = true,
["realSpellName"] = 113860,
["use_spellName"] = true,
["spellIds"] = {
},
["use_testForCooldown"] = true,
["duration"] = "1",
["names"] = {
},
["use_track"] = true,
["spellName"] = 113860,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
["itemSlot"] = 14,
},
},
{
["trigger"] = {
["type"] = "custom",
["events"] = "PLAYER_EQUIPMENT_CHANGED",
["custom_type"] = "stateupdate",
["check"] = "event",
["debuffType"] = "HELPFUL",
["custom"] = "function(...) return aura_env:TSU(...) end\n    \n    ",
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["PRIEST"] = true,
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["custom"] = "function aura_env:Init()\n    self.slot = 13\n    self.filteredItemIDs = {\n        [186421] = true,\n        [185304] = true,\n        [185282] = true,\n        [190958] = true,\n        [193757] = true, --Ruby Whelp Shell\n        [194307] = true, --Broodkeeper Promise\n        [193718] = true, --Emerald Coach's Whistle\n        [200563] = true, --Primal Ritual Shell\n        [203729] = true, --Ominous Chromatic Essence \n        [202612] = true, --Screaming Black Dragonscale \n        [178742] = true, --Bottled FLayedwing Toxin\n        [230193] = true, --Mister Lock-N-Stalk\n        [242396] = true, --Unyielding Netherprism  \n        \n    }\nend\n\nfunction aura_env:TSU(allStates, event, arg1)\n    if event == \"PLAYER_EQUIPMENT_CHANGED\" and (not arg1 or arg1 == self.slot) then\n        self.show = not self.filteredItemIDs[GetInventoryItemID(\"player\", self.slot)]\n    end\n    \n    self.changed = true\n    allStates[\"\"] = self\n    return true\nend\n\naura_env:Init()",
["do_custom"] = true,
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = ")Mt5ae2NfAW",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Trinket",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Mortal Strike"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 12294,
["type"] = "spell",
["unit"] = "player",
["unevent"] = "auto",
["use_genericShowOn"] = true,
["subeventSuffix"] = "_CAST_START",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Mortal Strike",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_absorbMode"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"7384",
},
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["unit"] = "player",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "aura2",
["auranames"] = {
"386633",
},
["debuffType"] = "HARMFUL",
["ownOnly"] = true,
["useName"] = true,
["unit"] = "target",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "spell",
["use_genericShowOn"] = true,
["genericShowOn"] = "showOnCooldown",
["unit"] = "player",
["realSpellName"] = 0,
["use_spellName"] = true,
["debuffType"] = "HELPFUL",
["event"] = "Spell Activation Overlay",
["use_exact_spellName"] = true,
["use_track"] = true,
["spellName"] = 12294,
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\n    return t[1]\nend",
["activeTriggerMode"] = 1,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["glow"] = false,
["glowDuration"] = 1,
["glowType"] = "Proc",
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["type"] = "subglow",
["glowScale"] = 1,
["useGlowColor"] = true,
["glowXOffset"] = 0,
["glowLength"] = 12,
["glowLines"] = 4,
["glowBorder"] = true,
},
{
["border_size"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text"] = "%2.s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["text_text_format_p_time_dynamic_threshold"] = 60,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
0,
1,
0.168627455830574,
1,
},
["text_font"] = "Expressway",
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = -5,
["text_text_format_p_time_format"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_fontType"] = "OUTLINE",
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 13,
["anchorXOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
},
{
["text_text_format_p_time_format"] = 0,
["text_text"] = "%3.s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_format"] = "timed",
["anchorXOffset"] = 0,
["text_text_format_p_time_precision"] = 1,
["type"] = "subtext",
["text_anchorXOffset"] = 6,
["text_color"] = {
1,
0.6352941393852234,
0.1607843190431595,
1,
},
["text_font"] = "Expressway",
["text_anchorYOffset"] = 3,
["text_shadowYOffset"] = 0,
["text_visible"] = true,
["text_wordWrap"] = "WordWrap",
["text_text_format_3.s_format"] = "none",
["text_fontType"] = "OUTLINE",
["text_text_format_2.s_format"] = "none",
["anchor_point"] = "INNER_TOPRIGHT",
["text_fontSize"] = 13,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowXOffset"] = 0,
},
},
["height"] = 34,
["load"] = {
["talent2"] = {
},
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[384361] = true,
[112122] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["herotalent"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
},
["alpha"] = 1,
["useAdjustededMax"] = false,
["useTooltip"] = false,
["source"] = "import",
["keepAspectRatio"] = false,
["cooldown"] = true,
["stickyDuration"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
["custom"] = "\n\n",
["do_custom"] = false,
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "2Ldeql67x)H",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["useAdjustededMin"] = false,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Mortal Strike",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["width"] = 34,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["config"] = {
},
["inverse"] = true,
["parent"] = "Warrior » Primary Bar",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "insufficientResources",
["value"] = 1,
},
["changes"] = {
{
["value"] = {
0.458823561668396,
0.4862745404243469,
0.7176470756530762,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.80784320831299,
0.23529413342476,
0.23137256503105,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["op"] = "==",
["checks"] = {
{
["trigger"] = 2,
["variable"] = "stacks",
["op"] = "==",
["value"] = "2",
},
{
["trigger"] = 3,
["variable"] = "stacks",
["op"] = "==",
["value"] = "2",
},
},
["trigger"] = 3,
["variable"] = "stacks",
["value"] = "2",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
{
["value"] = {
1,
0.6352941393852234,
0.1607843190431595,
1,
},
["property"] = "sub.2.glowColor",
},
},
["linked"] = false,
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Execute"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -113,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["names"] = {
},
["use_track"] = true,
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["use_charges"] = false,
["type"] = "unit",
["use_absorbHealMode"] = true,
["subeventSuffix"] = "_CAST_START",
["use_spellCount"] = false,
["percenthealth"] = {
"20",
},
["event"] = "Health",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["use_targetRequired"] = true,
["spellName"] = 163201,
["use_percenthealth"] = true,
["percenthealth_operator"] = {
"<=",
},
["unit"] = "target",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["unit"] = "player",
["use_spellName"] = true,
["spellName"] = 5308,
["genericShowOn"] = "showAlways",
["use_exact_spellName"] = false,
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["unit"] = "player",
["use_spellName"] = true,
["debuffType"] = "HELPFUL",
["genericShowOn"] = "showOnCooldown",
["use_exact_spellName"] = false,
["use_track"] = true,
["spellName"] = 5308,
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[3];\nend",
["activeTriggerMode"] = 2,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[112145] = false,
[112279] = false,
},
},
["use_class_and_spec"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["talent_extraOption"] = 0,
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["use_spec"] = true,
["covenant"] = {
["single"] = 2,
["multi"] = {
["1"] = true,
["4"] = true,
["3"] = true,
["0"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
[2] = true,
[3] = true,
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[71] = true,
},
},
["use_covenant"] = false,
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["parent"] = "Warrior » Emphasized Buffs",
["preferToUpdate"] = false,
["icon"] = true,
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["conditions"] = {
{
["check"] = {
["op"] = "<",
["checks"] = {
{
["value"] = 0,
["op"] = "<",
["variable"] = "show",
},
{
["value"] = 0,
["variable"] = "show",
},
},
["trigger"] = 2,
["variable"] = "insufficientResources",
["value"] = 1,
},
["linked"] = false,
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 2,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["progressSource"] = {
-1,
"",
},
["xOffset"] = 0,
["uid"] = "kitfwCk1okn",
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Execute",
["frameStrata"] = 3,
["alpha"] = 1,
["width"] = 34,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "alphaPulse",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["displayIcon"] = "135358",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["stickyDuration"] = false,
},
["Fury Warriorr: Bladestorm Buff"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"227847",
},
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 6,
["multi"] = {
[6] = true,
[119139] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["spellknown"] = 46924,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Fury Warrior Buffs",
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "JinbsV(YaU)",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warriorr: Bladestorm Buff",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 28,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Fury Warrior: Champion's Might"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["rem"] = "0",
["useGroup_count"] = false,
["ownOnly"] = true,
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["matchesShowOn"] = "showOnActive",
["duration"] = "1",
["useName"] = false,
["custom_hide"] = "timed",
["useExactSpellId"] = true,
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["auranames"] = {
"311193",
},
["unevent"] = "timed",
["event"] = "Health",
["debuffType"] = "HARMFUL",
["unit"] = "target",
["auraspellids"] = {
"376080",
},
["spellIds"] = {
},
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["remOperator"] = ">",
["combineMatches"] = "showLowest",
["buffShowOn"] = "showOnActive",
["useRem"] = false,
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = 1,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.2,
["glow"] = true,
["glowDuration"] = 1,
["glowType"] = "Pixel",
["glowLength"] = 8,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["type"] = "subglow",
["glowScale"] = 1,
["useGlowColor"] = true,
["glowXOffset"] = 0,
["glowThickness"] = 1,
["glowLines"] = 4,
["glowBorder"] = true,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112180] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["faction"] = {
["multi"] = {
},
},
["item_bonusid_equipped"] = "",
["pvptalent"] = {
["multi"] = {
},
},
["use_item_bonusid_equipped"] = false,
["size"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["icon"] = true,
["source"] = "import",
["keepAspectRatio"] = false,
["cooldown"] = true,
["conditions"] = {
},
["authorOptions"] = {
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["uid"] = "bwRGVR7x4Bx",
["parent"] = "Fury Warrior Buffs",
["width"] = 28,
["anchorFrameParent"] = false,
["selfPoint"] = "CENTER",
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Champion's Might",
["frameStrata"] = 3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["stickyDuration"] = false,
["config"] = {
},
["inverse"] = false,
["adjustedMin"] = "",
["displayIcon"] = 3565453,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior: Charge"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 100,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Charge",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_text_format_p_time_precision"] = 1,
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -3,
},
},
["height"] = 28.6,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 14,
["multi"] = {
[17] = true,
[16] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "EX2w8zgG9jn",
["parent"] = "Warrior » Secondary Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Charge",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 28.7,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["op"] = ">",
["variable"] = "AND",
["checks"] = {
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
{
["trigger"] = 1,
["op"] = ">",
["value"] = "0",
["variable"] = "charges",
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "cooldownEdge",
},
{
["value"] = false,
["property"] = "cooldownSwipe",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["value"] = "0",
["variable"] = "charges",
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Ignore Pain"] = {
["sparkWidth"] = 10,
["text2Point"] = "TOP",
["iconSource"] = -1,
["text1FontSize"] = 15,
["authorOptions"] = {
{
["type"] = "input",
["useDesc"] = false,
["width"] = 1,
["default"] = "Warrior » Primary Bar",
["multiline"] = false,
["name"] = "Class Bar Name Pattern",
["length"] = 10,
["key"] = "classBarNamePattern",
["useLength"] = false,
},
{
["type"] = "number",
["useDesc"] = false,
["default"] = 243,
["name"] = "Minimum Width",
["key"] = "minWidth",
["width"] = 1,
},
},
["adjustedMax"] = "",
["yOffset"] = -161,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["actions"] = {
["start"] = {
["do_custom"] = false,
},
["init"] = {
["custom"] = "function aura_env:Init()\n    local ctx = self.region.arcCustomContext\n    if not ctx then\n        ctx = {}\n        self.region.arcCustomContext = ctx\n    end\n    \n    local classBar = self:GetClassBarName()\n    local parentRegion = WeakAuras.GetRegion(classBar)\n    if not parentRegion then\n        print(self.id, \"could not find WA:\", classBar)\n        return\n    end\n    \n    ctx.parentRegion = parentRegion\n    ctx.minWidth = self.config.minWidth\n    ctx.region = self.region\n    \n    if not ctx.hooked then\n        hooksecurefunc(ctx.parentRegion, \"SetWidth\", function(_, width)\n                ctx.region:SetRegionWidth(max(ctx.minWidth, width))\n        end)\n        ctx.hooked = true\n    end\nend\n\nfunction aura_env:GetClassBarName()\n    local classNames = {\"Warrior\", \"Paladin\", \"Hunter\", \"Rogue\", \"Priest\", \"Death Knight\",\n    \"Shaman\", \"Mage\", \"Warlock\", \"Monk\", \"Druid\", \"Demon Hunter\",\"Evoker\"}\n    local class = select(2, UnitClass(\"player\"))\n    for i, name in ipairs(classNames) do\n        if class == name:gsub(\" \", \"\"):upper() then\n            return self.config.classBarNamePattern:format(name)\n        end\n    end\nend\n\naura_env:Init()",
["do_custom"] = true,
},
["finish"] = {
["do_custom"] = false,
},
},
["icon_color"] = {
1,
1,
1,
1,
},
["text1Enabled"] = true,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["barColor"] = {
0.92549026012421,
0.50980395078659,
0,
1,
},
["desaturate"] = false,
["glowColor"] = {
1,
1,
1,
1,
},
["text1Point"] = "CENTER",
["sparkOffsetY"] = 0,
["text2FontFlags"] = "OUTLINE",
["gradientOrientation"] = "HORIZONTAL",
["load"] = {
["spec_position"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
},
},
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
},
},
["use_class"] = true,
["size"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["use_spec"] = true,
["use_class_and_spec"] = true,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["use_never"] = false,
["zoneIds"] = "",
},
["glowType"] = "buttonOverlay",
["smoothProgress"] = false,
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["text2FontSize"] = 15,
["texture"] = "Atrocity",
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["auto"] = true,
["tocversion"] = 110200,
["text2Enabled"] = true,
["sparkColor"] = {
1,
1,
1,
1,
},
["sparkOffsetX"] = 0,
["parent"] = "Warrior",
["customText"] = "function()\n    if not aura_env.calc then\n        return \"\", \"\"\n    end\n    \n    local currentIP = aura_env.calc.currentIP\n    local percentOfCap = aura_env.calc.percentOfCap \n    local text1 = currentIP\n    local text2 = percentOfCap\n    return text1, text2\nend",
["preferToUpdate"] = false,
["information"] = {
["ignoreOptionsEventErrors"] = true,
["forceEvents"] = true,
["debugLog"] = false,
},
["cooldownSwipe"] = true,
["color"] = {
1,
1,
1,
1,
},
["customTextUpdate"] = "event",
["cooldownEdge"] = false,
["barColor2"] = {
1,
1,
0,
1,
},
["triggers"] = {
{
["trigger"] = {
["duration"] = "1",
["unit"] = "player",
["names"] = {
},
["use_absorbMode"] = true,
["subeventPrefix"] = "SPELL",
["debuffType"] = "HELPFUL",
["matchesShowOn"] = "showAlways",
["type"] = "custom",
["custom"] = "function(arg1, arg2)\n    if arg1 == \"UNIT_AURA\" and arg2 ~= \"player\" then\n        return false\n    end\n    \n    local currentIP = select(16, WA_GetUnitBuff(\"player\", 190456))\n    aura_env.currentIP = currentIP or 0\n    \n    -- Only return true if the buff is present\n    return currentIP ~= nil\nend",
["auraspellids"] = {
"190456",
},
["events"] = "UNIT_AURA, PLAYER_EQUIPMENT_CHANGED, PLAYER_TALENT_UPDATE",
["custom_type"] = "status",
["event"] = "Chat Message",
["subeventSuffix"] = "_CAST_START",
["customDuration"] = "function()\n    local maxHP = UnitHealthMax(\"player\")\n    local currentIP = aura_env.currentIP or 0\n    local descriptionAmount = maxHP * 30 / 100\n    local IPCap = math.floor(descriptionAmount)\n    local additionalAbsorb = IPCap - currentIP\n    \n    if additionalAbsorb < 0 then\n        IPCap = currentIP\n        additionalAbsorb = 0\n    end\n    \n    local percentOfCap = (currentIP / IPCap) * 100\n    local percentOfMaxHP = (currentIP / maxHP) * 100\n    \n    aura_env.calc = {\n        currentIP = currentIP,\n        castIP = descriptionAmount,\n        IPCap = IPCap,\n        percentOfCap = percentOfCap,\n        additionalAbsorb = additionalAbsorb,\n        percentOfMaxHP = percentOfMaxHP\n    }\n    \n    return percentOfCap, 100, true\nend",
["unevent"] = "timed",
["spellIds"] = {
},
["useExactSpellId"] = true,
["check"] = "event",
["custom_hide"] = "custom",
["use_unit"] = true,
["dynamicDuration"] = false,
},
["untrigger"] = {
["custom"] = "function(arg1, arg2)\n    if arg1 == \"UNIT_AURA\" and arg2 ~= \"player\" then\n        return false\n    end\n    \n    local currentIP = aura_env.currentIP\n    \n    -- Untrigger when the buff no longer exists\n    return currentIP == nil or currentIP == 0\nend",
},
},
{
["trigger"] = {
["type"] = "aura2",
["useExactSpellId"] = true,
["unit"] = "player",
["auraspellids"] = {
"190456",
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["text2"] = "%c2",
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["colorR"] = 1,
["duration_type"] = "seconds",
["colorA"] = 1,
["colorG"] = 1,
["type"] = "none",
["easeType"] = "none",
["scaley"] = 1,
["alpha"] = 0,
["colorB"] = 1,
["y"] = 0,
["x"] = 0,
["scalex"] = 1,
["easeStrength"] = 3,
["colorFunc"] = "function(progress, r1, g1, b1, a1, r2, g2, b2, a2)\n    return WeakAuras.GetHSVTransition(progress, r1, g1, b1, a1, r2, g2, b2, a2)\nend\n",
["rotate"] = 0,
["colorType"] = "straightHSV",
["use_color"] = false,
},
["main"] = {
["colorR"] = 1,
["scalex"] = 1,
["alphaType"] = "straight",
["colorB"] = 1,
["colorG"] = 1,
["alphaFunc"] = "function(progress, start, delta)\n    return start + (progress * delta)\nend\n",
["use_translate"] = false,
["use_alpha"] = false,
["type"] = "none",
["colorA"] = 1,
["easeType"] = "none",
["translateFunc"] = "function(progress, startX, startY, deltaX, deltaY)\n    return startX + (progress * deltaX), startY + (progress * deltaY)\nend\n",
["scaley"] = 1,
["alpha"] = 0,
["use_color"] = false,
["y"] = 0,
["x"] = 0,
["easeStrength"] = 3,
["translateType"] = "straightTranslate",
["colorFunc"] = "function(progress, r1, g1, b1, a1, r2, g2, b2, a2)\n    local angle = (progress * 2 * math.pi) - (math.pi / 2)\n    local newProgress = ((math.sin(angle) + 1)/2);\n    return r1 + (newProgress * (r2 - r1)),\n    g1 + (newProgress * (g2 - g1)),\n    b1 + (newProgress * (b2 - b1)),\n    a1 + (newProgress * (a2 - a1))\nend",
["rotate"] = 0,
["colorType"] = "custom",
["duration_type"] = "seconds",
},
["finish"] = {
["colorR"] = 1,
["duration_type"] = "seconds",
["colorA"] = 1,
["colorG"] = 1,
["type"] = "none",
["easeType"] = "none",
["scaley"] = 1,
["alpha"] = 0,
["colorB"] = 1,
["y"] = 0,
["x"] = 0,
["scalex"] = 1,
["easeStrength"] = 3,
["colorFunc"] = "\n\n",
["rotate"] = 0,
["colorType"] = "custom",
["use_color"] = true,
},
},
["backdropInFront"] = false,
["alpha"] = 1,
["text1FontFlags"] = "OUTLINE",
["stickyDuration"] = false,
["uid"] = "iICtYzwstqF",
["anchorFrameType"] = "SCREEN",
["sparkRotationMode"] = "AUTO",
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["anchor_area"] = "bar",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text"] = "%c2%%",
["text_text_format_c2_round_type"] = "floor",
["text_selfPoint"] = "AUTO",
["text_text_format_c2_pad_max"] = 8,
["text_fixedWidth"] = 64,
["text_text_format_c2_pad"] = false,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_c2_decimal_precision"] = 0,
["type"] = "subtext",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_automaticWidth"] = "Auto",
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_text_format_c2_format"] = "Number",
["text_visible"] = true,
["text_text_format_c2_pad_mode"] = "left",
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_RIGHT",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
},
{
["text_shadowXOffset"] = 0,
["text_text"] = "%2.p",
["text_text_format_2.p_time_format"] = 0,
["text_text_format_c1_decimal_precision"] = 0,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_2.p_time_legacy_floor"] = false,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["text_text_format_2.p_time_precision"] = 1,
["text_text_format_c1_big_number_format"] = "AbbreviateNumbers",
["text_text_format_2.p_format"] = "timed",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["type"] = "subtext",
["text_text_format_2.p_time_mod_rate"] = true,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_visible"] = true,
["text_shadowYOffset"] = 0,
["text_text_format_2.p_time_dynamic_threshold"] = 3,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_text_format_c1_round_type"] = "floor",
["text_text_format_c1_format"] = "BigNumber",
["anchor_point"] = "INNER_LEFT",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["rotateText"] = "NONE",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%c1",
["text_text_format_2.p_time_format"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_text_format_2.p_time_legacy_floor"] = true,
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["rotateText"] = "NONE",
["text_text_format_p_decimal_precision"] = 0,
["text_color"] = {
1,
1,
1,
1,
},
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_text_format_p_round_type"] = "floor",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["text_text_format_2.p_time_precision"] = 1,
["text_text_format_2.p_format"] = "timed",
["type"] = "subtext",
["text_anchorXOffset"] = 0,
["text_font"] = "Expressway",
["text_text_format_2.p_time_dynamic_threshold"] = 60,
["text_visible"] = false,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_c1_format"] = "none",
["text_text_format_p_time_format"] = 0,
["anchor_point"] = "INNER_CENTER",
["text_text_format_p_time_precision"] = 1,
["text_text_format_2.p_time_mod_rate"] = true,
["text_text_format_p_format"] = "Number",
},
},
["height"] = 8,
["textureSource"] = "LSM",
["xOffset"] = 0,
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["id"] = "Prot Warrior: Ignore Pain",
["text2Containment"] = "OUTSIDE",
["source"] = "import",
["text1Color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["text1Containment"] = "INSIDE",
["text2Color"] = {
1,
1,
1,
1,
},
["useglowColor"] = false,
["borderInFront"] = false,
["glow"] = false,
["icon_side"] = "RIGHT",
["text1"] = "%c1",
["icon"] = false,
["sparkHeight"] = 30,
["text2Font"] = "Friz Quadrata TT",
["spark"] = false,
["cooldownTextDisabled"] = true,
["text1Font"] = "Friz Quadrata TT",
["adjustedMin"] = "",
["sparkHidden"] = "NEVER",
["backdropColor"] = {
1,
1,
1,
0,
},
["frameStrata"] = 3,
["width"] = 145,
["backgroundColor"] = {
0.2431372702121735,
0.2431372702121735,
0.2431372702121735,
1,
},
["config"] = {
["classBarNamePattern"] = "Warrior » Primary Bar",
["minWidth"] = 145,
},
["inverse"] = false,
["zoom"] = 0,
["orientation"] = "HORIZONTAL",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "value",
["value"] = "100",
},
["changes"] = {
{
["value"] = {
1,
0,
0,
1,
},
["property"] = "barColor",
},
},
},
},
["cooldown"] = true,
["borderBackdrop"] = "None",
},
["Warrior: Wrecking Throw"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["names"] = {
},
["type"] = "spell",
["unit"] = "player",
["unevent"] = "auto",
["subeventPrefix"] = "SPELL",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Wrecking Throw",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["subeventSuffix"] = "_CAST_START",
["duration"] = "1",
["use_track"] = true,
["spellName"] = 384110,
},
["untrigger"] = {
["genericShowOn"] = "showOnCooldown",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28.6,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 18,
["multi"] = {
[14] = true,
[18] = true,
},
},
["use_class_and_spec"] = false,
["use_class"] = true,
["use_spellknown"] = true,
["use_never"] = false,
["use_petbattle"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spellknown"] = 384110,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28.7,
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["authorOptions"] = {
},
["anchorFrameParent"] = false,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Wrecking Throw",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "vsKR0ZsBxIr",
["inverse"] = true,
["parent"] = "Warrior » Secondary Bar",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078432083129883,
0.2352941334247589,
0.2313725650310516,
1,
},
["property"] = "color",
},
},
},
},
["cooldown"] = true,
["stickyDuration"] = false,
},
["Arms Warrior: Execute (Massacre)"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -113,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = true,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["unit"] = "target",
["use_track"] = true,
["use_charges"] = false,
["use_unit"] = true,
["use_trackcharge"] = false,
["spellName"] = 163201,
["use_absorbMode"] = true,
["type"] = "unit",
["use_absorbHealMode"] = true,
["use_targetRequired"] = true,
["use_spellCount"] = false,
["percenthealth"] = {
"35",
},
["event"] = "Health",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
["use_percenthealth"] = true,
["percenthealth_operator"] = {
"<=",
},
["names"] = {
},
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["unit"] = "player",
["use_spellName"] = true,
["spellName"] = 281000,
["genericShowOn"] = "showAlways",
["use_exact_spellName"] = false,
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "unit",
["use_absorbHealMode"] = true,
["talent"] = {
["single"] = 9,
["multi"] = {
[112136] = true,
},
},
["spec"] = 1,
["event"] = "Talent Known",
["unit"] = "player",
["use_class"] = true,
["use_absorbMode"] = true,
["use_spec"] = true,
["use_talent"] = false,
["use_unit"] = true,
["class"] = "WARRIOR",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"280776",
"52437",
},
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["unit"] = "player",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[4];\nend",
["activeTriggerMode"] = 2,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["glowXOffset"] = 0,
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowLength"] = 10,
["glow"] = true,
["glowDuration"] = 1,
["useGlowColor"] = false,
["glowScale"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_shadowXOffset"] = 0,
["text_text"] = "FREE",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_text_format_p_time_precision"] = 1,
["text_color"] = {
0,
1,
0.10980392156863,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
["text_text_format_p_time_format"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_fontType"] = "OUTLINE",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchor_point"] = "CENTER",
["text_fontSize"] = 10,
["anchorXOffset"] = 0,
["text_anchorYOffset"] = -15,
},
},
["height"] = 34,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[112145] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["use_class_and_spec"] = true,
["talent_extraOption"] = 0,
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["use_spec"] = true,
["covenant"] = {
["single"] = 2,
["multi"] = {
["1"] = true,
["4"] = true,
["3"] = true,
["0"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
[2] = true,
[3] = true,
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
},
},
["use_covenant"] = false,
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["color"] = {
1,
1,
1,
1,
},
["preferToUpdate"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["conditions"] = {
{
["check"] = {
["op"] = "<",
["checks"] = {
{
["value"] = 0,
["op"] = "<",
["variable"] = "show",
},
{
["trigger"] = 4,
["variable"] = "show",
["value"] = 0,
},
},
["trigger"] = 2,
["variable"] = "insufficientResources",
["value"] = 1,
},
["linked"] = false,
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
{
["property"] = "sub.2.glow",
},
},
},
{
["check"] = {
["trigger"] = 4,
["variable"] = "show",
["value"] = 1,
},
["linked"] = true,
["changes"] = {
{
["value"] = true,
["property"] = "sub.4.text_visible",
},
},
},
{
["check"] = {
["trigger"] = 3,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = 37,
["property"] = "yOffsetRelative",
},
},
},
},
["progressSource"] = {
-1,
"",
},
["xOffset"] = 0,
["uid"] = "wYKdPmBDlMl",
["useCooldownModRate"] = true,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Execute (Massacre)",
["alpha"] = 1,
["frameStrata"] = 3,
["width"] = 34,
["parent"] = "Warrior » Emphasized Buffs",
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "alphaPulse",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["displayIcon"] = "135358",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["stickyDuration"] = false,
},
["Prot Warrior: Wrecked"] = {
["iconSource"] = -1,
["parent"] = "Prot Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["ownOnly"] = true,
["unit"] = "target",
["use_tooltip"] = false,
["debuffType"] = "HARMFUL",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["custom_hide"] = "timed",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["subeventSuffix"] = "_CAST_START",
["matchesShowOn"] = "showOnActive",
["duration"] = "1",
["spellIds"] = {
},
["type"] = "aura2",
["auranames"] = {
"447513",
},
["combineMatches"] = "showLowest",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["buffShowOn"] = "showOnActive",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_format"] = "timed",
["anchorXOffset"] = 0,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_format"] = 0,
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = true,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["text_text_format_p_time_dynamic_threshold"] = 60,
["anchorYOffset"] = 0,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[2] = true,
[112150] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["race"] = {
["multi"] = {
},
},
["use_herotalent"] = false,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["herotalent"] = {
["multi"] = {
[117415] = true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["zoneIds"] = "",
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["selfPoint"] = "CENTER",
["color"] = {
1,
1,
1,
1,
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["keepAspectRatio"] = false,
["desaturate"] = false,
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Wrecked",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["cooldownTextDisabled"] = false,
["uid"] = "8j2vWtESrhA",
["inverse"] = false,
["icon"] = true,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Merciless Bonegrinder"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["duration"] = "1",
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"346574",
},
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[112117] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["parent"] = "Arms Warrior Buffs",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Merciless Bonegrinder",
["frameStrata"] = 3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "HUjn2OgXuRD",
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior » Primary Bar"] = {
["arcLength"] = 360,
["controlledChildren"] = {
"Arms Warrior: Mortal Strike",
"Arms Warrior: Overpower",
"Arms Warrior: Cleave",
"Arms Warrior: Skullsplitter",
"Arms Warrior: Colossus Smash",
"Arms Warrior: Demolish",
"Fury Warrior: Bloodthirst",
"Fury Warrior: Onslaught",
"Fury Warrior: Raging Blow",
"Fury Warrior: Thunder Clap",
"Fury Warrior: Odyn's Fury",
"Fury Warrior: Ravager",
"Fury Warrior: Bladestorm",
"Prot Warrior: Shield Slam",
"Prot Warrior: Thunder Clap",
"Prot Warrior: Shield Charge",
"Prot Warrior: Shield Block",
"Prot Warrior: Demolish",
"Prot Warrior: Demoralizing Shout",
"Warrior: Thunderous Roar",
"Prot Warrior: Ravager",
"Warrior: Champion's Spear",
"Arms Warrior: Ravager",
"Fury Warrior: Recklessness",
"Arms Warrior: Bladestorm",
"Warrior: Avatar",
"Warrior: Trinket",
"Warrior: Trinket 2",
"Warrior: Unyielding Netherprism Stacks",
"Warrior: Racial (Troll)",
"Warrior: Racial (Orc)",
"Warrior: Racial (Mag'har Orc)",
},
["borderBackdrop"] = "Blizzard Tooltip",
["parent"] = "Warrior",
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["gridType"] = "RD",
["fullCircle"] = true,
["rowSpace"] = 1,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["subeventPrefix"] = "SPELL",
["unit"] = "player",
["event"] = "Health",
["names"] = {
},
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["radius"] = 200,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["align"] = "CENTER",
["alpha"] = 1,
["authorOptions"] = {
},
["useLimit"] = false,
["rotation"] = 0,
["space"] = 3,
["anchorPoint"] = "CENTER",
["subRegions"] = {
},
["stagger"] = 0,
["grow"] = "HORIZONTAL",
["load"] = {
["talent"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["zoneIds"] = "",
},
["uid"] = "F6nx7cm7uV1",
["backdropColor"] = {
1,
1,
1,
0.5,
},
["borderInset"] = 1,
["animate"] = false,
["xOffset"] = -0.2,
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["stepAngle"] = 15,
["borderSize"] = 2,
["limit"] = 5,
["sortHybridTable"] = {
["Arms Warrior: Mortal Strike"] = false,
["Arms Warrior: Colossus Smash"] = false,
["Prot Warrior: Demolish"] = false,
["Warrior: Racial (Troll)"] = false,
["Warrior: Racial (Mag'har Orc)"] = false,
["Fury Warrior: Bloodthirst"] = false,
["Warrior: Racial (Orc)"] = false,
["Warrior: Avatar"] = false,
["Arms Warrior: Ravager"] = false,
["Fury Warrior: Bladestorm"] = false,
["Prot Warrior: Shield Block"] = false,
["Arms Warrior: Demolish"] = false,
["Warrior: Trinket 2"] = false,
["Arms Warrior: Skullsplitter"] = false,
["Arms Warrior: Cleave"] = false,
["Prot Warrior: Shield Charge"] = false,
["Prot Warrior: Ravager"] = false,
["Warrior: Thunderous Roar"] = false,
["Fury Warrior: Raging Blow"] = false,
["Fury Warrior: Ravager"] = false,
["Arms Warrior: Bladestorm"] = false,
["Warrior: Champion's Spear"] = false,
["Warrior: Unyielding Netherprism Stacks"] = false,
["Prot Warrior: Demoralizing Shout"] = false,
["Arms Warrior: Overpower"] = false,
["Fury Warrior: Recklessness"] = false,
["Prot Warrior: Shield Slam"] = false,
["Prot Warrior: Thunder Clap"] = false,
["Fury Warrior: Thunder Clap"] = false,
["Fury Warrior: Onslaught"] = false,
["Fury Warrior: Odyn's Fury"] = false,
["Warrior: Trinket"] = false,
},
["gridWidth"] = 5,
["constantFactor"] = "RADIUS",
["sort"] = "none",
["borderOffset"] = 4,
["selfPoint"] = "CENTER",
["tocversion"] = 110200,
["id"] = "Warrior » Primary Bar",
["regionType"] = "dynamicgroup",
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["config"] = {
},
["borderColor"] = {
0,
0,
0,
1,
},
["internalVersion"] = 86,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["yOffset"] = -215,
},
["Fury Warrior: Bloodthirst"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["subeventPrefix"] = "SPELL",
["use_showgcd"] = true,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["type"] = "spell",
["names"] = {
},
["subeventSuffix"] = "_CAST_START",
["use_unit"] = true,
["duration"] = "1",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Onslaught",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["unevent"] = "auto",
["use_absorbMode"] = true,
["use_track"] = true,
["spellName"] = 23881,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[382310] = true,
[112261] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_spellknown"] = false,
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 72,
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spellknown"] = 315720,
["size"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["preferToUpdate"] = false,
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["color"] = {
1,
1,
1,
1,
},
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["xOffset"] = 0,
["config"] = {
},
["parent"] = "Warrior » Primary Bar",
["width"] = 34,
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Bloodthirst",
["frameStrata"] = 3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["desaturate"] = false,
["uid"] = "BVYjm5F)jR)",
["inverse"] = true,
["internalVersion"] = 86,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellUsable",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "spellInRange",
["value"] = 0,
},
["changes"] = {
{
["value"] = {
0.8078431372549,
0.23529411764706,
0.23137254901961,
1,
},
["property"] = "color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["cooldown"] = true,
["icon"] = true,
},
["Fury Warrior: Racials"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["unit"] = "player",
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["names"] = {
"Overwhelming Power",
},
["event"] = "Health",
["unevent"] = "timed",
["subeventPrefix"] = "SPELL",
["useName"] = true,
["spellIds"] = {
},
["auranames"] = {
"26297",
"33697",
"273104",
"274740",
"274742",
"274739",
"274741",
"20572",
},
["ownOnly"] = true,
["combineMatches"] = "showLowest",
["matchesShowOn"] = "showOnActive",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "fade",
["easeStrength"] = 3,
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["preset"] = "slideright",
["easeStrength"] = 3,
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["text_text_format_p_time_precision"] = 1,
["text_text"] = "H",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_legacy_floor"] = false,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorYOffset"] = 0,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
0,
1,
0,
1,
},
["text_font"] = "Expressway",
["text_anchorYOffset"] = -3,
["text_shadowYOffset"] = 0,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_text_format_p_time_format"] = 0,
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_mod_rate"] = true,
},
},
["height"] = 28,
["load"] = {
["zoneIds"] = "",
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[257] = true,
[256] = true,
},
},
["talent"] = {
["single"] = 7,
["multi"] = {
[7] = true,
},
},
["use_class_and_spec"] = true,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["talent2"] = {
["multi"] = {
},
},
["race"] = {
["single"] = "Troll",
["multi"] = {
["Troll"] = true,
["Orc"] = true,
["DarkIronDwarf"] = true,
["MagharOrc"] = true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["use_race"] = false,
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["stickyDuration"] = false,
["xOffset"] = 0,
["cooldown"] = true,
["keepAspectRatio"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["parent"] = "Fury Warrior Buffs",
["uid"] = "XUXaY2vi9c9",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Racials",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["value"] = "274740",
["variable"] = "spellId",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274742",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "V",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274739",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "C",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "spellId",
["value"] = "274741",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.text_visible",
},
{
["value"] = "M",
["property"] = "sub.3.text_text",
},
},
["linked"] = true,
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior » Secondary Bar"] = {
["arcLength"] = 360,
["controlledChildren"] = {
"Prot Warrior: Taunt",
"Warrior: Charge",
"Warrior: Leap",
"Warrior: Intervene",
"Arms Warrior: Sweeping Strikes",
"Warrior: Impending Victory",
"Warrior: Shattering Throw",
"Warrior: Wrecking Throw",
"Warrior: Storm Bolt",
"Warrior: Shockwave",
"Warrior: Piercing Howl",
"Warrior: Fear",
"Warrior: Kick",
},
["borderBackdrop"] = "Blizzard Tooltip",
["parent"] = "Warrior",
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["gridType"] = "RD",
["fullCircle"] = true,
["rowSpace"] = 1,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["subeventPrefix"] = "SPELL",
["names"] = {
},
["event"] = "Health",
["unit"] = "player",
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["radius"] = 200,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["align"] = "CENTER",
["alpha"] = 1,
["authorOptions"] = {
},
["useLimit"] = false,
["rotation"] = 0,
["space"] = 3,
["anchorPoint"] = "CENTER",
["subRegions"] = {
},
["stagger"] = 0,
["grow"] = "HORIZONTAL",
["load"] = {
["talent"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["zoneIds"] = "",
},
["uid"] = "68L)tZXWCfI",
["backdropColor"] = {
1,
1,
1,
0.5,
},
["borderInset"] = 1,
["animate"] = false,
["xOffset"] = -0.2,
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["stepAngle"] = 15,
["borderSize"] = 2,
["limit"] = 5,
["sortHybridTable"] = {
["Warrior: Shockwave"] = false,
["Arms Warrior: Sweeping Strikes"] = false,
["Warrior: Fear"] = false,
["Warrior: Impending Victory"] = false,
["Warrior: Shattering Throw"] = false,
["Warrior: Charge"] = false,
["Warrior: Storm Bolt"] = false,
["Warrior: Kick"] = false,
["Warrior: Piercing Howl"] = false,
["Warrior: Wrecking Throw"] = false,
["Prot Warrior: Taunt"] = false,
["Warrior: Intervene"] = false,
["Warrior: Leap"] = false,
},
["gridWidth"] = 5,
["constantFactor"] = "RADIUS",
["sort"] = "none",
["borderOffset"] = 4,
["selfPoint"] = "CENTER",
["tocversion"] = 110200,
["id"] = "Warrior » Secondary Bar",
["regionType"] = "dynamicgroup",
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["config"] = {
},
["borderColor"] = {
0,
0,
0,
1,
},
["internalVersion"] = 86,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["yOffset"] = -249,
},
["Prot Warrior Defensives"] = {
["arcLength"] = 360,
["controlledChildren"] = {
"Prot Warrior: Externals",
"Prot Warrior: Absorbs",
"Prot Warrior: Shield Wall",
"Prot Warrior: Spell Reflection Buff",
"Prot Warrior: Last Stand",
"Prot Warrior: Battle-Scarred Veteran",
"Prot Warrior: Demoralizing Shout Debuff",
"Prot Warrior: Outburst",
"Prot Warrior: Devouring Nucleus Debuff",
"Prot Warrior: Tank Cloak",
},
["borderBackdrop"] = "Blizzard Tooltip",
["authorOptions"] = {
},
["preferToUpdate"] = false,
["yOffset"] = -106,
["anchorPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["space"] = 3,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["names"] = {
},
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["radius"] = 200,
["useLimit"] = false,
["align"] = "CENTER",
["alpha"] = 1,
["groupIcon"] = "626008",
["stagger"] = 0,
["rotation"] = 0,
["internalVersion"] = 86,
["rowSpace"] = 1,
["subRegions"] = {
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["gridType"] = "RD",
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["uid"] = "DeED7tgq1da",
["backdropColor"] = {
1,
1,
1,
0.5,
},
["config"] = {
},
["source"] = "import",
["grow"] = "HORIZONTAL",
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["stepAngle"] = 15,
["borderSize"] = 2,
["sort"] = "none",
["sortHybridTable"] = {
["Prot Warrior: Outburst"] = false,
["Prot Warrior: Absorbs"] = false,
["Prot Warrior: Battle-Scarred Veteran"] = false,
["Prot Warrior: Devouring Nucleus Debuff"] = false,
["Prot Warrior: Tank Cloak"] = false,
["Prot Warrior: Demoralizing Shout Debuff"] = false,
["Prot Warrior: Externals"] = false,
["Prot Warrior: Shield Wall"] = false,
["Prot Warrior: Spell Reflection Buff"] = false,
["Prot Warrior: Last Stand"] = false,
},
["frameStrata"] = 1,
["constantFactor"] = "RADIUS",
["parent"] = "Warrior » Buff Bar",
["borderOffset"] = 4,
["limit"] = 5,
["tocversion"] = 110200,
["id"] = "Prot Warrior Defensives",
["regionType"] = "dynamicgroup",
["gridWidth"] = 5,
["anchorFrameType"] = "SCREEN",
["animate"] = false,
["borderInset"] = 1,
["fullCircle"] = true,
["selfPoint"] = "CENTER",
["conditions"] = {
},
["information"] = {
},
["xOffset"] = 0.01,
},
["Prot Warrior: Shield Wall "] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_absorbMode"] = true,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["names"] = {
},
["type"] = "spell",
["unit"] = "player",
["unevent"] = "auto",
["subeventPrefix"] = "SPELL",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Shield Wall",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["subeventSuffix"] = "_CAST_START",
["duration"] = "1",
["use_track"] = true,
["spellName"] = 871,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"265144",
},
["unit"] = "player",
["type"] = "aura2",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["glow"] = false,
["useGlowColor"] = false,
["glowType"] = "buttonOverlay",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["type"] = "subglow",
["glowThickness"] = 1,
["glowDuration"] = 1,
["glowXOffset"] = 0,
["glowScale"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
{
["text_text_format_p_time_format"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_shadowXOffset"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_shadowColor"] = {
0,
0,
0,
0,
},
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_precision"] = 1,
},
},
["height"] = 26,
["load"] = {
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[71] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[384361] = true,
[112176] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_never"] = false,
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
["WARRIOR"] = true,
},
},
["talent2"] = {
},
["size"] = {
["multi"] = {
},
},
},
["useCooldownModRate"] = true,
["useAdjustededMax"] = false,
["selfPoint"] = "CENTER",
["source"] = "import",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["authorOptions"] = {
},
["useAdjustededMin"] = false,
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["regionType"] = "icon",
["xOffset"] = 0,
["config"] = {
},
["progressSource"] = {
-1,
"",
},
["width"] = 26,
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Shield Wall ",
["desaturate"] = false,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["parent"] = "Warrior » Top Bar",
["uid"] = "tUYWNQA(pmy",
["inverse"] = true,
["internalVersion"] = 86,
["conditions"] = {
{
["check"] = {
["trigger"] = -2,
["op"] = ">",
["variable"] = "AND",
["checks"] = {
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
{
["trigger"] = 1,
["op"] = ">",
["variable"] = "charges",
["value"] = "0",
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "cooldownEdge",
},
{
["value"] = false,
["property"] = "cooldownSwipe",
},
},
},
{
["check"] = {
["trigger"] = 1,
["op"] = "==",
["variable"] = "charges",
["value"] = "0",
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior"] = {
["controlledChildren"] = {
"Warrior » Primary Bar",
"Warrior » Secondary Bar",
"Warrior » Top Bar",
"Warrior » Emphasized Buffs",
"Warrior » Buff Bar",
"Warrior » Spell Alerts",
"Warrior » PvP Bar",
"Warrior: Current Stance",
"Prot Warrior: Stance",
"Warrior: Rage Bar",
"Warrior: Rallying Cry CD",
"Warrior: Find Self",
"Fury Warrior: Enrage Timer",
"Arms Warrior: Swing Timer",
"Prot Warrior: Ignore Pain",
"Prot Warrior: Shield Block Timer",
},
["borderBackdrop"] = "Blizzard Tooltip",
["authorOptions"] = {
},
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["anchorPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["subeventPrefix"] = "SPELL",
["names"] = {
},
["event"] = "Health",
["unit"] = "player",
},
["untrigger"] = {
},
},
},
["internalVersion"] = 86,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["subRegions"] = {
},
["load"] = {
["talent"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["backdropColor"] = {
1,
1,
1,
0.5,
},
["source"] = "import",
["scale"] = 1,
["border"] = false,
["borderEdge"] = "Square Full White",
["regionType"] = "group",
["borderSize"] = 2,
["borderOffset"] = 4,
["borderInset"] = 1,
["tocversion"] = 110200,
["id"] = "Warrior",
["selfPoint"] = "CENTER",
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["xOffset"] = 0,
["config"] = {
},
["frameStrata"] = 1,
["uid"] = "Q2VfaG1N7)F",
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
},
["yOffset"] = 0,
},
["Arms Warrior: Potion"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
"3710924",
},
["auranames"] = {
"431932",
"431925",
},
["unit"] = "player",
["event"] = "Health",
["useExactSpellId"] = false,
["subeventSuffix"] = "_CAST_START",
["matchesShowOn"] = "showOnActive",
["spellIds"] = {
},
["type"] = "aura2",
["unevent"] = "timed",
["combineMatches"] = "showLowest",
["subeventPrefix"] = "SPELL",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\n    return t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "fade",
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "slideright",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[72] = true,
[577] = true,
[253] = true,
[103] = true,
[581] = true,
[259] = true,
[268] = true,
[250] = true,
[254] = true,
[260] = true,
[71] = true,
[73] = true,
[104] = true,
[261] = true,
[269] = true,
[251] = true,
[66] = true,
},
},
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
["itemequiped"] = {
158712,
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["race"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["keepAspectRatio"] = false,
["parent"] = "Arms Warrior Buffs",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Potion",
["alpha"] = 1,
["frameStrata"] = 3,
["width"] = 28,
["zoom"] = 0.3,
["uid"] = "xWdnWi)YN(W",
["inverse"] = false,
["stickyDuration"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warrior: Unyielding Netherprism"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["custom_hide"] = "timed",
["showClones"] = true,
["type"] = "aura2",
["use_debuffClass"] = false,
["auraspellids"] = {
"1239675",
},
["useExactSpellId"] = false,
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["ownOnly"] = true,
["unit"] = "player",
["auranames"] = {
"1233556",
},
["spellIds"] = {
},
["useName"] = true,
["subeventSuffix"] = "_CAST_START",
["combineMatches"] = "showLowest",
["names"] = {
"Aspect of the Eagle",
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["pvptalent"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["itemequiped"] = {
242396,
},
["faction"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Fury Warrior Buffs",
["authorOptions"] = {
},
["icon"] = true,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slidebottom",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
},
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warrior: Unyielding Netherprism",
["alpha"] = 1,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "Lgww)15P5K3",
["inverse"] = false,
["keepAspectRatio"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Prot Warrior: Signet of the Priory"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["spellId"] = {
"49206",
},
["auranames"] = {
"443531",
},
["duration"] = "25",
["use_sourceNpcId"] = false,
["use_totemType"] = true,
["spellName"] = {
"",
},
["use_debuffClass"] = false,
["subeventSuffix"] = "_SUMMON",
["event"] = "Combat Log",
["use_spellId"] = true,
["use_sourceUnit"] = true,
["combineMatches"] = "showLowest",
["use_track"] = true,
["useGroup_count"] = false,
["use_absorbMode"] = true,
["genericShowOn"] = "showOnCooldown",
["use_unit"] = true,
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["unit"] = "player",
["type"] = "aura2",
["custom_hide"] = "timed",
["unevent"] = "timed",
["subeventPrefix"] = "SPELL",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_genericShowOn"] = true,
["totemType"] = 1,
["realSpellName"] = "",
["use_spellName"] = false,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["matchesShowOn"] = "showOnActive",
["useName"] = true,
["sourceUnit"] = "player",
["use_sourceName"] = false,
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_never"] = false,
["class"] = {
["single"] = "DEATHKNIGHT",
["multi"] = {
["DEATHKNIGHT"] = true,
},
},
["role"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[252] = true,
},
},
["talent"] = {
["multi"] = {
[96311] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["race"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["zoneIds"] = "",
["itemequiped"] = {
219308,
},
["faction"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 28,
["source"] = "import",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["displayIcon"] = 458967,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["keepAspectRatio"] = false,
["config"] = {
},
["stickyDuration"] = false,
["anchorFrameParent"] = false,
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["zoom"] = 0.3,
["auto"] = false,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Signet of the Priory",
["cooldownTextDisabled"] = false,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["authorOptions"] = {
},
["uid"] = "BvlAUTJjZsZ",
["inverse"] = false,
["parent"] = "Prot Warrior Buffs",
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Araz's Ritual Forge"] = {
["iconSource"] = -1,
["parent"] = "Arms Warrior Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["ownOnly"] = true,
["names"] = {
"Aspect of the Eagle",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["auraspellids"] = {
"459864",
},
["custom_hide"] = "timed",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["matchesShowOn"] = "showOnActive",
["useExactSpellId"] = false,
["auranames"] = {
"1232802",
},
["spellIds"] = {
},
["type"] = "aura2",
["subeventSuffix"] = "_CAST_START",
["combineMatches"] = "showLowest",
["unit"] = "player",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slidebottom",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["use_petbattle"] = false,
["class"] = {
["single"] = "HUNTER",
["multi"] = {
["HUNTER"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["use_itemequiped"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[255] = true,
},
},
["talent"] = {
["multi"] = {
[100564] = true,
[126326] = true,
},
},
["spec"] = {
["single"] = 3,
["multi"] = {
[3] = true,
},
},
["role"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["size"] = {
["multi"] = {
},
},
["itemequiped"] = {
242402,
},
["ingroup"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["color"] = {
1,
1,
1,
1,
},
["progressSource"] = {
-1,
"",
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["selfPoint"] = "CENTER",
["authorOptions"] = {
},
["uid"] = "zOS)KGo6heB",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Araz's Ritual Forge",
["frameStrata"] = 3,
["alpha"] = 1,
["width"] = 28,
["zoom"] = 0.3,
["config"] = {
},
["inverse"] = false,
["icon"] = true,
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Warrior » Top Bar"] = {
["grow"] = "LEFT",
["controlledChildren"] = {
"Arms Warrior: Ignore Pain",
"Warrior: Spell Reflection",
"Arms Warrior: Die by the Sword",
"Fury Warrior: Enraged Regeneration",
"Warrior: Bitter Immunity",
"Prot Warrior: Last Stand ",
"Prot Warrior: Shield Wall ",
},
["borderBackdrop"] = "Blizzard Tooltip",
["authorOptions"] = {
},
["preferToUpdate"] = false,
["groupIcon"] = "626008",
["gridType"] = "RD",
["fullCircle"] = true,
["space"] = 3,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["subeventPrefix"] = "SPELL",
["names"] = {
},
["event"] = "Health",
["unit"] = "player",
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["internalVersion"] = 86,
["gridWidth"] = 5,
["selfPoint"] = "RIGHT",
["align"] = "CENTER",
["rotation"] = 0,
["radius"] = 200,
["anchorPoint"] = "TOPRIGHT",
["stagger"] = 0,
["useLimit"] = true,
["parent"] = "Warrior",
["subRegions"] = {
},
["uid"] = "PqW(K1h204D",
["config"] = {
},
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["arcLength"] = 360,
["backdropColor"] = {
1,
1,
1,
0.5,
},
["yOffset"] = 15,
["animate"] = false,
["frameStrata"] = 1,
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["regionType"] = "dynamicgroup",
["borderSize"] = 2,
["sort"] = "none",
["stepAngle"] = 15,
["limit"] = 8,
["anchorFrameParent"] = false,
["constantFactor"] = "RADIUS",
["anchorFrameFrame"] = "ElvUF_Player",
["borderOffset"] = 4,
["rowSpace"] = 1,
["tocversion"] = 110200,
["id"] = "Warrior » Top Bar",
["source"] = "import",
["alpha"] = 1,
["anchorFrameType"] = "SELECTFRAME",
["sortHybridTable"] = {
["Prot Warrior: Last Stand "] = false,
["Warrior: Bitter Immunity"] = false,
["Warrior: Spell Reflection"] = false,
["Fury Warrior: Enraged Regeneration"] = false,
["Arms Warrior: Ignore Pain"] = false,
["Arms Warrior: Die by the Sword"] = false,
["Prot Warrior: Shield Wall "] = false,
},
["borderInset"] = 1,
["borderColor"] = {
0,
0,
0,
1,
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
},
["xOffset"] = -1,
},
["Arms Warrior: Die by the Sword"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 118038,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Die by the Sword",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
{
["trigger"] = {
["useName"] = true,
["useExactSpellId"] = false,
["unit"] = "player",
["type"] = "aura2",
["auranames"] = {
"265144",
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[2]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["glow"] = false,
["useGlowColor"] = false,
["glowScale"] = 1,
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["glowDuration"] = 1,
["type"] = "subglow",
["glowXOffset"] = 0,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 26,
["load"] = {
["use_petbattle"] = false,
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
},
},
["talent"] = {
["single"] = 14,
["multi"] = {
[14] = true,
[112128] = true,
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["class"] = {
["single"] = "DEMONHUNTER",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_never"] = false,
["talent2"] = {
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["keepAspectRatio"] = false,
["cooldown"] = true,
["preferToUpdate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["selfPoint"] = "CENTER",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["uid"] = "HC89R5JqlNv",
["parent"] = "Warrior » Top Bar",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Die by the Sword",
["useCooldownModRate"] = true,
["alpha"] = 1,
["width"] = 26,
["authorOptions"] = {
},
["config"] = {
},
["inverse"] = true,
["xOffset"] = 0,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
["checks"] = {
{
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
{
["value"] = 1,
["variable"] = "onCooldown",
},
},
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 2,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.2.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["desaturate"] = false,
},
["Prot Warrior: Seeing Red"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["unit"] = "player",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["auranames"] = {
"386486",
},
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
{
["glowFrequency"] = 0.25,
["glow"] = false,
["glowXOffset"] = 0,
["glowScale"] = 1,
["glowLength"] = 10,
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
0.3490196168422699,
0.3019607961177826,
1,
},
["glowStartAnim"] = true,
["type"] = "subglow",
["useGlowColor"] = true,
["glowType"] = "Proc",
["glowDuration"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_format"] = "timed",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 0,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_shadowXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_visible"] = true,
["anchor_point"] = "CENTER",
["text_fontSize"] = 18,
["anchorXOffset"] = 0,
["text_text_format_p_time_legacy_floor"] = false,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[2] = true,
[112116] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["difficulty"] = {
["multi"] = {
},
},
["use_petbattle"] = false,
["faction"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["use_class_and_spec"] = true,
["role"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["parent"] = "Prot Warrior Buffs",
["color"] = {
1,
1,
1,
1,
},
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["cooldown"] = true,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["desaturate"] = false,
["authorOptions"] = {
},
["selfPoint"] = "CENTER",
["uid"] = "P(TjsdIYE8o",
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["alpha"] = 1,
["cooldownTextDisabled"] = true,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Seeing Red",
["useCooldownModRate"] = true,
["frameStrata"] = 3,
["width"] = 28,
["zoom"] = 0.3,
["config"] = {
},
["inverse"] = false,
["keepAspectRatio"] = false,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "stacks",
["value"] = "90",
["op"] = ">=",
},
["changes"] = {
{
["value"] = true,
["property"] = "sub.3.glow",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Bloodlust"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["unit"] = "player",
["use_tooltip"] = false,
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["buffShowOn"] = "showOnActive",
["event"] = "Health",
["custom_hide"] = "timed",
["subeventPrefix"] = "SPELL",
["matchesShowOn"] = "showOnActive",
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"80353",
"2825",
"264667",
"32182",
"381301",
"390386",
"444257",
"466904",
},
["combineMatches"] = "showLowest",
["names"] = {
"Time Warp",
"Bloodlust",
"Primal Rage",
"Drums of Rage",
"Drums of Fury",
"Netherwinds",
"Drums of the Mountain",
},
["unevent"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1]\nend",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_offset"] = 1,
["type"] = "subborder",
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["height"] = 28,
["load"] = {
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[255] = true,
[263] = true,
[252] = true,
[70] = true,
[72] = true,
[577] = true,
[253] = true,
[254] = true,
[268] = true,
[259] = true,
[73] = true,
[250] = true,
[581] = true,
[260] = true,
[71] = true,
[104] = true,
[66] = true,
[261] = true,
[269] = true,
[251] = true,
[103] = true,
},
},
["talent"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_petbattle"] = false,
["race"] = {
["multi"] = {
},
},
["difficulty"] = {
["multi"] = {
},
},
["role"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "fade",
},
["main"] = {
["duration_type"] = "seconds",
["type"] = "none",
["easeStrength"] = 3,
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["duration_type"] = "seconds",
["easeStrength"] = 3,
["preset"] = "slideright",
},
},
["parent"] = "Prot Warrior Buffs",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["progressSource"] = {
-1,
"",
},
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["anchorFrameType"] = "SCREEN",
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Bloodlust",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["width"] = 28,
["zoom"] = 0.3,
["uid"] = "z1cfyzobacN",
["inverse"] = false,
["stickyDuration"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Arms Warrior: Collateral Damage"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["matchesShowOn"] = "showOnActive",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["duration"] = "1",
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"334783",
},
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_anchorXOffset"] = 5,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Expressway",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowYOffset"] = 0,
["text_anchorYOffset"] = -3,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_fontType"] = "OUTLINE",
["anchor_point"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 11,
["anchorXOffset"] = 0,
["text_text_format_p_time_precision"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = true,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
},
},
["talent"] = {
["multi"] = {
[112118] = true,
[114739] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["race"] = {
["multi"] = {
},
},
["spellknown"] = 46924,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["parent"] = "Arms Warrior Buffs",
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["useCooldownModRate"] = true,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Collateral Damage",
["frameStrata"] = 3,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "(m9LAoUqRTR",
["inverse"] = false,
["desaturate"] = false,
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Racial (Mag'har Orc)"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["names"] = {
},
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 274738,
["type"] = "spell",
["subeventPrefix"] = "SPELL",
["unevent"] = "auto",
["duration"] = "1",
["subeventSuffix"] = "_CAST_START",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Blood Fury",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_absorbMode"] = true,
["use_unit"] = true,
["use_track"] = true,
["unit"] = "player",
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 34,
["load"] = {
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["single"] = 18,
["multi"] = {
[14] = true,
[18] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_class"] = true,
["race"] = {
["single"] = "MagharOrc",
["multi"] = {
["Troll"] = true,
["Orc"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["use_race"] = true,
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_class_and_spec"] = false,
["talent2"] = {
},
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["selfPoint"] = "CENTER",
["source"] = "import",
["icon"] = true,
["cooldown"] = true,
["authorOptions"] = {
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["useAdjustededMin"] = false,
["regionType"] = "icon",
["parent"] = "Warrior » Primary Bar",
["uid"] = "BzN5BoYJM)3",
["progressSource"] = {
-1,
"",
},
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["alpha"] = 1,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Racial (Mag'har Orc)",
["desaturate"] = false,
["useCooldownModRate"] = true,
["width"] = 34,
["xOffset"] = 0,
["config"] = {
},
["inverse"] = true,
["useTooltip"] = false,
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Prot Warrior: Avatar Buff"] = {
["iconSource"] = -1,
["parent"] = "Prot Warrior Buffs",
["adjustedMax"] = "",
["customText"] = "function()\n    local r = WeakAuras.regions[aura_env.id].region\n    r.text2:ClearAllPoints()\n    r.text2:SetPoint(\"BOTTOMRIGHT\", r, \"BOTTOMRIGHT\", 2, 0)\nend",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["auranames"] = {
"107574",
},
["matchesShowOn"] = "showOnActive",
["subeventPrefix"] = "SPELL",
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["useName"] = true,
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
["event"] = "Health",
["unit"] = "player",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["useGroup_count"] = false,
["spellIds"] = {
},
["type"] = "aura2",
["duration"] = "1",
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["custom_hide"] = "timed",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "fade",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["preset"] = "slideright",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["use_talent"] = false,
["use_class"] = true,
["race"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["talent"] = {
["multi"] = {
[107574] = true,
[114769] = true,
[112232] = true,
},
},
["spec"] = {
["single"] = 2,
["multi"] = {
true,
true,
},
},
["use_petbattle"] = false,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["faction"] = {
["multi"] = {
},
},
["pvptalent"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["use_class_and_spec"] = true,
["spellknown"] = 107574,
["role"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["anchorFrameType"] = "SCREEN",
["source"] = "import",
["selfPoint"] = "CENTER",
["icon"] = true,
["cooldown"] = true,
["desaturate"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["keepAspectRatio"] = false,
["color"] = {
1,
1,
1,
1,
},
["uid"] = "JWyf(EIOfsN",
["adjustedMin"] = "",
["anchorFrameParent"] = false,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Prot Warrior: Avatar Buff",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 28,
["xOffset"] = 0,
["config"] = {
},
["inverse"] = false,
["authorOptions"] = {
},
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
["Arms Warrior: Execute"] = {
["iconSource"] = -1,
["parent"] = "Warrior » Emphasized Buffs",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -113,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = true,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_charges"] = false,
["genericShowOn"] = "showAlways",
["use_unit"] = true,
["unit"] = "target",
["percenthealth_operator"] = {
"<=",
},
["use_absorbMode"] = true,
["names"] = {
},
["use_trackcharge"] = false,
["spellName"] = 163201,
["use_genericShowOn"] = true,
["type"] = "unit",
["use_absorbHealMode"] = true,
["subeventSuffix"] = "_CAST_START",
["use_spellCount"] = false,
["percenthealth"] = {
"20",
},
["event"] = "Health",
["use_exact_spellName"] = false,
["realSpellName"] = "Execute",
["use_spellName"] = true,
["spellIds"] = {
},
["use_targetRequired"] = true,
["debuffType"] = "HELPFUL",
["use_percenthealth"] = true,
["use_track"] = true,
["subeventPrefix"] = "SPELL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["track"] = "auto",
["type"] = "spell",
["use_genericShowOn"] = true,
["event"] = "Cooldown Progress (Spell)",
["unit"] = "player",
["use_spellName"] = true,
["debuffType"] = "HELPFUL",
["genericShowOn"] = "showAlways",
["use_exact_spellName"] = false,
["use_track"] = true,
["spellName"] = 281000,
},
["untrigger"] = {
},
},
{
["trigger"] = {
["type"] = "unit",
["use_absorbHealMode"] = true,
["talent"] = {
["single"] = 9,
["multi"] = {
[112136] = true,
},
},
["spec"] = 1,
["event"] = "Talent Known",
["use_unit"] = true,
["use_class"] = true,
["use_absorbMode"] = true,
["use_spec"] = true,
["use_talent"] = false,
["unit"] = "player",
["class"] = "WARRIOR",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
{
["trigger"] = {
["useName"] = true,
["auranames"] = {
"280776",
"52437",
},
["unit"] = "player",
["type"] = "aura2",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "custom",
["customTriggerLogic"] = "function(t)\nreturn t[1] or t[4];\nend",
["activeTriggerMode"] = 2,
},
["internalVersion"] = 86,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "alphaPulse",
["duration_type"] = "seconds",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["stickyDuration"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["glowDuration"] = 1,
["glowType"] = "buttonOverlay",
["glowThickness"] = 1,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowLength"] = 10,
["glowScale"] = 1,
["glowXOffset"] = 0,
["useGlowColor"] = false,
["glow"] = true,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
{
["text_text_format_p_time_precision"] = 1,
["text_text"] = "FREE",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_text_format_p_format"] = "timed",
["text_color"] = {
0,
1,
0.10980392156863,
1,
},
["text_font"] = "Expressway",
["anchorXOffset"] = 0,
["text_shadowYOffset"] = 0,
["text_shadowXOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "OUTLINE",
["text_visible"] = false,
["text_text_format_p_time_format"] = 0,
["anchor_point"] = "CENTER",
["text_fontSize"] = 10,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_anchorYOffset"] = -15,
},
},
["height"] = 34,
["load"] = {
["use_covenant"] = false,
["use_petbattle"] = false,
["use_never"] = false,
["talent"] = {
["multi"] = {
[112145] = false,
},
},
["size"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
},
},
["talent_extraOption"] = 0,
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["use_class_and_spec"] = true,
["use_spec"] = true,
["covenant"] = {
["single"] = 2,
["multi"] = {
["1"] = true,
["4"] = true,
["3"] = true,
["0"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
[2] = true,
[3] = true,
},
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
},
},
["zoneIds"] = "",
},
["useAdjustededMax"] = false,
["width"] = 34,
["source"] = "import",
["xOffset"] = 0,
["preferToUpdate"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["displayIcon"] = "135358",
["selfPoint"] = "CENTER",
["authorOptions"] = {
},
["config"] = {
},
["frameStrata"] = 3,
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Execute",
["alpha"] = 1,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["color"] = {
1,
1,
1,
1,
},
["uid"] = "8RXGMNiSE70",
["inverse"] = true,
["desaturate"] = false,
["conditions"] = {
{
["check"] = {
["op"] = "<",
["checks"] = {
{
["value"] = 0,
["op"] = "<",
["variable"] = "show",
},
{
["trigger"] = 4,
["variable"] = "show",
["value"] = 0,
},
},
["trigger"] = 2,
["variable"] = "insufficientResources",
["value"] = 1,
},
["linked"] = false,
["changes"] = {
{
["value"] = {
0.45882352941176,
0.48627450980392,
0.71764705882353,
1,
},
["property"] = "color",
},
{
["property"] = "sub.2.glow",
},
},
},
{
["check"] = {
["trigger"] = 4,
["variable"] = "show",
["value"] = 1,
},
["linked"] = true,
["changes"] = {
{
["value"] = true,
["property"] = "sub.4.text_visible",
},
},
},
{
["check"] = {
["trigger"] = 3,
["variable"] = "show",
["value"] = 1,
},
["changes"] = {
{
["value"] = 37,
["property"] = "yOffsetRelative",
},
},
},
},
["cooldown"] = true,
["keepAspectRatio"] = false,
},
["Arms Warrior: Ignore Pain"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["use_genericShowOn"] = true,
["genericShowOn"] = "showAlways",
["names"] = {
},
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["use_unit"] = true,
["type"] = "spell",
["subeventPrefix"] = "SPELL",
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["duration"] = "1",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Impending Victory",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["unevent"] = "auto",
["use_absorbMode"] = true,
["use_track"] = true,
["spellName"] = 190456,
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subborder",
["border_size"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_offset"] = 1,
},
},
["height"] = 26,
["load"] = {
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 71,
["multi"] = {
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 12,
["multi"] = {
[14] = true,
[18] = true,
[12] = true,
[114738] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
["WARRIOR"] = true,
},
},
["use_talent"] = false,
["use_class"] = true,
["use_spellknown"] = false,
["use_petbattle"] = false,
["use_class_and_spec"] = true,
["use_never"] = false,
["spec"] = {
["single"] = 3,
["multi"] = {
true,
[3] = true,
},
},
["spellknown"] = 202168,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["width"] = 26,
["source"] = "import",
["selfPoint"] = "CENTER",
["progressSource"] = {
-1,
"",
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["stickyDuration"] = false,
["useAdjustededMin"] = false,
["regionType"] = "icon",
["icon"] = true,
["authorOptions"] = {
},
["config"] = {
},
["xOffset"] = 0,
["anchorFrameParent"] = false,
["alpha"] = 1,
["cooldownTextDisabled"] = false,
["zoom"] = 0.3,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Arms Warrior: Ignore Pain",
["frameStrata"] = 3,
["useCooldownModRate"] = true,
["anchorFrameType"] = "SCREEN",
["parent"] = "Warrior » Top Bar",
["uid"] = "dnXgiZxWFvX",
["inverse"] = true,
["anchorFrameFrame"] = "ElvUI_Bar6Button2",
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "insufficientResources",
["value"] = 1,
},
["changes"] = {
{
["value"] = {
0.364705890417099,
0.4745098352432251,
1,
1,
},
["property"] = "color",
},
},
},
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Fury Warriorr: Ravager Buff"] = {
["iconSource"] = -1,
["color"] = {
1,
1,
1,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["useGroup_count"] = false,
["duration"] = "1",
["names"] = {
"Battle Potion of Intellect",
"Potion of Rising Death",
"Potion of Prolonged Power",
},
["use_tooltip"] = false,
["buffShowOn"] = "showOnActive",
["type"] = "aura2",
["use_debuffClass"] = false,
["subeventSuffix"] = "_CAST_START",
["custom_hide"] = "timed",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["unit"] = "player",
["matchesShowOn"] = "showOnActive",
["spellIds"] = {
},
["useName"] = true,
["auranames"] = {
"228920",
},
["combineMatches"] = "showLowest",
["unevent"] = "timed",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["disjunctive"] = "all",
["activeTriggerMode"] = -10,
},
["internalVersion"] = 86,
["keepAspectRatio"] = false,
["animation"] = {
["start"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "fade",
["duration_type"] = "seconds",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeType"] = "none",
["easeStrength"] = 3,
["preset"] = "slideright",
["duration_type"] = "seconds",
},
},
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 28,
["load"] = {
["ingroup"] = {
["multi"] = {
},
},
["use_class_and_spec"] = true,
["use_talent"] = false,
["use_class"] = true,
["role"] = {
["multi"] = {
},
},
["use_spec"] = false,
["zoneIds"] = "",
["talent2"] = {
["multi"] = {
},
},
["class_and_spec"] = {
["single"] = 72,
["multi"] = {
[71] = true,
[72] = true,
},
},
["talent"] = {
["single"] = 6,
["multi"] = {
[6] = true,
[112256] = true,
},
},
["use_petbattle"] = false,
["spec"] = {
["single"] = 1,
["multi"] = {
true,
true,
},
},
["race"] = {
["multi"] = {
},
},
["use_not_spellknown"] = true,
["difficulty"] = {
["multi"] = {
},
},
["use_spellknown"] = false,
["pvptalent"] = {
["multi"] = {
},
},
["faction"] = {
["multi"] = {
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["WARRIOR"] = true,
},
},
["not_spellknown"] = 386628,
["spellknown"] = 46924,
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["source"] = "import",
["xOffset"] = 0,
["stickyDuration"] = false,
["selfPoint"] = "CENTER",
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["authorOptions"] = {
},
["progressSource"] = {
-1,
"",
},
["icon"] = true,
["config"] = {
},
["anchorFrameParent"] = false,
["width"] = 28,
["frameStrata"] = 3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Fury Warriorr: Ravager Buff",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["zoom"] = 0.3,
["uid"] = "1d9lXMbwanl",
["inverse"] = false,
["parent"] = "Fury Warrior Buffs",
["conditions"] = {
},
["cooldown"] = true,
["preferToUpdate"] = false,
},
["Warrior: Racial (Troll)"] = {
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["customTextUpdate"] = "update",
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["track"] = "auto",
["duration"] = "1",
["genericShowOn"] = "showAlways",
["unit"] = "player",
["use_showgcd"] = false,
["use_trackcharge"] = false,
["debuffType"] = "HELPFUL",
["spellName"] = 26297,
["type"] = "spell",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["use_absorbMode"] = true,
["unevent"] = "auto",
["event"] = "Cooldown Progress (Spell)",
["use_exact_spellName"] = false,
["realSpellName"] = "Berserking",
["use_spellName"] = true,
["spellIds"] = {
},
["buffShowOn"] = "showOnActive",
["use_genericShowOn"] = true,
["subeventPrefix"] = "SPELL",
["use_track"] = true,
["names"] = {
},
},
["untrigger"] = {
["genericShowOn"] = "showAlways",
},
},
["disjunctive"] = "any",
["customTriggerLogic"] = "",
["activeTriggerMode"] = -10,
},
["useTooltip"] = false,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["border_size"] = 1,
["border_offset"] = 1,
["border_color"] = {
0,
0,
0,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 34,
["load"] = {
["use_race"] = true,
["use_never"] = false,
["talent"] = {
["single"] = 18,
["multi"] = {
[14] = true,
[18] = true,
},
},
["class"] = {
["single"] = "WARRIOR",
["multi"] = {
["DEMONHUNTER"] = true,
},
},
["use_class"] = true,
["race"] = {
["single"] = "Troll",
["multi"] = {
["Troll"] = true,
["Orc"] = true,
},
},
["spec"] = {
["single"] = 1,
["multi"] = {
true,
},
},
["talent2"] = {
},
["class_and_spec"] = {
["single"] = 73,
["multi"] = {
[73] = true,
[71] = true,
[72] = true,
},
},
["use_class_and_spec"] = false,
["use_petbattle"] = false,
["size"] = {
["multi"] = {
},
},
},
["frameStrata"] = 3,
["useAdjustededMax"] = false,
["stickyDuration"] = false,
["source"] = "import",
["parent"] = "Warrior » Primary Bar",
["cooldown"] = true,
["internalVersion"] = 86,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["anchorFrameFrame"] = "ElvUI_Bar6Button1",
["regionType"] = "icon",
["useAdjustededMin"] = false,
["uid"] = "4ohnKEyDONY",
["xOffset"] = 0,
["anchorFrameType"] = "SCREEN",
["anchorFrameParent"] = false,
["progressSource"] = {
-1,
"",
},
["zoom"] = 0.3,
["cooldownTextDisabled"] = false,
["auto"] = true,
["tocversion"] = 110200,
["id"] = "Warrior: Racial (Troll)",
["alpha"] = 1,
["useCooldownModRate"] = true,
["width"] = 34,
["color"] = {
1,
1,
1,
1,
},
["config"] = {
},
["inverse"] = true,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "onCooldown",
["value"] = 1,
},
["changes"] = {
{
["value"] = true,
["property"] = "desaturate",
},
},
},
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["preferToUpdate"] = false,
},
},
["historyCutoff"] = 730,
["lastArchiveClear"] = 1758721137,
["minimap"] = {
["hide"] = false,
},
["lastUpgrade"] = 1758721155,
["dbVersion"] = 86,
["migrationCutoff"] = 730,
["features"] = {
},
["editor_font_size"] = 12,
["login_squelch_time"] = 10,
["registered"] = {
},
}
