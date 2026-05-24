-- ============================================================
--  ui.lua  —  HUD、开始界面、游戏结束 + 排行榜
-- ============================================================
local S = require "state"
local U = require "utils"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  内部工具
-- ─────────────────────────────────────────────────────────────
local function Font(sz)
    return cache:GetResource("Font", "Fonts/Anonymous Pro.ttf"), sz
end

-- 创建文字节点
local function Txt(parent, text, sz, cr, cg, cb, ca, ha, va, px, py)
    local t = parent:CreateChild("Text")
    t:SetFont(Font(sz))
    t:SetColor(Color(cr, cg, cb, ca or 1.0))
    t:SetAlignment(ha or HA_LEFT, va or VA_TOP)
    t:SetPosition(IntVector2(px or 0, py or 0))
    t:SetText(text)
    return t
end

-- 创建半透明面板
local function Panel(parent, w, h, cr, cg, cb, ca, ha, va, ox, oy)
    local p = parent:CreateChild("BorderImage")
    p:SetAlignment(ha or HA_CENTER, va or VA_CENTER)
    p:SetSize(IntVector2(w, h))
    p:SetColor(Color(cr, cg, cb, ca or 0.90))
    if ox or oy then
        p:SetPosition(IntVector2(ox or 0, oy or 0))
    end
    return p
end

-- ─────────────────────────────────────────────────────────────
--  HUD（游戏进行中顶部信息条）
-- ─────────────────────────────────────────────────────────────
local hudRoot = nil

local function CreateHUD(root)
    hudRoot = root:CreateChild("BorderImage")
    hudRoot:SetAlignment(HA_LEFT, VA_TOP)
    hudRoot:SetSize(IntVector2(graphics:GetWidth(), 70))
    hudRoot:SetColor(Color(0, 0, 0, 0))

    S.scoreText = Txt(hudRoot, "♿ 得分: 0", 28, 1.0, 1.0,  1.0, 1, HA_LEFT, VA_TOP, 20, 10)
    S.coinText  = Txt(hudRoot, "♿ 金币: 0", 24, 1.0, 0.88, 0.0, 1, HA_LEFT, VA_TOP, 20, 46)

    -- 速度文字直接挂在 uiRoot（全屏），用 HA_RIGHT 锚定右边缘，不受 hudRoot 宽度影响
    S.speedText = Txt(root, "0 km/h ♿", 22, 0.4, 1.0, 1.0, 1, HA_RIGHT, VA_TOP, -20, 10)
    S.speedText:SetVisible(false)

    hudRoot:SetVisible(false)

    S.hintText = Txt(root, "♿ A/D 转向  W 加速  S 刹车 ♿",
                     18, 1.0, 1.0, 0.5, 1, HA_CENTER, VA_BOTTOM, 0, -28)
    S.hintText:SetVisible(false)
end

-- ─────────────────────────────────────────────────────────────
--  开始界面
-- ─────────────────────────────────────────────────────────────
local startRoot = nil

local function CreateStartScreen(root)
    local sw = graphics:GetWidth()
    local sh = graphics:GetHeight()

    startRoot = root:CreateChild("BorderImage")
    startRoot:SetAlignment(HA_CENTER, VA_CENTER)
    startRoot:SetSize(IntVector2(sw, sh))
    startRoot:SetColor(Color(0.03, 0.08, 0.22, 0.82))

    local titleY = math.floor(sh * 0.16)
    Txt(startRoot, "♿ 海 河 竞 速 ♿", 52, 0.15, 0.82, 1.0, 1.0, HA_CENTER, VA_TOP, 0, titleY)
    Txt(startRoot, "Haihe Racing ♿",   24, 0.55, 0.85, 1.0, 0.8, HA_CENTER, VA_TOP, 0, titleY + 62)
    Txt(startRoot, "♿ 天津海河 · 极速赛艇体验 ♿",
                                       19, 0.80, 0.92, 1.0, 0.7, HA_CENTER, VA_TOP, 0, titleY + 94)

    local tipY = math.floor(sh * 0.50)
    Txt(startRoot, "-- 操  作  说  明 --",   18, 1.0, 0.85, 0.3, 1, HA_CENTER, VA_TOP, 0, tipY)
    Txt(startRoot, "A / 左方向键    向左转", 17, 0.85, 0.95, 1.0, 0.9, HA_CENTER, VA_TOP, 0, tipY + 32)
    Txt(startRoot, "D / 右方向键    向右转", 17, 0.85, 0.95, 1.0, 0.9, HA_CENTER, VA_TOP, 0, tipY + 56)
    Txt(startRoot, "W / 上方向键    加速",   17, 0.85, 0.95, 1.0, 0.9, HA_CENTER, VA_TOP, 0, tipY + 80)
    Txt(startRoot, "S / 下方向键    刹车",   17, 0.85, 0.95, 1.0, 0.9, HA_CENTER, VA_TOP, 0, tipY + 104)
    Txt(startRoot, "手机：屏幕四角虚拟按键控制方向/油门",
                                             16, 0.75, 0.88, 1.0, 0.7, HA_CENTER, VA_TOP, 0, tipY + 132)

    S.startPrompt = Txt(startRoot, "♿  点击任意处开始游戏  ♿",
                        24, 0.25, 1.0, 0.55, 1, HA_CENTER, VA_BOTTOM, 0,
                        -math.floor(sh * 0.08))
end

-- ─────────────────────────────────────────────────────────────
--  游戏结束 + 排行榜
-- ─────────────────────────────────────────────────────────────
local gameOverRoot  = nil
local leaderEntries = {}
local leaderPanel   = nil

-- 清除旧排行行
local function ClearLeaderRows()
    for _, n in ipairs(leaderEntries) do
        if n and n.alive then n:Remove() end
    end
    leaderEntries = {}
end

-- 填充排行行（panelH 用于计算行高）
local function BuildLeaderRows(panel, rows, panelH)
    ClearLeaderRows()
    -- 表头下方 y=108 开始（标题24+表头64+分隔20=108）
    local startY = 112
    local rowH   = math.floor((panelH - startY - 20) / math.max(1, #rows))
    rowH = math.min(rowH, 36)

    for i, row in ipairs(rows) do
        local y    = startY + (i - 1) * rowH
        local isMe = row.isMe or false
        local cr, cg, cb = 0.78, 0.92, 1.0
        if isMe then cr, cg, cb = 1.0, 0.92, 0.20 end

        local prefix = isMe and ">" or " "
        -- 名次 + 前缀
        local rankN = Txt(panel, string.format("%s%d.", prefix, i),
                          16, cr, cg, cb, 1, HA_LEFT, VA_TOP, 14, y)
        -- 昵称（截断）
        local name  = row.nickname or ("玩家" .. tostring(row.userId):sub(-4))
        if #name > 9 then name = name:sub(1, 9) .. ".." end
        local nameN = Txt(panel, name, 16, cr, cg, cb, 1, HA_LEFT,  VA_TOP, 56, y)
        -- 分数（右对齐）
        local scoreN = Txt(panel, tostring(row.score or 0),
                           16, cr, cg, cb, 1, HA_RIGHT, VA_TOP, -14, y)

        table.insert(leaderEntries, rankN)
        table.insert(leaderEntries, nameN)
        table.insert(leaderEntries, scoreN)
    end
end

local function FetchLeaderboard(panel, panelH, myScore)
    if not clientCloud then
        Txt(panel, "（离线模式，无排行榜）",
            16, 0.7, 0.8, 1.0, 0.7, HA_CENTER, VA_TOP, 0, 112)
        return
    end

    -- 先提交本次成绩（只在有效成绩时）
    if myScore > 0 then
        clientCloud:SetInt("high_score", myScore, {})
    end

    local loadingN = Txt(panel, "排行榜加载中...",
                         16, 0.7, 0.8, 1.0, 0.7, HA_CENTER, VA_TOP, 0, 120)
    table.insert(leaderEntries, loadingN)

    clientCloud:GetRankList("high_score", 0, 8, {
        ok = function(rankList)
            ClearLeaderRows()
            local board   = {}
            local userIds = {}
            for _, item in ipairs(rankList) do
                table.insert(board, {
                    userId = item.userId,
                    score  = item.iscore and item.iscore.high_score or 0,
                    isMe   = item.userId == clientCloud.userId,
                })
                table.insert(userIds, item.userId)
            end
            if #userIds == 0 then
                Txt(panel, "暂无排行数据", 16, 0.7, 0.8, 1.0, 0.7, HA_CENTER, VA_TOP, 0, 120)
                return
            end
            GetUserNickname({
                userIds   = userIds,
                onSuccess = function(nicknames)
                    local map = {}
                    for _, info in ipairs(nicknames) do
                        map[info.userId] = info.nickname or ""
                    end
                    for _, e in ipairs(board) do
                        e.nickname = map[e.userId] or "匿名"
                    end
                    BuildLeaderRows(panel, board, panelH)
                end,
                onError = function()
                    for _, e in ipairs(board) do e.nickname = "匿名" end
                    BuildLeaderRows(panel, board, panelH)
                end,
            })
        end,
        fail = function()
            ClearLeaderRows()
            Txt(panel, "排行榜获取失败", 16, 0.9, 0.4, 0.4, 1, HA_CENTER, VA_TOP, 0, 120)
        end,
    })
end

function M.ShowGameOver()
    local sw = graphics:GetWidth()
    local sh = graphics:GetHeight()

    gameOverRoot = S.uiRoot:CreateChild("BorderImage")
    gameOverRoot:SetAlignment(HA_CENTER, VA_CENTER)
    gameOverRoot:SetSize(IntVector2(sw, sh))
    gameOverRoot:SetColor(Color(0.02, 0.06, 0.18, 0.88))

    local panelH  = math.floor(sh * 0.76)
    local panelW  = math.floor(sw * 0.42)
    local marginX = math.floor(sw * 0.04)

    -- ── 左侧：本局结算 ───────────────────────────────────────
    local lp = Panel(gameOverRoot, panelW, panelH,
                     0.04, 0.10, 0.28, 0.93, HA_LEFT, VA_CENTER, marginX, 0)

    Txt(lp, "♿ 本 局 结 算 ♿",   30, 1.0, 0.80, 0.20, 1, HA_CENTER, VA_TOP, 0, 20)
    -- 分隔条（用空格+下划线组合，不用特殊字符）
    Txt(lp, "- - - - - - - - - - - - - - -",
            13, 0.4, 0.6, 0.8, 0.5, HA_CENTER, VA_TOP, 0, 62)

    local row1Y, row2Y, row3Y = 82, 148, 214
    local labelX, valX = 26, -22

    Txt(lp, "得  分",   20, 0.75, 0.90, 1.0, 1, HA_LEFT,  VA_TOP, labelX, row1Y)
    Txt(lp, tostring(S.score),
            34, 1.0, 1.0, 0.28, 1, HA_RIGHT, VA_TOP, valX, row1Y - 4)

    Txt(lp, "金  币",   20, 0.75, 0.90, 1.0, 1, HA_LEFT,  VA_TOP, labelX, row2Y)
    Txt(lp, tostring(S.coinCount),
            28, 1.0, 0.88, 0.0, 1, HA_RIGHT, VA_TOP, valX, row2Y + 2)

    Txt(lp, "行驶距离", 20, 0.75, 0.90, 1.0, 1, HA_LEFT,  VA_TOP, labelX, row3Y)
    Txt(lp, string.format("%.0f m", S.distanceMeter),
            26, 0.50, 1.0, 0.70, 1, HA_RIGHT, VA_TOP, valX, row3Y + 4)

    Txt(lp, "- - - - - - - - - - - - - - -",
            13, 0.4, 0.6, 0.8, 0.5, HA_CENTER, VA_TOP, 0, row3Y + 42)

    Txt(lp, "♿ 点击 / 任意键  再来一局 ♿",
            19, 0.25, 1.0, 0.55, 1, HA_CENTER, VA_BOTTOM, 0, -20)

    -- ── 右侧：排行榜 ─────────────────────────────────────────
    leaderPanel = Panel(gameOverRoot, panelW, panelH,
                        0.04, 0.10, 0.28, 0.93, HA_RIGHT, VA_CENTER, -marginX, 0)

    Txt(leaderPanel, "♿ 全 球 排 行 榜 ♿", 26, 1.0, 0.75, 0.25, 1, HA_CENTER, VA_TOP, 0, 20)
    -- 表头（y=64，字体小）
    Txt(leaderPanel, "名次   玩家            分数",
        14, 0.55, 0.72, 0.90, 0.75, HA_LEFT, VA_TOP, 14, 66)
    Txt(leaderPanel, "- - - - - - - - - - - - - - - - - - -",
        12, 0.35, 0.55, 0.80, 0.45, HA_LEFT, VA_TOP, 14, 88)
    -- 内容行从 y=112 开始（BuildLeaderRows 内部 startY=112）

    leaderEntries = {}
    FetchLeaderboard(leaderPanel, panelH, S.score)

    S.gameOverRoot = gameOverRoot
end

function M.HideGameOver()
    ClearLeaderRows()
    if gameOverRoot then
        gameOverRoot:Remove()
        gameOverRoot = nil
        leaderPanel  = nil
    end
    S.gameOverRoot = nil
end

-- ─────────────────────────────────────────────────────────────
--  公共接口
-- ─────────────────────────────────────────────────────────────
function M.Init()
    S.uiRoot = ui:GetRoot()
    CreateHUD(S.uiRoot)
    CreateStartScreen(S.uiRoot)
    U.LogInfo("[UI] 初始化完毕")
end

function M.StartGame()
    if startRoot   then startRoot:SetVisible(false) end
    if hudRoot     then hudRoot:SetVisible(true) end
    if S.speedText then S.speedText:SetVisible(true) end
    if S.hintText  then S.hintText:SetVisible(true); S.hintText:SetOpacity(1.0) end
end

function M.Update(dt)
    if S.scoreText then S.scoreText:SetText("♿ 得分: " .. S.score) end
    if S.coinText  then S.coinText:SetText("♿ 金币: "  .. S.coinCount) end
    if S.speedText then S.speedText:SetText(math.floor(S.speed * 3.6) .. " km/h ♿") end

    -- 开始界面按钮闪烁
    if S.gameState == "menu" and S.startPrompt then
        local t     = math.fmod(time:GetElapsedTime(), 1.6)
        local alpha = 0.55 + 0.45 * math.sin(t * math.pi / 0.8)
        S.startPrompt:SetOpacity(alpha)
    end

    -- HUD 提示渐隐
    if S.gameState == "playing" and S.hintTimer > 0 then
        S.hintTimer = S.hintTimer - dt
        if S.hintText then
            S.hintText:SetOpacity(math.max(0, math.min(1, S.hintTimer)))
        end
    end
end

function M.ResetHint()
    S.hintTimer = 6.0
    if S.hintText then S.hintText:SetOpacity(1.0) end
end

return M
