--!strict
-- Client entry point. Boots every controller in ./Controllers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServiceLoader = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ServiceLoader"))

ServiceLoader.boot(script.Parent:WaitForChild("Controllers"), "Client")
