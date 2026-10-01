--!strict
-- Server entry point. Boots every service in ./Services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceLoader = require(ReplicatedStorage.Shared.ServiceLoader)

ServiceLoader.boot(script.Parent.Services, "Server")
