-- ============================================================
--  海河飙车 (Haihe Rush) - 自由驾驶河道赛车游戏
--  入口文件：模块加载、事件注册、主循环编排
-- ============================================================

local C             = require "config"
local S             = require "state"
local U             = require "utils"
local SceneMod      = require "scene"
local Track         = require "track"
local Boat          = require "boat"
local BoatPhys      = require "boatphys"
local Obstacles     = require "obstacles"   -- 内部会 require gameboat
local Coins         = require "coins"
local Camera        = require "camera"
local UI            = require "ui"
local ThrottleUI    = require "throttleui"
local Water         = require "water"
local Particles     = require "particles"
local Vegetation    = require "vegetation"
local Buildings     = require "buildings"
local Audio         = require "audio"
local TouchControls = require "touchcontrols"

-- ─────────────────────────────────────────────────────────────
--  耐久度扣减（全局，供 boatphys.lua 调用）
-- ─────────────────────────────────────────────────────────────
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
--  开始游戏（menu → playing）
-- ─────────────────────────────────────────────────────────────
local function StartGame()
    if S.gameState ~= "menu" then return end
    U.LogInfo("[Game] 开始游戏")
    S.gameState = "playing"
    UI.StartGame()
    UI.ResetHint()
    TouchControls.SetVisible(true)
end

-- ─────────────────────────────────────────────────────────────
--  重新开始（gameover → playing）
-- ─────────────────────────────────────────────────────────────
local function RestartGame()
    if S.gameState ~= "gameover" then return end
    U.LogInfo("[Game] 重新开始")

    Obstacles.ClearAll()
    Coins.ClearAll()
    Boat.Reset()
    BoatPhys.Reset()
    Camera.Reset()
    Track.Reset()
    Water.Reset()
    Particles.Reset()
    UI.HideGameOver()
    UI.ResetHint()
    TouchControls.SetVisible(true)

    S.speed         = C.SPEED_INIT
    S.throttle      = 0.25
    S.score         = 0
    S.coinCount     = 0
    S.distanceMeter = 0.0
    S.durability    = 1.0
    S.gameState     = "playing"
    S.touchSteering = 0
end

-- ─────────────────────────────────────────────────────────────
--  键盘输入
-- ─────────────────────────────────────────────────────────────
local function HandleKeyboard(dt)
    -- menu 状态：任意键开始
    if S.gameState == "menu" then
        if input:GetKeyPress(KEY_RETURN) or input:GetKeyPress(KEY_SPACE)
        or input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_D)
        or input:GetKeyDown(KEY_LEFT) or input:GetKeyDown(KEY_RIGHT)
        or input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then
            StartGame()
        end
        return
    end

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

    -- 合并触屏转向（虚拟按键优先于旧半屏逻辑）
    if steering == 0 then
        local tc = TouchControls.GetSteering()
        steering = (tc ~= 0) and tc or S.touchSteering
    end

    if steering ~= 0 then
        Boat.Steer(steering, dt)
    else
        Boat.ReturnCenter(dt)
    end

    -- 油门：键盘 + 虚拟按键
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) or TouchControls.IsAccelPressed() then
        S.throttle = math.min(1.0, S.throttle + C.THROTTLE_STEP * dt)
    end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) or TouchControls.IsBrakePressed() then
        S.throttle = math.max(0.0, S.throttle - C.THROTTLE_STEP * dt)
    end
end

-- ─────────────────────────────────────────────────────────────
--  触摸事件
-- ─────────────────────────────────────────────────────────────
function HandleTouchBegin(eventType, eventData)
    if S.gameState == "menu" then
        StartGame()
        return
    end
    if S.gameState == "gameover" then
        RestartGame()
        return
    end

    -- 先让虚拟按键消费此触点
    TouchControls_OnTouchBegin(eventType, eventData)

    -- 若虚拟按键已处理（GetSteering 非零），不再走旧半屏逻辑
    if TouchControls.GetSteering() ~= 0 then return end

    -- 旧半屏逻辑（未点中虚拟按键时的兜底）
    if S.touchId ~= -1 then return end
    S.touchId       = eventData["TouchID"]:GetInt()
    S.touchStartX   = eventData["X"]:GetInt()
    S.touchStartY   = eventData["Y"]:GetInt()
    local screenHalf = graphics:GetWidth() / 2
    S.touchSteering  = eventData["X"]:GetInt() < screenHalf and -1 or 1
end

function HandleTouchEnd(eventType, eventData)
    -- 转发给虚拟按键
    TouchControls_OnTouchEnd(eventType, eventData)

    -- 旧半屏逻辑释放
    if eventData["TouchID"]:GetInt() == S.touchId then
        S.touchId       = -1
        S.touchSteering = 0
    end
end

function HandleMousePress(eventType, eventData)
    if S.gameState == "menu" then
        StartGame()
    elseif S.gameState == "gameover" then
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
    Vegetation.Init()
    Buildings.Init()
    Water.Init()
    Boat.Init()
    Particles.Init()
    BoatPhys.Init()
    Camera.Init()
    UI.Init()
    ThrottleUI.Init()
    TouchControls.Init()
    Audio.Init(S.mainScene)

    SubscribeToEvent("TouchBegin",      "HandleTouchBegin")
    SubscribeToEvent("TouchEnd",        "HandleTouchEnd")
    SubscribeToEvent("TouchMove",       "TouchControls_OnTouchMove")
    SubscribeToEvent("MouseButtonDown", "HandleMousePress")
    SubscribeToEvent("Update",          "HandleUpdate")

    U.LogInfo("[Init] 全部模块初始化完成，等待玩家开始")
end

-- ─────────────────────────────────────────────────────────────
--  主循环
-- ─────────────────────────────────────────────────────────────
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    dt = math.min(dt, 0.05)

    HandleKeyboard(dt)
    UI.Update(dt)

    -- menu 状态：只更新相机和水面动画，船不移动
    if S.gameState == "menu" then
        Water.Update(dt)
        Camera.Update(dt)
        return
    end

    if S.gameState ~= "playing" then return end

    -- 油门驱动速度
    local targetSpeed = C.SPEED_MIN + S.throttle * (C.SPEED_MAX - C.SPEED_MIN)
    if S.speed < targetSpeed then
        S.speed = math.min(targetSpeed, S.speed + C.THROTTLE_ACCEL * dt)
    else
        S.speed = math.max(targetSpeed, S.speed - C.THROTTLE_DECAY * dt)
    end

    S.distanceMeter = S.distanceMeter + S.speed * dt
    S.score = math.floor(S.distanceMeter) + S.coinCount * 10

    -- 低油门缓慢回复耐久
    if S.throttle < C.DUR_REGEN_THR and S.durability < 1.0 then
        S.durability = math.min(1.0, S.durability + C.DUR_REGEN * dt)
    end

    Boat.Update(dt)
    Particles.Update(dt)
    Camera.Update(dt)
    Track.Update(S.boatPosX, S.boatPosZ)
    Water.Update(dt)
    Obstacles.Update(dt)
    Coins.Update(dt)
    ThrottleUI.Update()
    TouchControls.Update()
end
