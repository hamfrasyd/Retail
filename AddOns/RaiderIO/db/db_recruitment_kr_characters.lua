--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="kr",date="2025-09-21T08:24:44Z",numCharacters=35833,db={}}
local F

F = function() provider.db["헬스크림"]={0,"홍타우","홍탁기","후신타후"} end F()

F = nil
RaiderIO.AddProvider(provider)
