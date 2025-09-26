
OmniCCDB = {
["profileKeys"] = {
["Badandbuzi - Argent Dawn"] = "Default",
["Yesfin - Argent Dawn"] = "FragUI_2",
["Whatamelon - Twisting Nether"] = "FragUI_1",
},
["global"] = {
["dbVersion"] = 6,
["addonVersion"] = "11.2.7",
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
["b"] = 1,
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
["seconds"] = {
},
["minutes"] = {
},
["soon"] = {
},
},
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
["FragUI_2"] = {
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
["enableText"] = false,
},
},
},
["Default"] = {
["themes"] = {
["Default"] = {
["textStyles"] = {
["minutes"] = {
},
["soon"] = {
},
["seconds"] = {
},
},
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
["FragUI_1"] = {
["themes"] = {
["Default"] = {
["textStyles"] = {
["seconds"] = {
},
["minutes"] = {
},
["soon"] = {
},
},
},
["Plater Nameplates Theme"] = {
["textStyles"] = {
["seconds"] = {
},
["minutes"] = {
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
},
}
OmniCC4Config = nil
