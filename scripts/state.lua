-- ============================================================
--  state.lua  —  全局共享可变状态表 S
--  所有模块 require 同一个表实例，通过引用共享修改
-- ============================================================
local C = require "config"

local S = {
    -- ── 场景节点 ──────────────────────────────────────────
    mainScene   = nil,
    cameraNode  = nil,
    boatNode    = nil,
    boatVisNode = nil,

    -- ── 快艇位置 / 朝向 ───────────────────────────────────
    boatPosX    = 0.0,
    boatPosY    = C.BOAT_BASE_Y,
    boatPosZ    = 0.0,
    boatHeading       = 0.0,    -- 偏航角（度），0 = +Z 方向
    boatTargetHeading = 0.0,    -- 碰墙后的目标偏航（船平滑转向这里）
    boatTiltZ   = 0.0,          -- 视觉侧倾角

    -- ── 赛道系统 ──────────────────────────────────────────
    trackPath        = {},      -- {x, z, heading} 中心线节点列表
    trackMeshes      = {},      -- {node, endZ} 活跃瓦片节点列表
    tilePool         = {},      -- 回收池
    trackEndX        = 0.0,     -- 当前赛道末端 X
    trackEndZ        = 0.0,     -- 当前赛道末端 Z
    trackEndHeading  = 0.0,     -- 当前赛道末端朝向

    -- ── 游戏进程 ──────────────────────────────────────────
    gameState     = "playing",  -- "playing" | "gameover"
    speed         = C.SPEED_INIT,
    throttle      = 0.25,       -- 油门开度（0 ~ 1）
    score         = 0,
    coinCount     = 0,
    distanceMeter = 0.0,
    hintTimer     = 8.0,

    -- ── 输入 / 触摸 ───────────────────────────────────────
    touchId     = -1,
    touchStartX = 0,
    touchStartY = 0,
    touchSteering = 0,          -- 触摸转向：-1/0/+1

    -- ── 对象池 ────────────────────────────────────────────
    obstaclePool    = {},
    activeObstacles = {},
    coinPool        = {},
    activeCoins     = {},

    -- ── 生成计时 ──────────────────────────────────────────
    obstTimer    = 0.0,
    coinTimer    = 0.0,
    obstInterval = 2.0,

    -- ── UI 节点 ───────────────────────────────────────────
    uiRoot       = nil,
    scoreText    = nil,
    coinText     = nil,
    speedText    = nil,
    hintText     = nil,
    gameOverRoot = nil,
}

return S
