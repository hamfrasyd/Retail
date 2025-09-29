--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="us",date="2025-09-28T06:04:57Z",numCharacters=96,lookup={},recordSizeInBytes=2,encodingOrder={0,1,3}}
local F

-- chunk size: 114
F = function() provider.lookup[1] = "\10\29\10\5\10\13\10\5\10\5\10\5\10\5\10\5\10\5\10\5\10\13\10\5\10\29\10\5\10\13\10\13\10\5\10\21\10\5\10\13\10\21\10\5\10\29\4\16\10\5\10\21\10\5\10\5\10\21\10\21\10\5\10\5\10\5\10\5\10\29\10\21\10\5\10\29\10\21\10\21\10\21\10\21\10\29\10\13\10\21\10\29\10\13\10\13\10\5\10\13\10\13\10\13\10\13\10\13\10\13\10\13\10\13" end F()

F = nil
RaiderIO.AddProvider(provider)
