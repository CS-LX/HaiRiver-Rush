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

-- MP3 资源路径（assets/ 被配置为资源根，直接写相对路径）
local BGM_PATH   = "image/AAA.mp3"
-- 重试计时：部分平台首帧资源尚未解码完毕，延迟一帧再 Play
local retryTimer = 0.0
local bgmPlayed  = false

local function TryPlayBGM()
    local sound = cache:GetResource("Sound", BGM_PATH)
    if not sound then return false end
    sound:SetLooped(true)
    musicSource:Play(sound)
    bgmPlayed = true
    return true
end

function M.Init(scene)
    -- 背景音乐节点
    musicNode   = scene:CreateChild("BGMusic")
    musicSource = musicNode:CreateComponent("SoundSource")
    musicSource:SetSoundType("MUSIC")
    musicSource:SetGain(0.55)

    -- 立即尝试播放；若首帧资源未就绪则在 Update 中重试
    bgmPlayed = TryPlayBGM()

    -- 音效节点（每次播放临时挂载 SoundSource）
    sfxNode = scene:CreateChild("SFX")
end

-- 在主循环中调用（每帧）
-- 1. 首次加载失败时每 0.5 秒重试
-- 2. 播放结束后自动重播（MP3 压缩格式 SetLooped 不可靠，用轮询保底）
function M.Update(dt)
    if not musicSource then return end

    if not bgmPlayed then
        -- 首次加载重试
        retryTimer = retryTimer + dt
        if retryTimer >= 0.5 then
            retryTimer = 0.0
            TryPlayBGM()
        end
        return
    end

    -- 已成功播放过：检测是否停止，停止则重播
    if not musicSource:IsPlaying() then
        TryPlayBGM()
    end
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
