-- ============================================================
--  audio.lua  —  背景音乐 + 音效管理
-- ============================================================
local M = {}

---@type Node
local musicNode = nil
---@type SoundSource
local musicSource = nil

---@type Node
local sfxNode = nil

function M.Init(scene)
    -- 背景音乐
    musicNode   = scene:CreateChild("BGMusic")
    musicSource = musicNode:CreateComponent("SoundSource")
    musicSource:SetSoundType("MUSIC")
    musicSource:SetGain(0.55)

    local sound = cache:GetResource("Sound", "image/AAA.mp3")
    if sound then
        sound:SetLooped(true)
        musicSource:Play(sound)
    end

    -- 音效节点（每次播放临时挂载 SoundSource）
    sfxNode = scene:CreateChild("SFX")
end

-- 播放一次性音效，name 为不含路径和扩展名的文件名
function M.PlaySfx(name)
    if not sfxNode then return end
    local snd = cache:GetResource("Sound", "audio/sfx/" .. name .. ".ogg")
    if not snd then return end
    local src = sfxNode:CreateComponent("SoundSource")
    src:SetSoundType("EFFECT")
    src:SetGain(0.8)
    src:SetAutoRemoveMode(REMOVE_COMPONENT)
    src:Play(snd)
end

function M.SetGain(v)
    if musicSource then musicSource:SetGain(v) end
end

function M.Stop()
    if musicSource then musicSource:Stop() end
end

return M
