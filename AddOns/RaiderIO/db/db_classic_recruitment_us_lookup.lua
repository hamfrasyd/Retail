--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="us",date="2025-10-04T06:05:22Z",numCharacters=45,lookup={},recordSizeInBytes=2,encodingOrder={0,1,3}}
local F

-- chunk size: 46
F = function() provider.lookup[1] = "\10\13\10\13\10\13\10\13\10\21\10\13\10\21\4\16\10\21\10\21\10\21\10\21\10\21\10\21\10\21\10\21\10\13\10\21\10\13\10\13\10\13\10\13\10\13" end F()

F = nil
RaiderIO.AddProvider(provider)
