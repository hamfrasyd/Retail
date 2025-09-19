--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="kr",date="2025-09-19T08:33:40Z",numCharacters=36085,lookup={},recordSizeInBytes=2,encodingOrder={0,1,3}}
local F

-- chunk size: 6
F = function() provider.lookup[1] = "\5\4\5\4\5\16" end F()

F = nil
RaiderIO.AddProvider(provider)
