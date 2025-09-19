
OmniCCDB = {
["global"] = {
["dbVersion"] = 6,
["addonVersion"] = "11.2.6",
},
["profileKeys"] = {
["Driplitty - Twisting Nether"] = "Default",
["Mbuzi - Twisting Nether"] = "FragUI",
["Bæenjoyer - Twisting Nether"] = "Default",
["Bægnaskeren - Twisting Nether"] = "Default",
["Kassedamen - Twisting Nether"] = "Default",
["Dådyret - Draenor"] = "Default",
["Mbuzipriest - Twisting Nether"] = "Default",
["Lilgoat - Twisting Nether"] = "Default",
["Mbuzi - Draenor"] = "Default",
["Ponypala - Twisting Nether"] = "Default",
},
["profiles"] = {
["Default"] = {
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
["FragUI"] = {
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
["seconds"] = {
["b"] = 1,
},
["minutes"] = {
},
["soon"] = {
["b"] = 0.250980406999588,
["scale"] = 1,
["g"] = 0.250980406999588,
},
["hours"] = {
["r"] = 1,
["scale"] = 1,
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
["b"] = 1,
["scale"] = 1,
["g"] = 1,
},
},
["fontSize"] = 17,
["tenthsDuration"] = 5,
["mmSSDuration"] = 601,
["effect"] = "none",
["yOff"] = -0.5,
},
["Plater Nameplates Theme"] = {
["textStyles"] = {
["soon"] = {
},
["seconds"] = {
},
["minutes"] = {
},
},
["enableText"] = false,
},
},
},
},
}
OmniCC4Config = nil
