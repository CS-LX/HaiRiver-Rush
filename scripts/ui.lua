-- ============================================================
--  ui.lua  —  HUD、开始界面、游戏结束 + 排行榜
-- ============================================================
local S = require "state"
local U = require "utils"

local M = {}

-- ─────────────────────────────────────────────────────────────
--  内部工具
-- ─────────────────────────────────────────────────────────────
local function GetFont(size)
    local f = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    return f, size
end

local function MakeText(parent, txt, size, r, g, b, a, hAlign, vAlign, px, py)
    local t = parent:CreateChild("Text")
    t:SetFont(GetFont(size))
    t:SetColor(Color(r, g, b, a or 1))
    t:SetAlignment(hAlign or HA_LEFT, vAlign or VA_TOP)
    t:SetPosition(IntVector2(px or 0, py or 0))
    t:SetText(txt)
    return t
end

local function MakePanel(parent, w, h, r, g, b, a, hAlign, vAlign)
    local p = parent:CreateChild("BorderImage")
    p:SetAlignment(hAlign or HA_CENTER, vAlign or VA_CENTER)
    p:SetSize(IntVector2(w, h))
    p:SetColor(Color(r, g, b, a or 0.88))
    return p
end

-- ─────────────────────────────────────────────────────────────
--  HUD（游戏进行中的顶部信息条）
-- ─────────────────────────────────────────────────────────────
local hudRoot = nil

local function CreateHUD(root)
    hudRoot = root:CreateChild("BorderImage")
    hudRoot:SetAlignment(HA_LEFT, VA_TOP)
    hudRoot:SetSize(IntVector2(graphics:GetWidth(), 70))
    hudRoot:SetColor(Color(0, 0, 0, 0))  -- 透明容器

    S.scoreText = MakeText(hudRoot, "得分: 0",    28, 1.0, 1.0, 1.0, 1, HA_LEFT,  VA_TOP, 20, 10)
    S.coinText  = MakeText(hudRoot, "金币: 0",    24, 1.0, 0.88, 0.0, 1, HA_LEFT,  VA_TOP, 20, 46)
    S.speedText = MakeText(hudRoot, "0 km/h",     22, 0.4, 1.0, 1.0, 1, HA_RIGHT, VA_TOP, -20, 10)

    S.hintText  = MakeText(root, "A/D 转向  ·  W 加速  ·  S 刹车",
                           18, 1.0, 1.0, 0.5, 1, HA_CENTER, VA_BOTTOM, 0, -28)
    hudRoot:SetVisible(false)
end

-- ─────────────────────────────────────────────────────────────
--  开始界面
-- ─────────────────────────────────────────────────────────────
local startRoot = nil

local function CreateStartScreen(root)
    local sw = graphics:GetWidth()
    local sh = graphics:GetHeight()

    -- 半透明深蓝遮罩
    startRoot = root:CreateChild("BorderImage")
    startRoot:SetAlignment(HA_CENTER, VA_CENTER)
    startRoot:SetSize(IntVector2(sw, sh))
    startRoot:SetColor(Color(0.03, 0.08, 0.22, 0.82))

    -- 游戏标题
    MakeText(startRoot, "海 河 飙 车", 52, 0.15, 0.82, 1.0, 1, HA_CENTER, VA_TOP, 0, math.floor(sh * 0.18))
    MakeText(startRoot, "Haihe Rush", 26, 0.55, 0.85, 1.0, 0.8, HA_CENTER, VA_TOP, 0, math.floor(sh * 0.18) + 62)

    -- 副标题
    MakeText(startRoot, "天津海河 · 极速赛艇体验", 20, 0.80, 0.92, 1.0, 0.75,
             HA_CENTER, VA_TOP, 0, math.floor(sh * 0.18) + 100)

    -- 分隔线（用短横线模拟）
    MakeText(startRoot, "─────────────────────────────",
             16, 0.3, 0.6, 0.9, 0.5, HA_CENTER, VA_TOP, 0, math.floor(sh * 0.18) + 132)

    -- 操作提示
    local tipY = math.floor(sh * 0.55)
    MakeText(startRoot, "操作说明", 20, 1.0, 0.85, 0.3, 1, HA_CENTER, VA_TOP, 0, tipY)
    MakeText(startRoot, "A / ←   左转          D / →   右转",
             18, 0.85, 0.95, 1.0, 0.85, HA_CENTER, VA_TOP, 0, tipY + 32)
    MakeText(startRoot, "W / ↑   加速          S / ↓   刹车",
             18, 0.85, 0.95, 1.0, 0.85, HA_CENTER, VA_TOP, 0, tipY + 58)
    MakeText(startRoot, "手机：点击屏幕左半转向，右半右转",
             17, 0.75, 0.88, 1.0, 0.7, HA_CENTER, VA_TOP, 0, tipY + 88)

    -- 开始按钮提示（闪烁文字）
    S.startPrompt = MakeText(startRoot, "▶  点击任意处开始游戏  ◀",
                             24, 0.25, 1.0, 0.55, 1, HA_CENTER, VA_BOTTOM, 0,
                             -math.floor(sh * 0.10))
end

-- ─────────────────────────────────────────────────────────────
--  游戏结束 + 排行榜
-- ─────────────────────────────────────────────────────────────
local gameOverRoot  = nil
local leaderEntries = {}   -- 排行榜行节点列表（供刷新用）
local leaderPanel   = nil

local function BuildLeaderRows(panel, rows, myScore)
    -- 清除旧行
    for _, n in ipairs(leaderEntries) do n:Remove() end
    leaderEntries = {}

    local panelW = 400
    local rowH   = 34
    local startY = 28

    for i, row in ipairs(rows) do
        local y     = startY + (i - 1) * rowH
        local isMe  = row.isMe or false
        local name  = row.nickname or ("玩家" .. row.userId)
        local score = row.score or 0

        -- 高亮自己
        local r, g, b = 0.75, 0.90, 1.0
        if isMe then r, g, b = 1.0, 0.92, 0.20 end

        -- 名次
        MakeText(panel, string.format("%d.", i),
                 17, r, g, b, 1, HA_LEFT, VA_TOP, 18, y)
        -- 昵称（截断过长）
        local dispName = name
        if #dispName > 10 then dispName = dispName:sub(1, 10) .. "…" end
        local nameNode = MakeText(panel, dispName,
                 17, r, g, b, 1, HA_LEFT, VA_TOP, 52, y)
        -- 分数（右对齐）
        MakeText(panel, tostring(score),
                 17, r, g, b, 1, HA_RIGHT, VA_TOP, -18, y)

        table.insert(leaderEntries, nameNode)
    end
end

local function FetchAndShowLeaderboard(panel, myScore)
    -- 先提交本次成绩
    if clientCloud then
        clientCloud:SetInt("high_score", myScore, {})
    end

    local statusNode = MakeText(panel, "排行榜加载中…",
                                17, 0.7, 0.8, 1.0, 0.8, HA_CENTER, VA_TOP, 0, 28)
    table.insert(leaderEntries, statusNode)

    if not clientCloud then
        -- 离线模式：只显示本次成绩
        statusNode:SetText("（离线模式，无排行榜）")
        return
    end

    clientCloud:GetRankList("high_score", 0, 8, {
        ok = function(rankList)
            local leaderboard = {}
            local userIds     = {}
            for _, item in ipairs(rankList) do
                table.insert(leaderboard, {
                    userId = item.userId,
                    score  = item.iscore and item.iscore.high_score or 0,
                    isMe   = item.userId == clientCloud.userId,
                })
                table.insert(userIds, item.userId)
            end

            if #userIds == 0 then
                statusNode:SetText("暂无排行数据")
                return
            end

            -- 查询昵称
            GetUserNickname({
                userIds   = userIds,
                onSuccess = function(nicknames)
                    local map = {}
                    for _, info in ipairs(nicknames) do
                        map[info.userId] = info.nickname or ""
                    end
                    for _, entry in ipairs(leaderboard) do
                        entry.nickname = map[entry.userId] or "匿名玩家"
                    end
                    statusNode:Remove()
                    -- 从 leaderEntries 里删掉 statusNode
                    for k, v in ipairs(leaderEntries) do
                        if v == statusNode then
                            table.remove(leaderEntries, k)
                            break
                        end
                    end
                    BuildLeaderRows(panel, leaderboard, myScore)
                end,
                onError = function()
                    statusNode:SetText("（昵称获取失败）")
                    BuildLeaderRows(panel, leaderboard, myScore)
                end,
            })
        end,
        fail = function()
            statusNode:SetText("排行榜获取失败")
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

    -- ── 左侧：本局结算 ───────────────────────────────────
    local leftW = math.floor(sw * 0.42)
    local panel = MakePanel(gameOverRoot, leftW, math.floor(sh * 0.72),
                            0.04, 0.10, 0.28, 0.92, HA_LEFT, VA_CENTER)
    panel:SetPosition(IntVector2(math.floor(sw * 0.05), 0))

    MakeText(panel, "本 局 结 算",   32, 1.0, 0.80, 0.20, 1, HA_CENTER, VA_TOP, 0, 24)
    MakeText(panel, "得  分",        20, 0.75, 0.90, 1.0,  1, HA_LEFT,  VA_TOP, 30, 90)
    MakeText(panel, tostring(S.score), 36, 1.0, 1.0, 0.3, 1, HA_RIGHT, VA_TOP, -30, 82)
    MakeText(panel, "金  币",        20, 0.75, 0.90, 1.0,  1, HA_LEFT,  VA_TOP, 30, 148)
    MakeText(panel, tostring(S.coinCount), 28, 1.0, 0.88, 0.0, 1, HA_RIGHT, VA_TOP, -30, 144)
    MakeText(panel, "行驶距离",      20, 0.75, 0.90, 1.0,  1, HA_LEFT,  VA_TOP, 30, 200)
    MakeText(panel, string.format("%.0f m", S.distanceMeter),
                                    28, 0.55, 1.0, 0.75, 1, HA_RIGHT, VA_TOP, -30, 196)

    -- 分隔线
    MakeText(panel, "─────────────────",
             16, 0.3, 0.5, 0.8, 0.5, HA_CENTER, VA_TOP, 0, 250)

    -- 重玩提示
    MakeText(panel, "▶  点击 / 任意键  再来一局",
             20, 0.25, 1.0, 0.55, 1, HA_CENTER, VA_BOTTOM, 0, -24)

    -- ── 右侧：排行榜 ─────────────────────────────────────
    local rightW = math.floor(sw * 0.42)
    leaderPanel = MakePanel(gameOverRoot, rightW, math.floor(sh * 0.72),
                            0.04, 0.10, 0.28, 0.92, HA_RIGHT, VA_CENTER)
    leaderPanel:SetPosition(IntVector2(-math.floor(sw * 0.05), 0))

    MakeText(leaderPanel, "全 球 排 行 榜", 28, 1.0, 0.75, 0.25, 1, HA_CENTER, VA_TOP, 0, 24)
    MakeText(leaderPanel, "名次   玩家            得分",
             15, 0.55, 0.70, 0.90, 0.7, HA_LEFT, VA_TOP, 14, 64)
    MakeText(leaderPanel, "────────────────────",
             14, 0.3, 0.5, 0.8, 0.4, HA_LEFT, VA_TOP, 14, 84)

    leaderEntries = {}
    FetchAndShowLeaderboard(leaderPanel, S.score)

    S.gameOverRoot = gameOverRoot
end

function M.HideGameOver()
    if gameOverRoot then
        gameOverRoot:Remove()
        gameOverRoot  = nil
        leaderPanel   = nil
        leaderEntries = {}
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
    U.LogInfo("[UI] 初始化完毕（开始界面已显示）")
end

function M.StartGame()
    -- 隐藏开始界面，显示 HUD
    if startRoot then
        startRoot:SetVisible(false)
    end
    if hudRoot then
        hudRoot:SetVisible(true)
    end
    if S.hintText then
        S.hintText:SetVisible(true)
        S.hintText:SetOpacity(1.0)
    end
end

function M.Update(dt)
    if S.scoreText then S.scoreText:SetText("得分: " .. S.score) end
    if S.coinText  then S.coinText:SetText("金币: " .. S.coinCount) end
    if S.speedText then S.speedText:SetText(math.floor(S.speed * 3.6) .. " km/h") end

    -- 开始界面按钮闪烁
    if S.gameState == "menu" and S.startPrompt then
        local t   = math.fmod(time:GetElapsedTime(), 1.6)
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
