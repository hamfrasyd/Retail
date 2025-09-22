--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="us",date="2025-09-21T06:05:39Z",numCharacters=129,lookup={},recordSizeInBytes=2,encodingOrder={0,1,3}}
local F

-- chunk size: 126
F = function() provider.lookup[1] = "\10\29\10\5\10\13\10\5\10\5\10\5\10\5\10\5\10\5\10\5\10\21\10\13\10\5\10\29\10\5\10\13\10\13\10\5\10\21\10\5\10\13\10\21\10\5\10\29\10\5\10\21\10\5\10\5\10\21\10\21\10\5\10\5\10\5\10\5\10\29\10\21\10\5\10\29\10\21\10\21\10\21\10\21\10\29\10\13\10\21\10\29\10\13\10\13\10\5\10\13\10\13\10\13\10\13\10\13\10\13\10\13\10\13\10\13\10\13\4\8\4\4\4\4\4\4" end F()

F = nil
RaiderIO.AddProvider(provider)
