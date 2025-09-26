
OmniCCDB = {
["global"] = {
["dbVersion"] = 6,
["addonVersion"] = "11.2.7",
},
["profileKeys"] = {
["Driplitty - Twisting Nether"] = "Default",
["Mbuzi - Twisting Nether"] = "FragUI",
["Bæenjoyer - Twisting Nether"] = "Default",
["Misswarchira - Argent Dawn"] = "Default",
["Bægnaskeren - Twisting Nether"] = "FragUI_1",
["Kassedamen - Twisting Nether"] = "Default",
["Dådyret - Draenor"] = "Default",
["Mbuzipriest - Twisting Nether"] = "Default",
["Lilgoat - Twisting Nether"] = "Default",
["Mbuzi - Draenor"] = "Default",
["Ponypala - Twisting Nether"] = "Default",
},
["profiles"] = {
["FragUI"] = {
["themes"] = {
["Default"] = {
["textStyles"] = {
["seconds"] = {
["b"] = 1,
},
["minutes"] = {
},
["soon"] = {
["scale"] = 1,
["g"] = 0.250980406999588,
["b"] = 0.250980406999588,
},
["hours"] = {
["scale"] = 1,
["r"] = 1,
["g"] = 1,
["b"] = 1,
},
["charging"] = {
["a"] = 1,
["b"] = 1,
["scale"] = 1,
["r"] = 1,
},
["controlled"] = {
["scale"] = 1,
["g"] = 1,
["b"] = 1,
},
},
["fontSize"] = 17,
["tenthsDuration"] = 5,
["effect"] = "none",
["mmSSDuration"] = 601,
["yOff"] = -0.5,
},
["Plater Nameplates Theme"] = {
["textStyles"] = {
["minutes"] = {
},
["soon"] = {
},
["seconds"] = {
},
},
["enableText"] = false,
},
},
["rules"] = {
{
["enabled"] = false,
["patterns"] = {
"Aura",
"Buff",
"Debuff",
},
["name"] = "Auras",
["id"] = "auras",
},
{
["enabled"] = false,
["patterns"] = {
"Plate",
},
["name"] = "Unit Nameplates",
["id"] = "plates",
},
{
["enabled"] = false,
["patterns"] = {
"ActionButton",
"MultiBar",
},
["name"] = "Action Bars",
["id"] = "actions",
},
{
["id"] = "Plater Nameplates Rule",
["patterns"] = {
"PlaterMainAuraIcon",
"PlaterSecondaryAuraIcon",
"ExtraIconRowIcon",
},
["theme"] = "Plater Nameplates Theme",
["priority"] = 4,
},
},
},
["Default"] = {
["rules"] = {
{
["enabled"] = false,
["patterns"] = {
"Aura",
"Buff",
"Debuff",
},
["name"] = "Auras",
["id"] = "auras",
},
{
["enabled"] = false,
["patterns"] = {
"Plate",
},
["name"] = "Unit Nameplates",
["id"] = "plates",
},
{
["enabled"] = false,
["patterns"] = {
"ActionButton",
"MultiBar",
},
["name"] = "Action Bars",
["id"] = "actions",
},
{
["patterns"] = {
"PlaterMainAuraIcon",
"PlaterSecondaryAuraIcon",
"ExtraIconRowIcon",
},
["id"] = "Plater Nameplates Rule",
["priority"] = 4,
["theme"] = "Plater Nameplates Theme",
},
},
["themes"] = {
["Default"] = {
["textStyles"] = {
["minutes"] = {
},
["seconds"] = {
},
["soon"] = {
},
},
},
["Plater Nameplates Theme"] = {
["textStyles"] = {
["minutes"] = {
},
["seconds"] = {
},
["soon"] = {
},
},
["enableText"] = false,
},
},
},
["FragUI_1"] = {
["themes"] = {
["Plater Nameplates Theme"] = {
["textStyles"] = {
["minutes"] = {
},
["soon"] = {
},
["seconds"] = {
},
},
["enableText"] = false,
},
["Default"] = {
["textStyles"] = {
["minutes"] = {
},
["soon"] = {
},
["seconds"] = {
},
},
["mmSSDuration"] = 300,
["maxDuration"] = 300,
},
},
["rules"] = {
{
["enabled"] = false,
["patterns"] = {
"Aura",
"Buff",
"Debuff",
},
["name"] = "Auras",
["id"] = "auras",
},
{
["enabled"] = false,
["patterns"] = {
"Plate",
},
["name"] = "Unit Nameplates",
["id"] = "plates",
},
{
["enabled"] = false,
["patterns"] = {
"ActionButton",
"MultiBar",
},
["name"] = "Action Bars",
["id"] = "actions",
},
{
["id"] = "Plater Nameplates Rule",
["patterns"] = {
"PlaterMainAuraIcon",
"PlaterSecondaryAuraIcon",
"ExtraIconRowIcon",
},
["theme"] = "Plater Nameplates Theme",
["priority"] = 4,
},
},
},
},
}
OmniCC4Config = nil
