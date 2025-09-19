
OmniCCDB = {
["profileKeys"] = {
["Zenikanova - Kel'Thuzad"] = "FragUI",
},
["global"] = {
["dbVersion"] = 6,
["addonVersion"] = "11.2.5",
},
["profiles"] = {
["Default"] = {
["rules"] = {
{
["id"] = "auras",
["patterns"] = {
"Aura",
"Buff",
"Debuff",
},
["name"] = "Auras",
["enabled"] = false,
},
{
["id"] = "plates",
["patterns"] = {
"Plate",
},
["name"] = "Unit Nameplates",
["enabled"] = false,
},
{
["id"] = "actions",
["patterns"] = {
"ActionButton",
"MultiBar",
},
["name"] = "Action Bars",
["enabled"] = false,
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
["themes"] = {
["Default"] = {
["textStyles"] = {
["soon"] = {
},
["seconds"] = {
},
["minutes"] = {
},
},
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
["b"] = 1,
["scale"] = 1,
["g"] = 1,
["r"] = 1,
},
["charging"] = {
["a"] = 1,
["r"] = 1,
["scale"] = 1,
["b"] = 1,
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
["minutes"] = {
},
["seconds"] = {
},
["soon"] = {
},
},
},
},
},
},
}
OmniCC4Config = nil
