-- ============================================================
--  audio.lua  —  背景音乐管理
-- ============================================================
local M = {}

---@type Node
local musicNode = nil
---@type SoundSource
local musicSource = nil

function M.Init(scene)
    musicNode   = scene:CreateChild("BGMusic")
    musicSource = musicNode:CreateComponent("SoundSource")
    musicSource:SetSoundType("MUSIC")
    musicSource:SetGain(0.55)

    local sound = cache:GetResource("Sound", "image/AAA.mp3")
    if sound then
        sound:SetLooped(true)
        musicSource:Play(sound)
    end
end

function M.SetGain(v)
    if musicSource then musicSource:SetGain(v) end
end

function M.Stop()
    if musicSource then musicSource:Stop() end
end

return M
