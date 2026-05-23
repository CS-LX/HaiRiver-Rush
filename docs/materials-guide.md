# HaiRiver Rush — 材质使用指南

> 记录项目中可用的引擎材质资源，以及各游戏元素的材质优化建议。

---

## 一、引擎程序化材质（无贴图）

纯色/无贴图材质只能使用以下三种 Technique，**不要猜测其他路径**：

| 效果 | Technique 路径 | 适用场景 |
|------|---------------|---------|
| 不透明 PBR（默认首选） | `Techniques/PBR/PBRNoTexture.xml` | 船体、障碍物、岸边墙壁 |
| 透明 PBR | `Techniques/PBR/PBRNoTextureAlpha.xml` | 玻璃、冰晶、半透效果 |
| 无光照（卡通风） | `Techniques/NoTextureUnlit.xml` | HUD 贴片、卡通物件 |

**标准用法：**
```lua
local mat = Material:new()
mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, 1.0)))
mat:SetShaderParameter("Metallic",     Variant(0.0))   -- 0=非金属, 1=金属
mat:SetShaderParameter("Roughness",    Variant(0.5))   -- 0=光滑, 1=粗糙
```

### 常用效果参数组合

| 材质效果 | Metallic | Roughness |
|---------|----------|-----------|
| 光滑金属（船舱镜面） | 0.9 | 0.15 |
| 磨砂金属（引擎盖） | 0.8 | 0.55 |
| 光滑塑料（船体漆面） | 0.0 | 0.35 |
| 橡胶/哑光 | 0.0 | 0.85 |
| 自发光（金币） | 0.0 | 0.3，加 MatEmissiveColor |

---

## 二、引擎内置水面材质

```lua
local mat = cache:GetResource("Material", "Materials/SingleLayerWater.xml")
mat:SetShaderParameter("WaterTint", Variant(Color(0.08, 0.38, 0.72)))  -- 仅 RGB
```

- 波纹动画由引擎着色器自动驱动，无需每帧 Update
- 当前项目 `water.lua` 已使用此材质，缩放 2000×2000 m 覆盖整圈赛道
- `WaterTint` 可调节水体颜色（深蓝 → 浅绿等）

---

## 三、预制纹理材质库（UUID 路径）

用法：`cache:GetResource("Material", "uuid://xxx")`

### 地面类

| 名称 | UUID | 适用场景 |
|------|------|---------|
| 方块地砖 BlockFlooring01 | `uuid://Hw7_CePj4QdSOcXIloCyqlTu` | 码头地板、休息区 |
| 石板铺装 StonePaving01 | `uuid://GSN7IaGGBlvP2Xk_zX9UQyuq` | 岸边广场、赛道边 |
| 城市人行道 UrbanSidewalk01 | `uuid://DKmYSWaMUJO6PDtihBbjHUQj` | 赛道护堤顶面 |
| 草地 Grass01 | `uuid://EFSiAWPsKtpGQpTAGBbflyyK` | 岸边草坡、绿化带 |

### 墙面/建筑类

| 名称 | UUID | 适用场景 |
|------|------|---------|
| 红砖墙 BrickWall01 | `uuid://DXjwQX_lcF60zC4F9y9yAyG_` | 两岸建筑外墙 |
| 混凝土 Concrete01 | `uuid://Gm0CwVtSclGB7uj0Zs_eP8Gs` | 赛道护堤侧面 |
| 混凝土变体 Concrete02 | `uuid://GMR70cPvbaF6F8SvtDto--G_` | 护堤侧面 |
| 石膏墙面 Plaster01 | `uuid://DSu7mcyfcXMfcpmHSWtv4KUm` | 建筑内墙 |

### 石材类

| 名称 | UUID | 适用场景 |
|------|------|---------|
| 岩石 Stone01 | `uuid://Hg04wSbDi8KsIwqNpUJ0OiwN` | 礁石、障碍物 |
| 岩石变体A Stone02 | `uuid://Cv_0id_Hb5MomJLKxjp_8o-Z` | 景观石 |
| 大理石 Marble01 | `uuid://HndW0W0ASO7zyBNhRXFeCwdL` | 高档码头 |

### 金属类

| 名称 | UUID | 适用场景 |
|------|------|---------|
| 金属-抛光 Metal01 | `uuid://D9QYQXRhlgGnRlDw8jDNGTya` | 船舱、引擎外壳 |
| 金属-拉丝 Metal02 | `uuid://Cis1sX30rhdTXVgC4QEwquGW` | 船体金属部件 |
| 金属-做旧 Metal03 | `uuid://FZIHOeDP_05jbHvpVhZaH2n9` | 废弃障碍物、铁桩 |

### 木材类

| 名称 | UUID | 适用场景 |
|------|------|---------|
| 木材 Wood01 | `uuid://DdH4-Su6Cppk8qaKI2AiCLs-` | 木船桨、码头木板 |
| 木栅栏 WoodenFence01 | `uuid://DoyqwWBUuF1yLRwH3fXFZYdV` | 岸边围栏 |
| 拼花木地板 WoodParquet01 | `uuid://G43HiRFgrh9VScIcXnDO4xGs` | 码头地板 |

### 特殊类

| 名称 | UUID | 适用场景 |
|------|------|---------|
| 玻璃 Glass01 | `uuid://Ex1LOem8FjFM7P9QTfyGjOTn` | 船舱窗户、透明护栏 |
| 橡胶 Rubber01 | `uuid://AkBCiS2MNfpI1vQqS6idJev_` | 浮标底部 |
| 喷漆表面 SprayPainted01 | `uuid://BeeVGafEvOlO71Gx7t73Uf16` | 船体光泽漆 |
| 碳纤维 CarbonFiber01 | `uuid://CvRSGW0wN84mcboHjqgVj7m3` | 赛艇科技感部件 |

---

## 四、当前项目材质现状

### 存在问题：`utils.lua` 的 `MakeMaterial` 缺少 `SetTechnique`

`scripts/utils.lua` 的 `MakeMaterial` 函数**没有调用 `SetTechnique`**，导致材质无法选择着色器，渲染结果为黑色/无效材质：

```lua
-- ❌ 当前代码（缺少 SetTechnique）
function M.MakeMaterial(r, g, b, a)
    local mat = Material.new()
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, a)))
    -- ⚠️ 缺少 SetTechnique，着色器无效！
    return mat
end
```

**受影响文件：**
| 文件 | 用途 | 颜色 |
|------|------|------|
| `boat.lua` | 船体（红色）、船头（红色）、船舱（蓝色）、引擎（深灰） | 无效材质 |
| `gameboat.lua` | 船体（蓝色）、甲板（米白） | 无效材质 |
| `track.lua` | 左右岸墙（草绿） | 无效材质 |

**未受影响（已正确使用 PBRNoTexture）：**
- `coins.lua` — 金币材质（金黄色 + 发光）✅
- `obstacles.lua` — 浮标材质（红/绿）✅
- `water.lua` — 内置水面材质 ✅

---

## 五、材质升级计划

### 优先级 1：修复 `utils.lua` MakeMaterial（必须）

```lua
-- ✅ 修复后的 MakeMaterial
function M.MakeMaterial(r, g, b, a, metallic, roughness)
    a = a or 1.0
    metallic = metallic or 0.0
    roughness = roughness or 0.5
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, a)))
    mat:SetShaderParameter("Metallic",     Variant(metallic))
    mat:SetShaderParameter("Roughness",    Variant(roughness))
    return mat
end
```

### 优先级 2：船体使用预制纹理材质（增强质感）

| 船体部件 | 当前 | 建议升级到 |
|---------|------|----------|
| 船体外壳 | 程序红色 PBR | `SprayPainted01`（喷漆光泽） 或保留程序化加大 Metallic |
| 船舱 | 程序蓝色 PBR | 程序化蓝色，`Metallic=0.7, Roughness=0.2`（金属感）|
| 引擎外壳 | 程序深灰 PBR | `Metal01`（抛光金属）或 `Metal02`（拉丝金属） |

### 优先级 3：赛道护堤使用预制材质（增强真实感）

| 赛道元素 | 建议材质 |
|---------|---------|
| 护堤侧面 | `Concrete01` 或 `Concrete02` |
| 护堤顶面 | `UrbanSidewalk01` 或 `Grass01` |
| 障碍铁桩 | `Metal03`（做旧金属） |

### 优先级 4：浮标使用橡胶材质

```lua
-- obstacles.lua 中浮标可加橡胶质感
local rubberMat = cache:GetResource("Material", "uuid://AkBCiS2MNfpI1vQqS6idJev_")
```

---

## 六、快速参考

```lua
-- 最小正确用法（程序化不透明材质）
local function MakePBR(r, g, b, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, 1.0)))
    mat:SetShaderParameter("Metallic",     Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness",    Variant(roughness or 0.5))
    return mat
end

-- 预制纹理材质
local concreteMat = cache:GetResource("Material", "uuid://Gm0CwVtSclGB7uj0Zs_eP8Gs")

-- 内置水面
local waterMat = cache:GetResource("Material", "Materials/SingleLayerWater.xml")
waterMat:SetShaderParameter("WaterTint", Variant(Color(0.08, 0.38, 0.72)))
```
