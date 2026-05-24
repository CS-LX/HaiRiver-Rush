-- ============================================================
--  config.lua  —  所有游戏常量，只读
-- ============================================================
local M = {}

-- 船速
M.SPEED_INIT      = 16.0
M.SPEED_MIN       = 4.0        -- 油门归零时的最低惰行速度
M.SPEED_MAX       = 82.5   -- 原 55.0 × 1.5

-- 油门系统
M.THROTTLE_STEP   = 0.6        -- 每秒 W/S 改变油门的量（0-1 区间）
M.THROTTLE_ACCEL  = 28.0       -- 速度向目标加速时的加速度（m/s²）
M.THROTTLE_DECAY  = 22.0       -- 速度向目标减速时的减速度（m/s²）

-- 碰墙惩罚
M.HIT_SPEED_LOSS  = 14.0       -- 碰墙固定扣除速度（m/s）
M.HIT_TURN_SPEED  = 160.0      -- 碰墙后转向动画角速度（度/秒）

-- 转向
M.STEER_SPEED     = 90.0        -- 度/秒
M.BOAT_BASE_Y     = 0.35

-- 赛道尺寸
M.TRACK_WIDTH     = 24.0        -- 河道宽度（米）（原16m，拓宽1.5倍）
M.TILE_LEN        = 10.0        -- 每块瓦片长度
M.TILES_PER_SEG   = 6           -- 每段瓦片数
M.NUM_INIT_SEGS   = 6           -- 初始生成段数

-- 弯道参数
M.CURVE_ANGLE     = 36.0        -- 每段弯道总转角（度）

-- 河岸墙壁
M.WALL_H          = 3.2
M.WALL_W          = 1.8

-- 生成 / 回收距离
M.SPAWN_DIST      = 120.0       -- 前方多远生成障碍物/金币
M.RECYCLE_DIST    = 60.0        -- 落后多远回收

-- 摄像机
M.CAM_BACK        = 10.0        -- 跟随距离（后方）
M.CAM_UP          = 5.5         -- 抬升高度
M.CAM_LERP        = 0.10

-- 输入
M.SWIPE_MIN       = 40

-- 金币
M.COIN_ROW_LEN    = 5
M.COIN_GAP        = 2.2

-- 耐久度（0.0 ~ 1.0 浮点，连续进度条）
--   碰墙：0.15 + 0.10*(speed/SPEED_MAX)  → 低速 15%，满速 25%
--   浮标：固定 0.10
--   游船：固定 0.22
--   恢复：+0.008/秒（油门 < 0.5 时才回血，鼓励减速驾驶）
M.DMG_WALL_BASE   = 0.15     -- 碰墙基础扣量
M.DMG_WALL_SPEED  = 0.10     -- 碰墙速度系数（×speed/SPEED_MAX）
M.DMG_BUOY        = 0.10     -- 撞浮标扣量
M.DMG_GAMEBOAT    = 0.22     -- 撞游船扣量
M.DUR_REGEN       = 0.008    -- 每秒回复量（低油门时生效）
M.DUR_REGEN_THR   = 0.50     -- 油门低于此值才回血
M.OBS_HIT_CD      = 0.8      -- 障碍物碰撞冷却（秒）

-- 跳跃
M.JUMP_VY         = 9.0      -- 起跳初速度（m/s）
M.JUMP_GRAVITY    = 22.0     -- 跳跃重力加速度（m/s²）
M.JUMP_MIN_Y      = 1.8      -- 超过此高度才能跳过游船（m）
M.JUMP_SHORE_Y    = 0.5      -- 超过此高度且落在岸上判定撞岸（m）

return M
