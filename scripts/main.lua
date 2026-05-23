-- ============================================================
--  海河飙车 (Haihe Rush) - 自由驾驶河道赛车游戏
--  入口文件：模块加载、事件注册、主循环编排
-- ============================================================

local C          = require "config"
local S          = require "state"
local U          = require "utils"
local SceneMod   = require "scene"
local Track      = require "track"
local Boat       = require "boat"
local BoatPhys   = require "boatphys"
local Obstacles  = require "obstacles"
local Coins      = require "coins"
local Camera     = require "camera"
local UI         = require "ui"
local ThrottleUI = require "throttleui"

-- ─────────────────────────────────────────────────────────────
--  耐久度扣减（全局，供 boatphys.lua 调用）
-- ─────────────────────────────────────────────────────────────
local lastObsHitTime = -10.0   -- 障碍物碰撞冷却计时

-- 计算各碰撞类型的伤害量
--   墙壁：基础 0.15 + 速度系数 0.10×(speed/SPEED_MAX)
--   浮标：固定 0.10
--   游船：固定 0.22
local function CalcDamage(source)
    if source == "wall" then
        local speedRatio = S.speed / C.SPEED_MAX
        return C.DMG_WALL_BASE + C.DMG_WALL_SPEED * speedRatio
    elseif source == "buoy" then
        return C.DMG_BUOY
    elseif source == "gameboat" then
        return C.DMG_GAMEBOAT
    end
    return 0.10
end

function TakeDurabilityHit(source)
    if S.gameState ~= "playing" then return end
    local dmg = CalcDamage(source)
    S.durability = math.max(0.0, S.durability - dmg)
    U.LogInfo(string.format("[Durability] 来源=%s 伤害=%.2f 剩余=%.2f", source, dmg, S.durability))
    if S.durability <= 0 then
        S.gameState = "gameover"
        UI.ShowGameOver()
    end
end

-- ─────────────────────────────────────────────────────────────
--  碰撞检测（手动 AABB，障碍物）
-- ─────────────────────────────────────────────────────────────
local function CheckCollisions()
    if S.gameState ~= "playing" then return end

    local now = time and time:GetElapsedTime() or 0
    if (now - lastObsHitTime) < C.OBS_HIT_CD then return end

    local bp = S.boatNode:GetPosition()

    for i = 1, #S.activeObstacles do
        local obs = S.activeObstacles[i]
        if obs:IsEnabled() then
            local p  = obs:GetPosition()
            local t  = U.GetObsType(obs)
            local hit = false

            -- 转换到障碍物局部空间进行碰撞检测
            local obsRad = math.rad(obs:GetRotation():YawAngle())
            local dx     = bp.x - p.x
            local dz     = bp.z - p.z
            local fwdX   = math.sin(obsRad)
            local fwdZ   = math.cos(obsRad)
            local rightX = math.cos(obsRad)
            local rightZ = -math.sin(obsRad)
            local localX = dx * rightX + dz * rightZ
            local localZ = dx * fwdX   + dz * fwdZ

            if t == "buoy" then
                hit = math.abs(localX) < 1.0 and math.abs(localZ) < 1.0
            elseif t == "gameboat" then
                hit = math.abs(localX) < 2.6 and math.abs(localZ) < 4.2
            end

            if hit then
                lastObsHitTime = now
                -- 碰障碍物：扣耐久 + 减速
                S.speed    = math.max(C.SPEED_MIN, S.speed - C.HIT_SPEED_LOSS)
                local newT = (S.speed - C.SPEED_MIN) / (C.SPEED_MAX - C.SPEED_MIN)
                S.throttle = math.max(0.0, math.min(1.0, newT))
                TakeDurabilityHit(t)   -- "buoy" 或 "gameboat"
                return
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  重新开始
-- ─────────────────────────────────────────────────────────────
local function RestartGame()
    U.LogInfo("[Game] 重新开始")

    Obstacles.ClearAll()
    Coins.ClearAll()
    Boat.Reset()
    BoatPhys.Reset()
    Camera.Reset()
    Track.Reset()
    UI.HideGameOver()
    UI.ResetHint()

    S.speed         = C.SPEED_INIT
    S.throttle      = 0.25
    S.score         = 0
    S.coinCount     = 0
    S.distanceMeter = 0.0
    S.durability    = 1.0
    S.gameState     = "playing"
    S.touchSteering = 0
    lastObsHitTime  = -10.0
end

-- ─────────────────────────────────────────────────────────────
--  键盘输入（使用 GetKeyDown 持续检测，支持连续转向）
-- ─────────────────────────────────────────────────────────────
local function HandleKeyboard(dt)
    if S.gameState == "gameover" then
        if input:GetKeyPress(KEY_RETURN) or input:GetKeyPress(KEY_SPACE) then
            RestartGame()
        end
        return
    end

    local steering = 0
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        steering = -1
    elseif input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        steering = 1
    end

    -- 触摸转向叠加
    if steering == 0 then
        steering = S.touchSteering
    end

    if steering ~= 0 then
        Boat.Steer(steering, dt)
    else
        Boat.ReturnCenter(dt)
    end

    -- W/S 调节油门（0 ~ 1 区间）
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then
        S.throttle = math.min(1.0, S.throttle + C.THROTTLE_STEP * dt)
    end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then
        S.throttle = math.max(0.0, S.throttle - C.THROTTLE_STEP * dt)
    end
end

-- ─────────────────────────────────────────────────────────────
--  触摸事件（屏幕左半 = 左转，右半 = 右转）
-- ─────────────────────────────────────────────────────────────
function HandleTouchBegin(eventType, eventData)
    if S.gameState == "gameover" then
        RestartGame()
        return
    end
    if S.touchId ~= -1 then return end
    S.touchId     = eventData["TouchID"]:GetInt()
    S.touchStartX = eventData["X"]:GetInt()
    S.touchStartY = eventData["Y"]:GetInt()

    local screenHalf = graphics:GetWidth() / 2
    S.touchSteering  = eventData["X"]:GetInt() < screenHalf and -1 or 1
end

function HandleTouchEnd(eventType, eventData)
    if eventData["TouchID"]:GetInt() ~= S.touchId then return end
    S.touchId       = -1
    S.touchSteering = 0
end

function HandleMousePress(eventType, eventData)
    if S.gameState == "gameover" then
        RestartGame()
    end
end

-- ─────────────────────────────────────────────────────────────
--  主入口
-- ─────────────────────────────────────────────────────────────
function Start()
    U.LogInfo("====== 海河飙车 · 启动 ======")

    if input then input:SetMouseVisible(true) end

    SceneMod.Init()
    Track.Init()
    Boat.Init()
    BoatPhys.Init()   -- 必须在 Boat.Init() 之后（需要 S.boatNode）
    Camera.Init()
    UI.Init()
    ThrottleUI.Init()

    SubscribeToEvent("TouchBegin",      "HandleTouchBegin")
    SubscribeToEvent("TouchEnd",        "HandleTouchEnd")
    SubscribeToEvent("MouseButtonDown", "HandleMousePress")
    SubscribeToEvent("Update",          "HandleUpdate")

    U.LogInfo("[Init] 全部模块初始化完成")
end

-- ─────────────────────────────────────────────────────────────
--  主循环
-- ─────────────────────────────────────────────────────────────
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    dt = math.min(dt, 0.05)

    HandleKeyboard(dt)

    if S.gameState ~= "playing" then return end

    -- 油门驱动速度：目标速度由油门开度决定，平滑插值逼近
    local targetSpeed = C.SPEED_MIN + S.throttle * (C.SPEED_MAX - C.SPEED_MIN)
    if S.speed < targetSpeed then
        S.speed = math.min(targetSpeed, S.speed + C.THROTTLE_ACCEL * dt)
    else
        S.speed = math.max(targetSpeed, S.speed - C.THROTTLE_DECAY * dt)
    end

    S.distanceMeter = S.distanceMeter + S.speed * dt
    S.score         = math.floor(S.distanceMeter) + S.coinCount * 10

    -- 低油门时缓慢回复耐久（鼓励减速驾驶）
    if S.throttle < C.DUR_REGEN_THR and S.durability < 1.0 then
        S.durability = math.min(1.0, S.durability + C.DUR_REGEN * dt)
    end

    Boat.Update(dt)
    Camera.Update(dt)
    Track.Update(S.boatPosX, S.boatPosZ)
    Obstacles.Update(dt)
    Coins.Update(dt)
    CheckCollisions()
    UI.Update(dt)
    ThrottleUI.Update()
end
