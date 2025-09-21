--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="eu",date="2025-09-20T06:08:28Z",numCharacters=148,lookup={},recordSizeInBytes=2,encodingOrder={0,1,3}}
local F

-- chunk size: 136
F = function() provider.lookup[1] = "\10\9\10\9\10\5\10\5\10\5\10\5\10\5\10\13\10\13\10\13\10\29\4\4\10\29\10\5\10\5\10\5\10\5\10\29\10\5\10\5\10\29\4\4\10\13\10\13\10\5\10\5\10\5\10\5\10\5\4\4\10\13\10\5\4\4\10\5\10\5\10\13\4\4\10\5\10\5\10\5\10\5\10\5\10\5\10\5\10\5\10\5\10\13\10\13\10\13\10\13\10\13\10\5\10\13\10\13\10\13\4\4\10\13\10\5\10\5\10\5\4\8\10\13\10\13\10\13\10\13\4\4\4\16\4\8" end F()

F = nil
RaiderIO.AddProvider(provider)
