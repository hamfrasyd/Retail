local GlobalAddonName, AUI = ...

BINDING_HEADER_AUI = "AtrocityUI"
BINDING_NAME_AUIHIDEBARS = "Hide ActionBars OOC"

setglobal("SetPITarget", function()
    local n=UnitName("mouseover") or "target" if not InCombatLockdown() then EditMacro(GetMacroIndexByName("PI"),nil,nil,"#showtooltip\n/cast [@mouseover,help,nodead][@"..n..",exists,nodead][] Power Infusion\n/use 13\n/use Ancestral Call\n/use Vampiric Embrace\n/use item:212971\n/use item:212265\n/use item:212264") print("PI Updated to "..n)
        end
    end)