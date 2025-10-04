--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="eu",date="2025-10-04T06:05:22Z",numCharacters=45,db={}}
local F

F = function() provider.db["PyrewoodVillage"]={0,"Keavarie"} end F()
F = function() provider.db["MirageRaceway"]={2,"Arooq","Eizon","Fehica","Rawrhehe"} end F()
F = function() provider.db["Auberdine"]={10,"Ayliea","Gaweed","Køølgoth","Sílver","Thenaryon","Tømo"} end F()
F = function() provider.db["Gehennas"]={22,"Helisha","Kéthaze","Nachoj","Nayaraw","Seythez","Seythezqt","Seythezz","Uroyamï","Åb"} end F()
F = function() provider.db["Firemaw"]={40,"Fiftyfiva"} end F()
F = function() provider.db["Everlook"]={42,"Michaa"} end F()

F = nil
RaiderIO.AddProvider(provider)
