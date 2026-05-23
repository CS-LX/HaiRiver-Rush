-- ============================================================
--  water.lua  —  水面地形块（循环复用）
-- ============================================================
local C = require "config"
local S = require "state"
local U = require "utils"

local M = {}

local function CreateChunk(zStart)
    local node = S.mainScene:CreateChild("WaterChunk")
    node:SetPosition(Vector3(0, -0.05, zStart + C.CHUNK_LEN * 0.5))
    local mdl = node:CreateComponent("StaticModel")
    mdl:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    mdl:SetMaterial(U.MakeMaterial(0.04, 0.42, 0.62))
    node:SetScale(Vector3(24.0, 1.0, C.CHUNK_LEN))
    return node
end

function M.Init()
    for i = 1, C.NUM_CHUNKS do
        S.waterChunks[i] = CreateChunk((i - 1) * C.CHUNK_LEN - C.CHUNK_LEN)
    end
    U.LogInfo("[Water] " .. C.NUM_CHUNKS .. " 个地形块已创建")
end

-- 每帧调用：当某块已落后 boatPosZ 超过一个块长时，循环移到前方
function M.Update(boatZ)
    for i = 1, #S.waterChunks do
        local chunk = S.waterChunks[i]
        local cz = chunk:GetPosition().z - C.CHUNK_LEN * 0.5
        if cz < boatZ - C.CHUNK_LEN then
            local newZ = cz + C.NUM_CHUNKS * C.CHUNK_LEN
            chunk:SetPosition(Vector3(0, -0.05, newZ + C.CHUNK_LEN * 0.5))
        end
    end
end

-- 重置所有地形块回初始位置（用于重新开始）
function M.Reset()
    for i = 1, #S.waterChunks do
        S.waterChunks[i]:SetPosition(Vector3(0, -0.05,
            ((i - 1) * C.CHUNK_LEN - C.CHUNK_LEN) + C.CHUNK_LEN * 0.5))
    end
end

return M
