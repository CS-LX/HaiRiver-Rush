-- ============================================================
--  touchcontrols.lua  —  手机触屏虚拟按键（左/右/加速/刹车）
--
--  布局（屏幕底部两侧）：
--    左侧 ─ [左转] [右转]   右侧 ─ [加速] [刹车]
--
--  使用方式：
--    M.Init()               — 初始化，创建 UI 控件
--    M.Update(dt)           — 每帧调用，处理按键状态
--    M.GetSteering()        — 返回 -1 / 0 / +1
--    M.GetThrottleDelta(dt) — 返回本帧油门增量（已乘 dt）
--    M.SetVisible(v)        — 显示 / 隐藏
-- ============================================================
local C = require "config"
local S = require "state"

local M = {}

-- ── 布局常量（百分比或像素） ──────────────────────────────────
local BTN_SIZE   = 88    -- 每个按钮大小（像素）
local BTN_GAP    = 12    -- 按钮间间距
local MARGIN_X   = 24    -- 距屏幕左右边缘距离
local MARGIN_BOT = 100   -- 距屏幕底部距离（为仪表盘让位）

-- 按钮透明度
local ALPHA_IDLE = 0.40
local ALPHA_HOLD = 0.80

-- ── 按钮状态 ────────────────────────────────────────────────
-- 每个按钮记录：node（UI节点）、pressed（当前按下）、touchId（哪个手指）
local buttons = {}

-- ── 辅助：创建单个虚拟按钮 ────────────────────────────────────
local function MakeBtn(parent, label, x, y)
    local root = parent:CreateChild("BorderImage")
    root:SetAlignment(HA_LEFT, VA_BOTTOM)
    root:SetSize(IntVector2(BTN_SIZE, BTN_SIZE))
    root:SetPosition(IntVector2(x, -y))
    root:SetColor(Color(0.1, 0.25, 0.55, ALPHA_IDLE))

    local txt = root:CreateChild("Text")
    txt:SetFont(cache:GetResource("Font", "Fonts/MiSans-Regular.ttf"), 28)
    txt:SetColor(Color(1.0, 1.0, 1.0, 0.9))
    txt:SetAlignment(HA_CENTER, VA_CENTER)
    txt:SetPosition(IntVector2(0, 0))
    txt:SetText(label)

    return { node = root, pressed = false, touchId = -1 }
end

-- ── 判断触点是否在按钮矩形内（屏幕绝对坐标）─────────────────
local function InBtn(btn, tx, ty)
    local pos  = btn.node:GetScreenPosition()
    local size = btn.node:GetSize()
    return tx >= pos.x and tx <= pos.x + size.x
       and ty >= pos.y and ty <= pos.y + size.y
end

-- ── 刷新按钮外观 ─────────────────────────────────────────────
local function RefreshColor(btn, tint)
    local alpha = btn.pressed and ALPHA_HOLD or ALPHA_IDLE
    btn.node:SetColor(Color(tint.r, tint.g, tint.b, alpha))
end

local TINT = {
    left  = Color(0.10, 0.30, 0.70),
    right = Color(0.10, 0.30, 0.70),
    accel = Color(0.10, 0.60, 0.25),
    brake = Color(0.65, 0.22, 0.10),
}

-- ─────────────────────────────────────────────────────────────
--  Init
-- ─────────────────────────────────────────────────────────────
function M.Init()
    local uiRoot = ui:GetRoot()
    local sw     = graphics:GetWidth()

    -- 左侧：左转（最左）、右转（右边紧邻）
    local lx1 = MARGIN_X
    local lx2 = MARGIN_X + BTN_SIZE + BTN_GAP

    -- 右侧：加速（右侧靠内），刹车（最右）
    local rx2 = sw - MARGIN_X - BTN_SIZE          -- 刹车 x
    local rx1 = rx2 - BTN_SIZE - BTN_GAP          -- 加速 x

    local by = MARGIN_BOT   -- 距底部高度（VA_BOTTOM 时正数 = 向上）

    buttons.left  = MakeBtn(uiRoot, "<",  lx1, by)
    buttons.right = MakeBtn(uiRoot, ">",  lx2, by)
    buttons.accel = MakeBtn(uiRoot, "W",  rx1, by)
    buttons.brake = MakeBtn(uiRoot, "S",  rx2, by)

    -- 初始隐藏（游戏开始后显示）
    M.SetVisible(false)
end

-- ─────────────────────────────────────────────────────────────
--  触摸事件注册（由 main.lua 调用后从此模块处理）
-- ─────────────────────────────────────────────────────────────
function TouchControls_OnTouchBegin(eventType, eventData)
    if S.gameState ~= "playing" then return end
    local tid = eventData["TouchID"]:GetInt()
    local tx  = eventData["X"]:GetInt()
    local ty  = eventData["Y"]:GetInt()

    for _, btn in pairs(buttons) do
        if btn.touchId == -1 and InBtn(btn, tx, ty) then
            btn.pressed = true
            btn.touchId = tid
        end
    end
end

function TouchControls_OnTouchEnd(eventType, eventData)
    local tid = eventData["TouchID"]:GetInt()
    for _, btn in pairs(buttons) do
        if btn.touchId == tid then
            btn.pressed = false
            btn.touchId = -1
        end
    end
end

function TouchControls_OnTouchMove(eventType, eventData)
    if S.gameState ~= "playing" then return end
    local tid = eventData["TouchID"]:GetInt()
    local tx  = eventData["X"]:GetInt()
    local ty  = eventData["Y"]:GetInt()

    -- 手指移出按钮区域时释放
    for _, btn in pairs(buttons) do
        if btn.touchId == tid and not InBtn(btn, tx, ty) then
            btn.pressed = false
            btn.touchId = -1
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  每帧：刷新颜色
-- ─────────────────────────────────────────────────────────────
function M.Update()
    RefreshColor(buttons.left,  TINT.left)
    RefreshColor(buttons.right, TINT.right)
    RefreshColor(buttons.accel, TINT.accel)
    RefreshColor(buttons.brake, TINT.brake)
end

-- ─────────────────────────────────────────────────────────────
--  查询接口（供 main.lua 主循环读取）
-- ─────────────────────────────────────────────────────────────
function M.GetSteering()
    if buttons.left  and buttons.left.pressed  then return -1 end
    if buttons.right and buttons.right.pressed then return  1 end
    return 0
end

function M.IsAccelPressed()
    return buttons.accel and buttons.accel.pressed
end

function M.IsBrakePressed()
    return buttons.brake and buttons.brake.pressed
end

function M.SetVisible(v)
    for _, btn in pairs(buttons) do
        if btn.node then btn.node:SetVisible(v) end
    end
end

return M
