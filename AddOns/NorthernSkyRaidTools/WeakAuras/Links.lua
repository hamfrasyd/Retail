local _, NSI = ... -- Internal namespace

local WeakAura_Links = {
    ["Manaforge"] = "https://wago.io/NSManaforge"
}

function NSI:GetWeakAuraLink(name)
    return WeakAura_Links[name] or ""
end