-- PBZ HitFeel: in-game tuning panel (Ctrl+F5), drawn in the user's steel-and-silver design (ui/*.png from their
-- PBZHitFeel_Steel_UI_Assets v1): a header with the language list and the master switch, feel presets (Vanilla / Subtle /
-- Intense / Custom), five tabs of rows with a description and a control each, a timed try of vanilla, and "reset this
-- page". Its text is in Chinese, English, Japanese or Korean (hf_lang, where the Chinese is the source), picked in the
-- header's list or following the game's own language.
-- Built from Lua: UserWidget + WidgetTree (outer: the player controller) + CanvasPanels of Images, TextBlocks and
-- transparent Buttons. The textures are the PNGs imported at runtime (KismetRenderingLibrary:ImportFileAsTexture2D)
-- and held by the images' brushes; a missing one falls back to a plain colored box. Built once per controller (a new
-- level means a new widget; the old one is never touched again), at map load by the preloader in small steps over a
-- few dozen frames (in one frame it took about 130 ms, a hitch just after loading), then only shown, collapsed and
-- refilled.
-- Used with the mouse: Ctrl+F5 opens it and shows the cursor. Every control is a transparent Button whose IsHovered
-- / IsPressed the panel reads each frame (no delegates from Lua; only the one under the mouse and one held down are
-- asked), and a full-screen one under the panel takes the clicks beside it, so no click reaches the game. Keys still
-- reach the player controller ("game and UI" input): the hotkey poller reads Ctrl+F5 there (and Esc, unless
-- Hud.EscCloses is off) to close it, and the panel reads the wheel; the character is held still meanwhile. Not "UI
-- only": then no key reaches the controller, and a widget built from Lua has no key events to hook
-- (UserWidget:OnKeyDown has no Blueprint code, so the engine never runs it and UE4SS never sees it).
-- Every change applies at once and is saved to tuning.lua, except the master switch: like Ctrl+F7 it lasts one
-- session.
local HUD = { name = "hud" }
local S, U, C
local Lang = require("hf_lang")
local tr, trf = Lang.t, Lang.f
-- Panel state lives in S.hudState, so a Ctrl+F8 reload of this file keeps the built widget.
local st
local dropBuild -- (below, with the building code)

-- { label, description, config path, kind, step / choices, min, max }; "fx" rows are the hit effect's own settings
-- (slash_tuning.lua), "fxchoice" the effect itself. The texts are hf_lang keys.
HUD.TABS = {
  { title = "常用", sections = {
    { title = "核心反馈", note = "即时生效", items = {
      { "命中定格", "短暂停顿，强化命中重量", "Freeze.Enabled", "bool" },
      { "受击抖动", "被打的敌人横着抖几下", "React.Shake.Enabled", "bool" },
      { "命中闪光", "命中瞬间轮廓闪一下黑红光", "Flash.Enabled", "bool" },
      { "命中特效", "砍中的位置出一道刀光", "Vfx.Slash.Enabled", "bool" },
      { "节奏", "连击轻重有别，重击和收尾加重", "Rhythm.Enabled", "bool" },
      { "击杀强调", "被打死的那一下额外加重", "Kill.Enabled", "bool" },
    } },
    { title = "镜头与震动", items = {
      { "镜头反馈", "调整命中时的镜头响应", "Camera.Enabled", "bool" },
      { "画面冲击", "重音时画面四周暗一下", "Screen.Enabled", "bool" },
      { "手柄震动", "通过震动传递命中反馈", "Rumble.Enabled", "bool" },
    } },
    { title = "格挡与挨打", items = {
      { "格挡反馈", "拼刀时的定格、火花和声音", "Deflect.Enabled", "bool" },
      { "挨打反馈", "被打中时镜头震退、身体推开", "Receive.Enabled", "bool" },
      { "破防提示", "破防时画面边缘暗红一闪、镜头踉跄、重震", "Guard.Break.Enabled", "bool" },
      { "杀气见底提示", "杀气越少画面边缘越红，快空时像心跳", "Guard.Low.Enabled", "bool" },
    } },
  } },
  { title = "动作", sections = {
    { title = "定格", items = {
      { "定格时长", "命中时敌人停多久", "Tuning.Freeze", "num", 0.1, 0, 3 },
      { "定格深度", "停住时敌人还剩多少速度，越小越静止", "Freeze.Scale", "num", 0.01, 0.01, 0.5 },
      { "击退时也延长定格", "带击退的重击也加长定格", "Freeze.ExtendKnockback", "bool" },
      { "霸体不加定格", "敌人霸体没被打断时保持原版", "Freeze.EndureGuard", "bool" },
      { "每秒额外定格", "同一敌人每秒最多多停几帧，0 = 不限", "Freeze.MaxExtraFramesPerSec", "num", 1, 0, 30 },
      { "节奏对比", "0 = 每下一样，2 = 轻重对比加倍", "Tuning.Rhythm", "num", 0.1, 0, 2 },
      { "密集减弱", "命中越密每下越轻，0 = 关", "Rhythm.Fatigue", "num", 0.05, 0, 1 },
    } },
    { title = "受击反应", items = {
      { "受击抖动幅度", "敌人横向抖动的幅度", "Tuning.HitShake", "num", 0.1, 0, 3 },
      { "模型推开", "敌人被推开几厘米再弹回", "React.Displace.Enabled", "bool" },
      { "推开距离", "模型推开的距离", "Tuning.Push", "num", 0.1, 0, 3 },
      { "闪光浓度", "越小越淡", "Tuning.Flash", "num", 0.1, 0, 3 },
    } },
    { title = "击退", items = {
      { "击退缓出", "击退先快后慢，距离不变", "Knockback.Enabled", "bool" },
      { "击退起速", "开头比原版快多少", "Knockback.StartSpeed", "num", 0.1, 1, 2 },
    } },
  } },
  { title = "镜头", sections = {
    { title = "镜头", items = {
      { "轻击补震动", "原版不震的轻击补一下", "Camera.FillEmptyShake", "bool" },
      { "额外震动", "叠在原版之上的镜头震动", "Tuning.Shake", "num", 0.1, 0, 3 },
      { "推近甩动", "命中时镜头推近、甩动", "Tuning.Punch", "num", 0.1, 0, 3 },
      { "挨打震退", "被打中时镜头震退和身体推开", "Tuning.Receive", "num", 0.1, 0, 3 },
      { "画面冲击强度", "画面四周变暗的程度", "Tuning.Screen", "num", 0.1, 0, 3 },
      { "画面冲击间隔", "两次之间至少隔多少毫秒", "Screen.MinGapMs", "num", 100, 0, 3000 },
      { "杀气提示强度", "暗红边缘的浓度和破防时的震动", "Tuning.Guard", "num", 0.1, 0, 3 },
    } },
    { title = "命中特效", note = "Ctrl+F6 也可以换", items = {
      { "特效", nil, nil, "fxchoice" },
      { "轻重档", "按力度换文件的特效，整体调轻或调重几档", nil, "fx", 1, -4, 4, key = "Step" },
      { "缩放", "火花、闪光这类粒子特效基本不随它变", nil, "fx", 0.05, 0.05, 5, key = "Scale" },
      { "画面内角度", "整个特效在屏幕上转", nil, "fx", 15, -180, 180, key = "Angle" },
      { "绕挥刀方向转", "看起来是一条细线时调这个", nil, "fx", 15, -180, 180, key = "Roll" },
      { "俯仰", "特效前后倾斜", nil, "fx", 15, -180, 180, key = "Pitch" },
      { "染成黑红", "特效有颜色参数才染得上，见上一行", "Vfx.Tint.Enabled", "bool" },
      { "挥刀空气轨迹", "每次挥刀，刀上都带一道空气轨迹", "Vfx.SwingTrail.Enabled", "bool" },
      { "刀上命中轨迹", "命中时刀上额外加一道轨迹", "Vfx.AirTrail.Enabled", "bool" },
      { "额外冲击特效", "游戏给不出血敌人用的冲击特效", "Vfx.HitVfx.Enabled", "bool" },
    } },
  } },
  { title = "声效", sections = {
    { title = "声音", items = {
      { "音乐让路", "命中瞬间压低战斗音乐", "Audio.Enabled", "bool" },
      { "音乐压低", "压低多少分贝", "Audio.DuckDb", "num", 1, 0, 20 },
      { "双持低频", "双持补一层单手刀命中声", "DualLayer.Enabled", "bool" },
      { "格挡音效", "格挡时叠一层拼刀声", "Deflect.SoundEnabled", "bool" },
      { "格挡音效音量", "叠上去那层的音量，1 = 原样", "Deflect.SoundVolume", "num", 0.1, 0, 1 },
    } },
    { title = "振动", items = {
      { "振动强度", "手柄振动的整体倍率", "Rumble.Scale", "num", 0.1, 0, 2 },
    } },
  } },
  { title = "高级", sections = {
    { title = "格挡", items = {
      { "精准判定", "哪些格挡按精准给反馈", "Deflect.Classify", "choice", { "game", "mult", "all_perfect", "all_guard" },
        names = { "游戏判定", "看倍率", "都算精准", "都算普通" } },
      { "精准倍率线", "看倍率时：拼刀慢放低于这个算精准", "Deflect.PerfectBelowMult", "num", 0.05, 0, 1 },
      { "格挡停敌人", "格挡时敌人停多久", "Tuning.DeflectFreeze", "num", 0.1, 0, 3 },
      { "格挡停自己", "格挡时你自己停多久", "Tuning.PlayerDeflectFreeze", "num", 0.1, 0, 3 },
      { "被挡下反馈", "你的攻击被挡下时也有反馈", "Deflect.OnEnemyDeflect", "bool" },
      { "精准格挡火花", "火花份数，0.5 = 只放第一层", "Deflect.SparkAmount.Perfect", "num", 0.5, 0, 4 },
      { "普通格挡火花", "火花份数，1.5 = 第一层两份", "Deflect.SparkAmount.Guard", "num", 0.5, 0, 4 },
      { "拼刀火花份数", "所有拼刀火花的份数倍率", "Tuning.Sparks", "num", 0.5, 0, 3 },
    } },
    -- Hit Feel: PBZHitFeel's Updates section (check Nexus, download page, install, rollback) is removed: it
    -- installed the original PBZHitFeel over this folder. Ctrl+F8 still reloads the scripts.
    { title = "状态", status = true },
  } },
}

-- Feel presets. Picking one sets every key it names (a key it leaves out goes back to config.lua) and keeps the
-- custom set it replaces in tuning_custom.lua, which Custom brings back. Changing any of these keys by hand makes the
-- current set Custom again. The names are what tuning.lua keeps (Hud.Preset) and hf_lang keys.
local TOGGLES = { "Freeze.Enabled", "React.Shake.Enabled", "React.Displace.Enabled",
  "Flash.Enabled", "Camera.Enabled", "Camera.FillEmptyShake", "Screen.Enabled", "Rhythm.Enabled", "Vfx.Slash.Enabled",
  "Vfx.AirTrail.Enabled", "Vfx.SwingTrail.Enabled", "Vfx.HitVfx.Enabled", "Rumble.Enabled", "Audio.Enabled", "DualLayer.Enabled",
  "Deflect.Enabled", "Receive.Enabled", "Knockback.Enabled", "Kill.Enabled", "Guard.Break.Enabled", "Guard.Low.Enabled" }
local SCALES = { "Tuning.Freeze", "Tuning.HitShake", "Tuning.Push", "Tuning.Flash", "Tuning.Shake",
  "Tuning.Punch", "Tuning.Screen", "Tuning.Receive", "Tuning.Sparks", "Tuning.Rhythm", "Rumble.Scale", "Tuning.Guard" }
HUD.PRESET_KEYS, HUD.IS_PRESET_KEY = {}, {}
for _, k in ipairs(TOGGLES) do HUD.PRESET_KEYS[#HUD.PRESET_KEYS + 1] = k end
for _, k in ipairs(SCALES) do HUD.PRESET_KEYS[#HUD.PRESET_KEYS + 1] = k end
for _, k in ipairs(HUD.PRESET_KEYS) do HUD.IS_PRESET_KEY[k] = true end
local VANILLA = {}
for _, k in ipairs(TOGGLES) do VANILLA[k] = false end
HUD.PRESETS = {
  { name = "原版", values = VANILLA },
  { name = "克制", values = { ["Vfx.AirTrail.Enabled"] = false, ["Vfx.SwingTrail.Enabled"] = false,
    ["Vfx.HitVfx.Enabled"] = false, ["Tuning.Freeze"] = 0.7, ["Tuning.HitShake"] = 0.7, ["Tuning.Push"] = 0.6,
    ["Tuning.Flash"] = 0.6, ["Tuning.Shake"] = 0.6, ["Tuning.Punch"] = 0.6, ["Tuning.Screen"] = 0.6,
    ["Tuning.Receive"] = 0.7, ["Rumble.Scale"] = 0.7, ["Tuning.Guard"] = 0.7 } },
  { name = "劲烈", values = { ["Vfx.AirTrail.Enabled"] = true, ["Vfx.SwingTrail.Enabled"] = true, ["Tuning.Freeze"] = 1.3, ["Tuning.HitShake"] = 1.4,
    ["Tuning.Push"] = 1.3, ["Tuning.Flash"] = 1.4, ["Tuning.Shake"] = 1.4, ["Tuning.Punch"] = 1.4, ["Tuning.Screen"] = 1.4,
    ["Tuning.Receive"] = 1.3, ["Tuning.Sparks"] = 1.5, ["Tuning.Rhythm"] = 1.3, ["Rumble.Scale"] = 1.2, ["Tuning.Guard"] = 1.3 } },
  { name = "自定义", custom = true },
}
HUD.CUSTOM_FILE = "tuning_custom.lua"

function HUD.init(state)
  S, U, C = state, state.U, state.C
  S.hudState = S.hudState or { page = 1, shown = false, last = {}, scroll = 1, cache = {} }
  st = S.hudState
  st.cache, st.active, st.pressedPrev, st.repeatAt = st.cache or {}, st.active or {}, st.pressedPrev or {}, st.repeatAt or {}
  HUD.overrides = C.loadTuning(U)
  -- A build a reload cut short belongs to the old code: dropped, and the next use builds afresh.
  if st.building then dropBuild(st.building) end
  HUD.applyLanguage(false)
end

-- ------------------------------------------------------------------ theme (docs/theme.json of the design)

-- sRGB hex to the linear color UMG takes.
local function hex(s, a)
  local function lin(i)
    local c = tonumber(s:sub(i, i + 1), 16) / 255
    return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return { R = lin(2), G = lin(4), B = lin(6), A = a or 1 }
end
local COL = {
  text = hex("#E6E2D8"), dim = hex("#A5A39C"), border = hex("#969A98"), sel = hex("#580F18"), focus = hex("#D3D0C6"),
  accent = hex("#9A2230"), key = hex("#1C1C1C"), line = hex("#969A98", 0.35), hl = { R = 1, G = 1, B = 1, A = 0.06 },
  -- Fallbacks for a texture that did not load.
  panel = { R = 0.006, G = 0.006, B = 0.007, A = 0.92 }, button = { R = 0.03, G = 0.03, B = 0.03, A = 0.95 },
}

-- Panel layout in 1080p units: the panel is 520 x 800 at Hud.X/Hud.Y. Rows: items 50 high, section headers 34,
-- status lines 24, in the content area from y 198 to 650.
local L = { W = 520, H = 800, contentY = 198, contentH = 452, itemH = 50, headH = 34, statusH = 24, slots = 14 }

-- How far (Lang.width units) a row's two lines may run before they meet its control: a switch, a number's reset mark,
-- a choice's arrow. Titles are 13 pt, descriptions 10 pt.
HUD.FIT = { title = { bool = 41, num = 34, choice = 27 }, desc = { bool = 52, num = 44, choice = 34 } }

-- Nine-slice margins (fractions of the texture) and nominal sizes from docs/assets.json (2x margins / 2x pixels).
-- DrawAs 1 is ESlateBrushDrawType::Box (sides and middle stretch); 2 would be Border, which leaves the middle empty
-- (v0.5.8's see-through panel and hollow preset buttons). Slate makes a nine-slice's edges as wide as the margin's
-- share of the texture's own pixels (ImageSize plays no part), and these textures are 2x: drawn at twice the size
-- and scaled by `scale`, the edges come out at the designed size and stay sharp on large screens. v0.6.0 drew them
-- at 1x, with doubled edges: squashed buttons, and the panel's corner bevel across the title icon.
local BOX = {
  panel = { margin = { Left = 48 / 960, Top = 48 / 1440, Right = 48 / 960, Bottom = 48 / 1440 }, size = { X = 480, Y = 720 },
    scale = 0.5 },
  button = { margin = { Left = 40 / 336, Top = 16 / 96, Right = 40 / 336, Bottom = 16 / 96 }, size = { X = 168, Y = 48 },
    scale = 0.5 },
}
local DRAW_BOX = 1

HUD.TEXTURES = { "panel_full", "button_normal", "button_hover", "button_selected", "checkbox_on", "checkbox_off",
  "checkbox_hover_on", "checkbox_hover_off", "icon_swords", "icon_close", "icon_diamond", "icon_chevron_left",
  "icon_chevron_right", "icon_chevron_up", "icon_chevron_down", "divider", "keycap", "icon_reset" }
-- Imported the first time the panel opens instead of at map load: the 960 x 1440 background alone took 79 ms of one
-- frame in game, and only the open panel shows it.
HUD.LATE = { panel_full = true }
HUD.IMPORT = "/Script/Engine.KismetRenderingLibrary:ImportFileAsTexture2D"
HUD.WBL = "/Script/UMG.Default__WidgetBlueprintLibrary"
HUD.GAME_UI = "/Script/UMG.WidgetBlueprintLibrary:SetInputMode_GameAndUIEx"
HUD.GAME_ONLY = "/Script/UMG.WidgetBlueprintLibrary:SetInputMode_GameOnly"
HUD.GPS = "/Script/Engine.Default__GameplayStatics"
HUD.I18N = "/Script/Engine.Default__KismetInternationalizationLibrary"

-- Visibility: 0 visible (hit-testable), 1 collapsed, 3 visible but not hit-testable, 4 only the children hit-testable.
local VIS, GONE, SHOWN, PASS = 0, 1, 3, 4

-- ------------------------------------------------------------------ language

-- The game's own language ("zh-Hans", "en", ...), nil when it cannot be read.
local function gameCulture()
  local lib = U.cdo(HUD.I18N)
  if not lib then return nil end
  for _, fn in ipairs({ "GetCurrentLanguage", "GetCurrentCulture" }) do
    local s = U.try("hud.language", function()
      local v = lib[fn](lib)
      if v ~= nil and type(v) ~= "string" then v = v:ToString() end
      return v
    end)
    if type(s) == "string" and s ~= "" then return s end
  end
  return nil
end

-- The panel's language: Hud.Language as config.lua or the panel's list set it; "auto" (or anything not in the list)
-- follows the game's language, English when that cannot be read. The game is asked (`detect`) on the game thread
-- only: at map load and each time the panel opens; loading the scripts uses what was read last.
function HUD.applyLanguage(detect)
  local want = tostring((S.cfg.Hud or {}).Language or "auto")
  if not Lang.known(want) then
    if detect then
      local culture = gameCulture()
      if (culture or "?") ~= st.cultureSeen then
        st.cultureSeen, st.culture = culture or "?", culture
        U.log("hud: the game's language is %s, so the panel is in %s", tostring(culture),
          Lang.name(culture and Lang.fromCulture(culture) or "en"))
      end
    end
    want = st.culture and Lang.fromCulture(st.culture) or "en"
  end
  Lang.code = want
  return want
end

function HUD.language() return Lang.code end

-- A language picked in the panel's list: applied at once and kept in tuning.lua (Hud.Language).
function HUD.setLanguage(code)
  if not Lang.known(code) then return end
  HUD.overrides["Hud.Language"] = code
  C.setPath(S.cfg, "Hud.Language", code)
  local ok = C.saveTuning(U, HUD.overrides)
  HUD.applyLanguage(false)
  st.note = ok and trf("语言：%s", Lang.name(code)) or tr("保存失败")
  U.log("hud: language %s", code)
end

-- Esc closes the panel too, unless Hud.EscCloses is off; Ctrl+F5 always does.
local function escCloses() return (S.cfg.Hud or {}).EscCloses ~= false end
HUD.escCloses = escCloses

-- ------------------------------------------------------------------ widget building

-- The panel's widget layout. A panel kept over a Ctrl+F8 reload from code with another layout is built again.
local LAYOUT = 2

local B -- the build in progress (see plan)
local giveInput -- (below, with the other input code)

local function construct(clsName, outer, name)
  local cls = B and B.classes[clsName]
  if not cls then
    cls = StaticFindObject("/Script/UMG." .. clsName)
    if not U.valid(cls) then error("UMG class not found: " .. clsName) end
    if B then B.classes[clsName] = cls end
  end
  local o = name and StaticConstructObject(cls, outer, name) or StaticConstructObject(cls, outer)
  if not U.valid(o) then error("could not construct " .. clsName) end
  return o
end

local function place(canvas, w, x, y, wd, ht)
  local slot = canvas:AddChildToCanvas(w)
  pcall(function() slot:SetAutoSize(false) end)
  pcall(function() slot:SetPosition({ X = x, Y = y }) end)
  pcall(function() slot:SetSize({ X = wd, Y = ht }) end)
  return slot
end

-- One PNG, imported in the step that also holds it (an unreferenced object may be collected by the next frame).
local function importTexture(pc, n)
  local lib = U.cdo("/Script/Engine.Default__KismetRenderingLibrary")
  local tex = lib and U.try("hud.texture", U.callNamed, lib, HUD.IMPORT,
    { WorldContextObject = pc, Filename = U.root .. "/ui/" .. n .. ".png" })
  return U.valid(tex) and tex or nil
end

local function setTex(img, name, fallback)
  local tex = name and B.tex[name]
  if tex and U.valid(tex) then
    pcall(function() img:SetBrushFromTexture(tex, false) end)
    return true
  end
  if fallback then pcall(function() img:SetColorAndOpacity(fallback) end) end
  return false
end

-- A textured image as a nine-slice box: the brush's margins, then (box.scale) drawn at 1/scale of its place and
-- scaled back about its top-left corner. Returns the factor its slot is sized by (1 when the scale did not take).
local function boxBrush(img, box)
  pcall(function()
    local b = img.Brush
    b.DrawAs = DRAW_BOX
    b.Margin = box.margin
    b.ImageSize = box.size
    img:SetBrush(b)
  end)
  if not box.scale or box.scale == 1 then return 1 end
  local ok = pcall(function()
    img:SetRenderTransformPivot({ X = 0, Y = 0 })
    img:SetRenderScale({ X = box.scale, Y = box.scale })
  end)
  return ok and 1 / box.scale or 1
end

-- An image of texture `name` (nil: a plain box in `color`), a nine-slice box when `box` is given. `color` tints a
-- texture; `fallback` colors the box when the texture did not load. Never hit-testable.
local function image(canvas, name, x, y, w, h, color, box, fallback)
  local img = construct("Image", B.tree)
  local textured = setTex(img, name, fallback)
  local k = (textured and box) and boxBrush(img, box) or 1
  if color and (textured or not name) then pcall(function() img:SetColorAndOpacity(color) end) end
  pcall(function() img:SetVisibility((name and not textured and not fallback) and GONE or SHOWN) end)
  return img, place(canvas, img, x, y, w * k, h * k)
end

local function setColor(t, color)
  pcall(function() t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
end

-- Justification: 0 left, 1 center, 2 right. Never hit-testable.
local function text(canvas, s, x, y, w, h, size, color, just)
  local t = construct("TextBlock", B.tree)
  pcall(function()
    local f = t.Font
    f.Size = size
    t:SetFont(f)
  end)
  pcall(function() t:SetShadowOffset({ X = 1, Y = 1 }) end)
  pcall(function() t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.8 }) end)
  if just then pcall(function() t:SetJustification(just) end) end
  setColor(t, color)
  pcall(function() t:SetVisibility(SHOWN) end)
  t:SetText(FText(U.keys(s or "")))
  return t, place(canvas, t, x, y, w, h)
end

-- A text that follows the language: tr(key) now, and again on every render (cached: only a change of language
-- reaches the widget).
local function label(canvas, key, x, y, w, h, size, color, just)
  local t, slot = text(canvas, tr(key), x, y, w, h, size, color, just)
  B.w.static[#B.w.static + 1] = { t, key }
  return t, slot
end

local function canvas(parent, x, y, w, h)
  local c = construct("CanvasPanel", B.tree)
  pcall(function() c:SetVisibility(PASS) end)
  return c, place(parent, c, x, y, w, h)
end

-- A transparent button: the only hit-testable widgets of the panel. Its state is read each frame (IsHovered,
-- IsPressed) instead of binding its events.
local function hitArea(parent, id, x, y, w, h)
  local b = construct("Button", B.tree)
  pcall(function()
    local style = b.WidgetStyle
    for _, k in ipairs({ "Normal", "Hovered", "Pressed", "Disabled" }) do style[k].DrawAs = 0 end
    b:SetStyle(style)
  end)
  pcall(function() b:SetBackgroundColor({ R = 0, G = 0, B = 0, A = 0 }) end)
  -- Not focusable: a clicked button would keep the keyboard focus, and Space or Enter would press it again.
  pcall(function() b.IsFocusable = false end)
  local slot = place(parent, b, x, y, w, h)
  local e = { id = id, w = b, slot = slot }
  B.buttons[#B.buttons + 1] = e
  B.byId[id] = e
  return b, slot
end

-- One row slot: a section header, an item row or a status line, depending on what it shows.
local function buildSlot(panel, i)
  local s = {}
  s.canvas, s.slot = canvas(panel, 0, L.contentY, L.W, L.itemH)
  s.hl = image(s.canvas, nil, 18, 1, L.W - 36, L.itemH - 3, COL.hl)
  s.accent = image(s.canvas, nil, 18, 1, 3, L.itemH - 3, COL.accent)
  s.diamond = image(s.canvas, "icon_diamond", 26, 11, 12, 12, nil, nil, COL.border)
  s.head = text(s.canvas, "", 46, 5, 280, 24, 14, COL.text)
  s.headNote = text(s.canvas, "", 300, 9, L.W - 300 - 26, 20, 10, COL.dim, 2)
  s.title = text(s.canvas, "", 44, 4, 310, 22, 13, COL.text)
  s.desc = text(s.canvas, "", 44, 26, 330, 18, 10, COL.dim)
  s.check = image(s.canvas, "checkbox_off", 420, 9, 30, 30, nil, nil, COL.button)
  s.state = text(s.canvas, "", 456, 12, 40, 22, 13, COL.text)
  s.chevL, s.chevLSlot = image(s.canvas, "icon_chevron_left", 392, 14, 12, 20, COL.border)
  s.chevR = image(s.canvas, "icon_chevron_right", 478, 14, 12, 20, COL.border)
  s.value, s.valueSlot = text(s.canvas, "", 406, 12, 70, 22, 13, COL.text, 1)
  s.reset = image(s.canvas, "icon_reset", 352, 15, 18, 18, COL.border)
  s.line = image(s.canvas, "divider", 40, L.itemH - 2, L.W - 80, 2, COL.line, nil, COL.line)
  s.status = text(s.canvas, "", 30, 3, L.W - 56, 20, 11, COL.dim)
  -- Click areas: the whole row (a switch flips, a choice steps on), the arrows, and the row's reset mark.
  s.rowBtn = hitArea(s.canvas, "row:" .. i, 18, 1, L.W - 36, L.itemH - 3)
  s.decBtn, s.decSlot = hitArea(s.canvas, "dec:" .. i, 382, 4, 30, 42)
  s.incBtn = hitArea(s.canvas, "inc:" .. i, 468, 4, 30, 42)
  s.resetBtn = hitArea(s.canvas, "rowreset:" .. i, 346, 9, 30, 30)
  return s
end

-- The build as small steps (the empty widget, one texture, the header, one row slot, ...), so that the preloader can
-- run a few per frame. The first step puts the empty widget in the viewport, collapsed: from then on it keeps
-- everything added to it, each texture from the step that imports it. Draw order is build order, so the language
-- list, which opens over the presets and tabs, comes last on the panel.
local function plan(pc)
  local h = S.cfg.Hud or {}
  local w = { slots = {}, presetBtn = {}, presetTxt = {}, tabTxt = {}, static = {}, langHl = {}, langMark = {},
    langTxt = {}, layout = LAYOUT }
  local b = { pc = pc, owner = U.addr(pc), w = w, tex = {}, missing = {}, buttons = {}, byId = {}, classes = {},
    steps = {}, at = 0, frames = 0, work = 0, worst = 0 }
  local function add(fn) b.steps[#b.steps + 1] = fn end

  add(function()
    U.note("hud: building the panel")
    -- (Named, so that a later run of the scripts finds it if this one leaves it behind: hf_env.)
    local widget = construct("UserWidget", pc, S.env and S.env.widgetName("Panel"))
    local tree = construct("WidgetTree", widget)
    widget.WidgetTree = tree
    b.widget, b.tree = widget, tree
    pcall(function() widget:SetOwningPlayer(pc) end)
    local root = construct("CanvasPanel", tree)
    tree.RootWidget = root
    b.root = root
    pcall(function() root:SetVisibility(PASS) end)
    pcall(function() widget:SetIsFocusable(true) end)
    pcall(function() widget.bIsFocusable = true end)
    widget:AddToViewport(9999)
    widget:SetVisibility(GONE)
    -- Every texture stays in a collapsed image here: a Lua value does not keep an object alive, and the states shown
    -- later (hover, selected, on) are not on screen yet.
    b.keep = canvas(root, 0, 0, 1, 1)
    pcall(function() b.keep:SetVisibility(GONE) end)
  end)
  for _, n in ipairs(HUD.TEXTURES) do
    if not HUD.LATE[n] then add(function()
      local tex = importTexture(pc, n)
      if not tex then
        b.missing[#b.missing + 1] = n
        return
      end
      b.tex[n] = tex
      image(b.keep, n, 0, 0, 1, 1)
    end) end
  end

  add(function()
    -- Under the panel, a transparent button over the whole screen: a click beside the panel goes nowhere.
    w.blocker = hitArea(b.root, "outside", 0, 0, 1, 1)
    pcall(function()
      local slot = b.byId.outside.slot
      slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
      slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    end)
    pcall(function() w.blocker:SetVisibility(GONE) end)
    w.panel = canvas(b.root, h.X or 40, h.Y or 70, L.W, L.H)
    pcall(function() w.panel:SetVisibility(GONE) end)
    -- (Its texture comes with the first opening; a plain dark box until then.)
    w.panelBg, w.panelBgSlot = image(w.panel, "panel_full", 0, 0, L.W, L.H, nil, BOX.panel, COL.panel)
    -- A click on the panel's empty parts is the panel's too.
    hitArea(w.panel, "panel", 0, 0, L.W, L.H)
  end)

  add(function()
    -- Header: icon, title, version; the language list's button, the master switch and the close mark.
    local p = w.panel
    image(p, "icon_swords", 24, 18, 46, 46, nil, nil, nil)
    label(p, "打击反馈", 82, 14, 124, 34, 22, COL.text)
    w.version = text(p, "PBZHitFeel / " .. tostring(U.version), 84, 50, 124, 20, 10, COL.dim)
    -- (The button's bevelled ends take 20 px each: the name and the arrow sit in its flat middle.)
    w.langBtn = image(p, "button_normal", 204, 22, 104, 36, nil, BOX.button, COL.button)
    w.langName = text(p, "", 220, 30, 56, 20, 12, COL.text, 1)
    w.langChev = image(p, "icon_chevron_down", 277, 37, 11, 7, COL.border)
    hitArea(p, "lang", 204, 22, 104, 36)
    w.enabledHl = image(p, nil, 314, 20, 116, 40, COL.hl)
    w.enabledTxt = text(p, "", 316, 30, 70, 22, 12, COL.text, 2)
    w.enabledChk = image(p, "checkbox_on", 392, 24, 32, 32, nil, nil, COL.button)
    hitArea(p, "enabled", 314, 20, 116, 40)
    w.close = image(p, "icon_close", 446, 27, 26, 26, COL.border)
    hitArea(p, "close", 438, 19, 42, 42)
    image(p, "divider", 24, 84, L.W - 48, 2, COL.line, nil, COL.line)
  end)

  add(function()
    -- Presets.
    local p = w.panel
    w.presetLabel = label(p, "手感预设", 26, 112, 96, 24, 13, COL.text)
    for i, pr in ipairs(HUD.PRESETS) do
      local x = 122 + (i - 1) * 94
      w.presetBtn[i] = image(p, "button_normal", x, 102, 90, 40, nil, BOX.button, COL.button)
      w.presetTxt[i] = label(p, pr.name, x, 112, 90, 22, 13, COL.dim, 1)
      hitArea(p, "preset:" .. i, x, 102, 90, 40)
    end
    -- Tabs: the active one bright with a red underline and a diamond on it.
    local tw = (L.W - 48) / #HUD.TABS
    for i, t in ipairs(HUD.TABS) do
      w.tabTxt[i] = label(p, t.title, 24 + (i - 1) * tw, 158, tw, 26, 14, COL.dim, 1)
      hitArea(p, "tab:" .. i, 24 + (i - 1) * tw, 150, tw, 38)
    end
    w.tabLine, w.tabLineSlot = image(p, nil, 32, 186, tw - 16, 2, COL.accent)
    w.tabDiamond, w.tabDiamondSlot = image(p, "icon_diamond", 24 + tw / 2 - 5, 182, 10, 10, nil, nil, COL.border)
    image(p, "divider", 24, 189, L.W - 48, 2, COL.line, nil, COL.line)
  end)

  -- Rows, one slot a step.
  for i = 1, L.slots do add(function() w.slots[i] = buildSlot(w.panel, i) end) end

  add(function()
    local p = w.panel
    -- The arrows that scroll when there is more above or below (the wheel scrolls too).
    w.moreUp = image(p, "icon_chevron_up", L.W / 2 - 10, L.contentY - 2, 20, 12, COL.border)
    hitArea(p, "up", L.W / 2 - 40, L.contentY - 8, 80, 22)
    w.moreDown = image(p, "icon_chevron_down", L.W / 2 - 10, L.contentY + L.contentH + 1, 20, 12, COL.border)
    hitArea(p, "down", L.W / 2 - 40, L.contentY + L.contentH - 6, 80, 22)
    -- Try vanilla for a moment, the footer and the key bar.
    w.compareBtn = image(p, "button_normal", 54, 664, 216, 40, nil, BOX.button, COL.button)
    w.compareTxt = text(p, "", 54, 673, 216, 24, 13, COL.text, 1)
    hitArea(p, "compare", 54, 664, 216, 40)
    label(p, "点后关面板去打，到时自动恢复", 284, 676, 210, 20, 10, COL.dim)
    image(p, "divider", 24, 714, L.W - 48, 2, COL.line, nil, COL.line)
    image(p, "icon_diamond", 26, 728, 10, 10, nil, nil, COL.border)
    w.note = text(p, "", 44, 722, 300, 20, 11, COL.dim)
    w.resetHl = image(p, nil, 352, 718, 148, 28, COL.hl)
    w.resetTxt = label(p, "恢复本页默认", 356, 722, 138, 20, 11, COL.dim, 2)
    hitArea(p, "reset", 352, 716, 148, 30)
    image(p, "divider", 24, 750, L.W - 48, 2, COL.line, nil, COL.line)
    image(p, "keycap", 24, 760, 80, 28, nil, nil, COL.focus)
    w.keyCap = text(p, "Ctrl+F5", 24, 765, 80, 20, 10, COL.key, 1)
    w.keyHint = text(p, "", 112, 765, 150, 20, 11, COL.dim)
    label(p, "鼠标点击调整 · 滚轮翻动", 200, 765, L.W - 200 - 26, 20, 11, COL.dim, 2)
  end)

  add(function()
    -- The language list under its header button: a solid backing (the button texture is translucent), then one row
    -- per language, the one in use marked.
    local n, rowH, lw = #Lang.LIST, 30, 120
    local lh = 16 + n * rowH
    w.langList = canvas(w.panel, 204, 60, lw, lh)
    pcall(function() w.langList:SetVisibility(GONE) end)
    image(w.langList, nil, 2, 2, lw - 4, lh - 4, COL.panel)
    image(w.langList, "button_normal", 0, 0, lw, lh, nil, BOX.button, COL.button)
    for i, l in ipairs(Lang.LIST) do
      local y = 8 + (i - 1) * rowH
      w.langHl[i] = image(w.langList, nil, 4, y, lw - 8, rowH, COL.hl)
      w.langMark[i] = image(w.langList, "icon_diamond", 12, y + 10, 10, 10, nil, nil, COL.border)
      w.langTxt[i] = text(w.langList, l.name, 30, y + 5, lw - 38, 20, 12, COL.dim)
      hitArea(w.langList, "langopt:" .. i, 0, y, lw, rowH)
    end
  end)

  add(function()
    -- The notice shown while the panel is closed (Ctrl+F6 names the hit effect it switched to).
    w.toast = canvas(b.root, h.ToastX or 40, h.ToastY or 30, 460, 46)
    pcall(function() w.toast:SetVisibility(GONE) end)
    image(w.toast, "button_normal", 0, 0, 460, 46, nil, BOX.button, COL.button)
    w.toastTxt = text(w.toast, "", 14, 11, 432, 24, 12, COL.text, 1)
  end)

  add(function()
    w.buttons, w.byId, w.tree, w.keep = b.buttons, b.byId, b.tree, b.keep
    st.widget, st.w, st.owner, st.cache, st.textures = b.widget, w, b.owner, {}, b.tex
    -- Which font the text gets (the TextBlock default): if a language shows boxes in game, this says what to replace.
    if not st.fontLogged then
      st.fontLogged = true
      local font = U.try("hud.font", function() return w.version.Font.FontObject end)
      U.log("hud: text font %s", font and U.valid(font) and U.fullName(font) or "(not readable)")
    end
  end)
  return b
end

-- Runs the build's next steps: all of them, or (budgetMs) until that much time has gone by, one at least. True once
-- it is done.
local function runBuild(b, budgetMs)
  local t0 = os.clock()
  B = b
  local ok, err = pcall(function()
    repeat
      b.at = b.at + 1
      b.steps[b.at]()
    until b.at >= #b.steps or (budgetMs and (os.clock() - t0) * 1000 >= budgetMs)
  end)
  B = nil
  local dt = os.clock() - t0
  b.frames, b.work, b.worst = b.frames + 1, b.work + dt, math.max(b.worst, dt)
  if not ok then error(err, 0) end
  if b.at < #b.steps then return false end
  local n = 0
  for _ in pairs(b.tex) do n = n + 1 end
  local late = 0
  for _ in pairs(HUD.LATE) do late = late + 1 end
  U.log("hud: panel built (%d of %d textures, %d more when it first opens%s) over %d frame(s): %.0f ms of work, at most %.0f ms in one frame",
    n, #HUD.TEXTURES - late, late, #b.missing > 0 and ("; not loaded, plain boxes instead: " .. table.concat(b.missing, ", ")) or "",
    b.frames, b.work * 1000, b.worst * 1000)
  return true
end

-- A build that will not finish (the level changed, a reload, an error): its widget leaves the viewport.
dropBuild = function(b)
  if st.building == b then st.building = nil end
  if b.widget and U.valid(b.widget) then pcall(function() b.widget:RemoveFromParent() end) end
end

local function failBuild(b, err)
  dropBuild(b)
  U.log("hud: could not build the panel: %s", tostring(err))
  st.failed = (st.failed or 0) + 1
end

local function ready(pc)
  return st.widget ~= nil and st.owner == U.addr(pc) and U.valid(st.widget) and st.w ~= nil and st.w.layout == LAYOUT
    and U.valid(st.w.panel)
end

-- The widget for the current controller; what is left of a build is done here and now. A widget from an earlier
-- controller (level) is left alone: the engine has torn it down with its world.
local function widget()
  local pc = U.pc()
  if not pc then return nil end
  if ready(pc) then return st.widget end
  if st.shown then
    -- A new level while the panel was open: the old one went with its world. Input goes back to the game.
    st.shown, st.active = false, {}
    local inp = st.input
    st.input = nil
    if inp then giveInput(inp) end
  end
  -- A panel built by code with another layout (kept over a reload) makes way.
  if st.widget and st.owner == U.addr(pc) and U.valid(st.widget) then pcall(function() st.widget:RemoveFromParent() end) end
  st.widget, st.w = nil, nil
  local b = st.building
  if b and not (b.owner == U.addr(pc) and U.valid(b.pc)) then
    dropBuild(b)
    b = nil
  end
  b = b or plan(pc)
  st.building = nil
  local ok, err = pcall(runBuild, b, nil)
  if not ok then
    failBuild(b, err)
    return nil
  end
  return st.widget
end

-- The textures HUD.LATE keeps out of the build, imported when the panel first opens (held by the keeper in the frame
-- they are imported), and put on the panel's background.
local function lateTextures()
  local w = st.w
  if not w or w.lateDone then return end
  w.lateDone = true
  local pc = U.pc()
  if not pc then return end
  local t0 = os.clock()
  local tex = importTexture(pc, "panel_full")
  if not tex then
    U.log("hud: ui/panel_full.png did not load; the panel keeps a plain box")
    return
  end
  B = { tree = w.tree, tex = { panel_full = tex }, buttons = {}, byId = {}, classes = {}, w = w }
  local ok, err = pcall(function()
    image(w.keep, "panel_full", 0, 0, 1, 1)
    st.textures.panel_full = tex
    w.panelBg:SetBrushFromTexture(tex, false)
    local k = boxBrush(w.panelBg, BOX.panel)
    pcall(function() w.panelBgSlot:SetSize({ X = L.W * k, Y = L.H * k }) end)
    pcall(function() w.panelBg:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 1 }) end)
  end)
  B = nil
  U.log("hud: panel background %s (%.0f ms)", ok and "loaded" or ("failed: " .. tostring(err)), (os.clock() - t0) * 1000)
end

-- Built at map load by the preloader, hidden, a few steps a frame (Hud.BuildMsPerFrame), so that the first Ctrl+F5
-- opens at once and no frame after loading stalls on it. Ctrl+F5 or a notice before it is done finishes it then.
function HUD.prebuild()
  if not (S.cfg.Hud or {}).Enabled then return end
  HUD.applyLanguage(true)
  local pc = U.pc()
  -- (An open panel is handled where it is used: widget() builds what it needs.)
  if not pc or st.shown or ready(pc) then return end
  local old = st.building
  if old then
    if old.owner == U.addr(pc) and U.valid(old.pc) then return end
    dropBuild(old)
  end
  -- A panel built by code with another layout (kept over a reload) makes way.
  if st.widget and st.owner == U.addr(pc) and U.valid(st.widget) then pcall(function() st.widget:RemoveFromParent() end) end
  st.widget, st.w = nil, nil
  local b, me = plan(pc), HUD
  st.building = b
  local budget = tonumber((S.cfg.Hud or {}).BuildMsPerFrame) or 4
  U.everyFrame("hud.build", function()
    if st.building ~= b then return true end
    if S.hud ~= me or not U.valid(b.pc) then
      dropBuild(b)
      return true
    end
    local ok, done = pcall(runBuild, b, budget)
    if not ok then
      failBuild(b, done)
      return true
    end
    if done then st.building = nil end
    return done
  end)
end

-- ------------------------------------------------------------------ cached setters (render touches only what changed)

local function cached(w, key, v, fn)
  local c = st.cache[w]
  if not c then
    c = {}
    st.cache[w] = c
  end
  if c[key] == v then return end
  c[key] = v
  pcall(fn)
end

local function show(w, on, vis) cached(w, "vis", on and (vis or SHOWN) or GONE, function() w:SetVisibility(on and (vis or SHOWN) or GONE) end) end
-- (A text names the hotkeys in use: U.keys.)
local function setText(t, s)
  s = U.keys(s)
  cached(t, "text", s, function() t:SetText(FText(s)) end)
end
local function setTextColor(t, col, name) cached(t, "color", name, function() setColor(t, col) end) end
local function setImage(img, name)
  local tex = st.textures and st.textures[name]
  if not U.valid(tex) then return end
  cached(img, "tex", name, function() img:SetBrushResourceObject(tex) end)
end
local function tint(img, col, name) cached(img, "tint", name, function() img:SetColorAndOpacity(col) end) end
local function moveTo(slot, x, y, key) cached(slot, "pos", key, function() slot:SetPosition({ X = x, Y = y }) end) end
-- A click area: shown (and polled) or not.
local function area(id, on)
  local e = st.w.byId[id]
  if not e then return end
  st.active[id] = on or nil
  show(e.w, on, VIS)
end

-- ------------------------------------------------------------------ values

-- nil for the step of an effect that has one version only, and for an action row.
local function value(item)
  if item[4] == "action" then return nil end
  if item[4] == "fx" then
    if not S.vfx or (item.key == "Step" and not S.vfx.hasSteps()) then return nil end
    return S.vfx.fxGet(item.key)
  end
  if item[4] == "fxchoice" then return S.vfx and S.vfx.slashLabel() end
  return C.getPath(S.cfg, item[3])
end

-- A string cut to `units` of Lang.width (a CJK character 2, a Latin letter about 1), "…" included, so that a line
-- stays inside its place in any language.
local function clip(str, units)
  str = tostring(str or "")
  if Lang.width(str) <= units then return str end
  local out, used = {}, 0
  for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local wch = Lang.charWidth(ch)
    if used + wch > units - 2 then break end
    out[#out + 1] = ch
    used = used + wch
  end
  return table.concat(out) .. "…"
end

local function fmt(item, v)
  local kind = item[4]
  if kind == "action" then return S.update and S.update.label(item.run) or "" end
  if kind == "bool" then return tr(v and "开" or "关") end
  if kind == "fxchoice" then return tostring(v):match("^(%d+/%d+)") or tr("关") end
  if kind == "choice" then
    for i, c in ipairs(item[5] or {}) do
      if c == v and item.names and item.names[i] then return tr(item.names[i]) end
    end
    return tostring(v)
  end
  if item.key == "Step" then
    if type(v) ~= "number" then return "—" end
    if v == 0 then return "0" end
    return string.format("%+d", v)
  end
  if type(v) ~= "number" then return tostring(v) end
  local step = item[5] or 0.1
  if step >= 1 then return string.format("%d", math.floor(v + 0.5)) end
  if step >= 0.1 then return string.format("%.1f", v) end
  return string.format("%.2f", v)
end

-- The row's second line: its description, or what a one-version effect cannot do, or the effect's full name; an
-- action row's live state when it has one.
local function describe(item)
  if item[4] == "action" then
    local s = S.update and U.try("hud.update", S.update.status, item.run)
    if s then return s end
  end
  if item[4] == "fxchoice" then
    local p = S.vfx and S.vfx.slashPath()
    if not p then return tr("不加命中特效") end
    local name = (tostring(p):match("([^%./]+)$") or tostring(p)):gsub("^NS_", "")
    local sys = S.vfx.asset and S.vfx.asset(S.vfx.expand(p, "Middle"))
    -- (Whether it takes the tint is known once it has been spawned: Ctrl+F6's preview or a hit.)
    local can = sys and S.vfx.tintable and S.vfx.tintable(sys)
    return (sys and tr(can == true and "可染黑红 · " or (can == false and "不能染色 · " or "染色待确认 · ")) or "") .. name
  end
  if item.key == "Step" and value(item) == nil then return tr("这个特效只有一档，换按力度分档的才能调") end
  return tr(item[2] or "")
end

local function overridden(item)
  if item[4] == "fx" then
    local t = S.vfx and S.vfx.fxTuning and S.vfx.fxTuning[S.vfx.slashPath() or ""]
    return t ~= nil and t[item.key] ~= nil
  end
  return item[3] ~= nil and HUD.overrides[item[3]] ~= nil
end

-- The last hit and deflect (HUD.capture keeps the facts; they are worded here, in the language of now).
local function lastHit()
  local h = st.last.hit
  if type(h) ~= "table" then return h or "-" end
  local r = h.rhythm
  return trf("%s，部位 %s%s", tostring(h.tier), h.bone or (h.estimated and tr("估计") or "-"),
    r and (r.accent and tr("，重音") or trf("，第 %d 下 x%.2f", r.chain or 0, r.emph or 1)) or "")
end

local function lastDeflect()
  local d = st.last.deflect
  if type(d) ~= "table" then return d or "-" end
  return trf("%s，倍率 %s", tostring(d.tier), d.mult and string.format("%.2f", d.mult) or "-")
end

local function statusLines()
  local out = {}
  local F = S.freeze or {}
  out[#out + 1] = trf("定格：%s，自检%s", tostring(F.method),
    tr(S.freezeVerdict == true and "通过" or (S.freezeVerdict == false and "未生效" or "待定")))
  out[#out + 1] = trf("帧时间 %.1f ms，卡顿记录 %d 次", U.frameMs, U.hitches or 0)
  out[#out + 1] = tr("最近命中：") .. lastHit()
  out[#out + 1] = tr("最近格挡：") .. lastDeflect()
  local b = S.hit and S.hit.blade
  out[#out + 1] = tr("刀身挂点：") .. (b and b.name and U.valid(b.comp) and b.name or "-")
  out[#out + 1] = tr("命中特效：") .. (S.vfx and S.vfx.slashLabel() or "-")
  local H = S.hit or {}
  out[#out + 1] = trf("命中 %d，格挡 %d，忽略跳伤 %d", H.hits or 0, H.deflects or 0, H.ignored or 0)
  if S.rhythm then out[#out + 1] = tr("节奏：") .. S.rhythm.stats() end
  if S.screen then out[#out + 1] = tr("画面冲击：") .. S.screen.stats() end
  if S.guard then
    local r = S.guardState and S.guardState.ratio
    out[#out + 1] = trf("杀气 %s，破防 %d 次", r and string.format("%.0f%%", r * 100) or "-", S.guard.breaks or 0)
  end
  if S.update then out[#out + 1] = tr("版本：") .. (U.try("hud.update", S.update.status, "check") or "-") end
  if S.env then out[#out + 1] = tr("环境：") .. S.env.status() end
  return out
end

-- ------------------------------------------------------------------ the panel's model: lines and scroll

local function currentPreset()
  local name = (S.cfg.Hud or {}).Preset
  for i, p in ipairs(HUD.PRESETS) do
    if p.name == name then return i end
  end
  return #HUD.PRESETS
end

local function lines()
  local out = {}
  for _, sec in ipairs(HUD.TABS[st.page].sections) do
    out[#out + 1] = { kind = "head", title = sec.title, note = sec.note, h = L.headH }
    if sec.status then
      for _, s in ipairs(statusLines()) do out[#out + 1] = { kind = "status", text = s, h = L.statusH } end
    else
      for _, it in ipairs(sec.items) do out[#out + 1] = { kind = "item", item = it, h = L.itemH } end
    end
  end
  return out
end

-- The furthest the list can scroll: the first line from which the rest fits.
local function maxScroll(all)
  local used = 0
  for i = #all, 1, -1 do
    used = used + all[i].h
    if used > L.contentH then return i + 1 end
  end
  return 1
end

-- The lines from st.scroll that fit.
local function visible(all)
  st.scroll = math.max(1, math.min(st.scroll or 1, maxScroll(all)))
  local out, used = {}, 0
  for i = st.scroll, #all do
    if used + all[i].h > L.contentH or #out >= L.slots then break end
    out[#out + 1] = { line = all[i], y = used, index = i }
    used = used + all[i].h
  end
  return out, st.scroll > 1, (out[#out] and out[#out].index or 0) < #all
end

-- The slot index of a click area's id ("row:3" -> 3).
local function slotOf(id) return tonumber(tostring(id or ""):match(":(%d+)$")) end

-- The compare button's label: what a click does now.
local function trialLabel()
  if st.trialId then return tr("原版试打中：点此恢复") end
  return trf("原版试打 %d 秒", tonumber((S.cfg.Hud or {}).TrialSec) or 10)
end

-- ------------------------------------------------------------------ render

local function renderSlot(i, s, entry)
  local l = entry and entry.line
  show(s.canvas, l ~= nil, PASS)
  st.slotLines[i] = l
  if not l then
    for _, id in ipairs({ "row:", "dec:", "inc:", "rowreset:" }) do area(id .. i, false) end
    return
  end
  moveTo(s.slot, 0, L.contentY + entry.y, entry.y)
  local head, item, status = l.kind == "head", l.kind == "item", l.kind == "status"
  local hovered = item and slotOf(st.hover) == i and not tostring(st.hover):find("^preset") and not tostring(st.hover):find("^tab")
    and not tostring(st.hover):find("^lang")
  show(s.diamond, head)
  show(s.head, head)
  show(s.headNote, head and l.note ~= nil)
  show(s.title, item)
  show(s.desc, item)
  show(s.line, item)
  show(s.hl, hovered)
  show(s.accent, hovered)
  show(s.status, status)
  if head then
    setText(s.head, tr(l.title))
    setText(s.headNote, tr(l.note) or "")
  elseif status then
    setText(s.status, clip(l.text, 62))
  end
  local kind = item and l.item[4]
  local isBool, isChoice = kind == "bool", kind == "choice" or kind == "fxchoice"
  local isAction = kind == "action"
  show(s.check, isBool)
  show(s.state, isBool)
  show(s.chevL, item and not isBool and not isAction)
  show(s.chevR, item and not isBool and not isAction)
  show(s.value, item and not isBool)
  local over = item and overridden(l.item)
  show(s.reset, item and over and hovered and kind ~= "fxchoice")
  -- The whole row is under the mouse as one (its reset mark shows then); a click on it flips a switch, steps a
  -- choice or runs an action, and does nothing on a number row.
  area("row:" .. i, item)
  area("dec:" .. i, item and not isBool and not isAction)
  area("inc:" .. i, item and not isBool and not isAction)
  area("rowreset:" .. i, item and over and hovered and kind ~= "fxchoice")
  if not item then return end
  local it = l.item
  local v = value(it)
  -- Both lines stop short of the row's control: the switch, the reset mark of a number, a choice's arrow.
  local fit = isBool and "bool" or (isChoice and "choice" or "num")
  setText(s.title, clip(tr(it[1]), HUD.FIT.title[fit] - (over and 2 or 0)) .. (over and "  *" or ""))
  setText(s.desc, clip(describe(it), HUD.FIT.desc[fit]))
  if isBool then
    setImage(s.check, (hovered and "checkbox_hover_" or "checkbox_") .. (v and "on" or "off"))
    setText(s.state, tr(v and "开" or "关"))
    setTextColor(s.state, v and COL.text or COL.dim, v and "text" or "dim")
  else
    local wide = isChoice
    moveTo(s.chevLSlot, wide and 286 or 392, 14, wide)
    moveTo(s.decSlot, wide and 276 or 382, 4, wide)
    cached(s.valueSlot, "size", wide, function()
      s.valueSlot:SetPosition({ X = wide and 300 or 406, Y = 12 })
      s.valueSlot:SetSize({ X = wide and 176 or 70, Y = 22 })
    end)
    setText(s.value, fmt(it, v))
    local hl = function(id) return st.hover == id and COL.text or (hovered and COL.focus or COL.border) end
    tint(s.chevL, hl("dec:" .. i), st.hover == "dec:" .. i and "text" or (hovered and "focus" or "border"))
    tint(s.chevR, hl("inc:" .. i), st.hover == "inc:" .. i and "text" or (hovered and "focus" or "border"))
  end
end

function HUD.render()
  if not st.shown then return end
  if not widget() then return end
  local w = st.w
  local hv = st.hover
  st.slotLines = st.slotLines or {}
  -- The texts that change only with the language.
  for _, e in ipairs(w.static) do setText(e[1], tr(e[2])) end
  -- Header: the language button, the master switch and the close mark.
  local langLit = st.langOpen or hv == "lang"
  setText(w.langName, Lang.name())
  setImage(w.langBtn, langLit and "button_hover" or "button_normal")
  tint(w.langChev, langLit and COL.text or COL.border, langLit and "text" or "border")
  area("lang", true)
  setText(w.enabledTxt, tr(S.cfg.Enabled and "已启用" or "已关闭"))
  setImage(w.enabledChk, (hv == "enabled" and "checkbox_hover_" or "checkbox_") .. (S.cfg.Enabled and "on" or "off"))
  show(w.enabledHl, hv == "enabled")
  tint(w.close, hv == "close" and COL.text or COL.border, hv == "close" and "text" or "border")
  area("enabled", true)
  area("close", true)
  area("panel", true)
  area("outside", true)
  -- Presets: the one in use red and bright, the others dim; the one under the mouse lit.
  local cur = currentPreset()
  for i in ipairs(HUD.PRESETS) do
    local on, over = i == cur, hv == "preset:" .. i
    setImage(w.presetBtn[i], on and "button_selected" or (over and "button_hover" or "button_normal"))
    setTextColor(w.presetTxt[i], (on or over) and COL.text or COL.dim, (on or over) and "text" or "dim")
    area("preset:" .. i, true)
  end
  -- Tabs.
  local tw = (L.W - 48) / #HUD.TABS
  for i in ipairs(HUD.TABS) do
    local on, over = i == st.page, hv == "tab:" .. i
    setTextColor(w.tabTxt[i], on and COL.text or (over and COL.focus or COL.dim), on and "text" or (over and "focus" or "dim"))
    area("tab:" .. i, true)
  end
  moveTo(w.tabLineSlot, 24 + (st.page - 1) * tw + 8, 186, st.page)
  moveTo(w.tabDiamondSlot, 24 + (st.page - 1) * tw + tw / 2 - 5, 182, st.page)
  -- Rows.
  local vis, up, down = visible(lines())
  for i, s in ipairs(w.slots) do renderSlot(i, s, vis[i]) end
  show(w.moreUp, up)
  show(w.moreDown, down)
  area("up", up)
  area("down", down)
  -- Try vanilla, footer.
  setImage(w.compareBtn, st.trialId and "button_selected" or (hv == "compare" and "button_hover" or "button_normal"))
  setText(w.compareTxt, trialLabel())
  area("compare", true)
  show(w.resetHl, hv == "reset")
  setTextColor(w.resetTxt, hv == "reset" and COL.text or COL.dim, hv == "reset" and "text" or "dim")
  area("reset", true)
  setText(w.note, clip(st.note or tr("已保存"), 38))
  setText(w.keyHint, tr(escCloses() and "或 Esc 关闭" or "关闭面板"))
  if w.keyCap then setText(w.keyCap, "Ctrl+F5") end
  -- The language list, over the presets and tabs while it is open.
  local open = st.langOpen == true
  show(w.langList, open, PASS)
  for i, l in ipairs(Lang.LIST) do
    local on, over = l.code == Lang.code, hv == "langopt:" .. i
    show(w.langHl[i], open and over)
    show(w.langMark[i], open and on)
    setTextColor(w.langTxt[i], (on or over) and COL.text or COL.dim, (on or over) and "text" or "dim")
    area("langopt:" .. i, open)
  end
end

-- A text version of what the panel shows (the offline tests read it; ">" marks the row under the mouse, "*" a
-- changed row; the language list's line shows while it is open).
function HUD.describe()
  local out = {}
  out[#out + 1] = string.format("%s PBZHitFeel %s  [%s]  {%s%s}", tr("打击反馈"), tostring(U.version),
    tr(S.cfg.Enabled and "已启用" or "已关闭"), Lang.name(), st.langOpen and " ▾" or "")
  if st.langOpen then
    local names = {}
    for i, l in ipairs(Lang.LIST) do
      local n = l.code == Lang.code and ("[" .. l.name .. "]") or l.name
      names[#names + 1] = (st.hover == "langopt:" .. i and ">" or "") .. n
    end
    out[#out + 1] = "  ▾ " .. table.concat(names, " ")
  end
  local names, cur = {}, currentPreset()
  for i, p in ipairs(HUD.PRESETS) do names[#names + 1] = i == cur and ("[" .. tr(p.name) .. "]") or tr(p.name) end
  out[#out + 1] = tr("手感预设") .. ": " .. table.concat(names, " ")
  local tabs = {}
  for i, t in ipairs(HUD.TABS) do tabs[#tabs + 1] = i == st.page and ("[" .. tr(t.title) .. "]") or tr(t.title) end
  out[#out + 1] = table.concat(tabs, " ")
  local vis = visible(lines())
  for i, v in ipairs(vis) do
    local l = v.line
    if l.kind == "head" then
      out[#out + 1] = "◆ " .. tr(l.title) .. (l.note and ("  " .. tr(l.note)) or "")
    elseif l.kind == "status" then
      out[#out + 1] = "    " .. l.text
    else
      local it = l.item
      out[#out + 1] = string.format("%s%s  %s%s  | %s", slotOf(st.hover) == i and "> " or "  ", tr(it[1]),
        fmt(it, value(it)), overridden(it) and " *" or "", describe(it))
    end
  end
  out[#out + 1] = "[" .. trialLabel() .. "]"
  out[#out + 1] = "◆ " .. (st.note or tr("已保存")) .. "   " .. tr("恢复本页默认")
  return U.keys(table.concat(out, "\n"))
end

-- The click area with this id ("row:3", "inc:3", "preset:2", "tab:4", "lang", "langopt:2", "compare", ...), for the
-- offline tests.
function HUD.button(id)
  local e = st.w and st.w.byId[id]
  return e and e.w
end

-- The panel's widgets, for the offline tests.
function HUD.parts() return st.w end

-- The slot showing the row labelled `label` (its key, or its text in the language of now) on this tab, if on screen.
function HUD.slotOf(label)
  for i, l in pairs(st.slotLines or {}) do
    if l and l.item and (l.item[1] == label or tr(l.item[1]) == label) then return i end
  end
end

-- ------------------------------------------------------------------ changes

-- A hand-made change to a key a preset sets turns the current set into Custom.
local function markCustom(path)
  if not (path and HUD.IS_PRESET_KEY[path]) then return end
  if HUD.overrides["Hud.Preset"] ~= nil then
    HUD.overrides["Hud.Preset"] = nil
    C.setPath(S.cfg, "Hud.Preset", nil)
  end
end

local function save(item, v)
  if item[4] == "fx" then
    local ok, shown = false, nil
    if S.vfx then ok, shown = S.vfx.fxSet(item.key, v) end
    st.note = ok and (trf("已保存：%s %s", tr(item[1]), fmt(item, value(item))) .. (shown and tr("，已预览") or ""))
      or tr("保存失败")
    return
  end
  C.setPath(S.cfg, item[3], v)
  if C.SESSION_ONLY[item[3]] then
    st.note = tr("只在这次游戏有效")
    U.log("hud: %s = %s for this session (not saved)", item[3], tostring(v))
  else
    HUD.overrides[item[3]] = v
    markCustom(item[3])
    st.note = C.saveTuning(U, HUD.overrides) and trf("已保存：%s %s", tr(item[1]), fmt(item, v)) or tr("保存失败")
  end
  -- Switching something off lets the features drop anything they still hold (freeze, camera layers, music duck).
  if item[4] == "bool" and not v and S.releaseAll then S.releaseAll() end
end

-- Back to config.lua's value for one row.
local function resetItem(item, base)
  if item[4] == "fxchoice" or item[4] == "action" then return end
  if item[4] == "fx" then
    if S.vfx then S.vfx.fxSet(item.key, nil) end
    return
  end
  HUD.overrides[item[3]] = nil
  markCustom(item[3])
  C.setPath(S.cfg, item[3], C.getPath(base, item[3]))
end

local function applyPreset(i)
  local p = HUD.PRESETS[i]
  local was = currentPreset()
  if was == i and not p.custom then return end
  if HUD.PRESETS[was].custom and not p.custom then
    local snap = {}
    for _, k in ipairs(HUD.PRESET_KEYS) do snap[k] = HUD.overrides[k] end
    C.saveOverrides(U, HUD.CUSTOM_FILE, snap,
      "PBZHitFeel: your own settings, kept when you picked a preset in the Ctrl+F5 panel; 自定义 brings them back.")
  end
  local values = p.custom and C.readOverrides(U, HUD.CUSTOM_FILE) or p.values
  local base = C.loadBase(U)
  for _, k in ipairs(HUD.PRESET_KEYS) do
    local v = values[k]
    HUD.overrides[k] = v
    if v == nil then v = C.getPath(base, k) end
    C.setPath(S.cfg, k, v)
  end
  HUD.overrides["Hud.Preset"] = (not p.custom) and p.name or nil
  C.setPath(S.cfg, "Hud.Preset", HUD.overrides["Hud.Preset"])
  st.note = C.saveTuning(U, HUD.overrides) and trf("手感预设：%s", tr(p.name)) or tr("保存失败")
  U.log("hud: preset %s", p.name)
  if S.releaseAll then S.releaseAll() end
end

local function resetPage()
  local base = C.loadBase(U)
  for _, sec in ipairs(HUD.TABS[st.page].sections) do
    for _, it in ipairs(sec.items or {}) do resetItem(it, base) end
  end
  C.saveTuning(U, HUD.overrides)
  st.note = trf("已恢复本页默认：%s", tr(HUD.TABS[st.page].title))
end

-- One step of a row: a switch flips, a choice or a number moves by `d`.
local function step(item, d)
  local v = value(item)
  local kind = item[4]
  if kind == "fxchoice" then
    if S.vfx then S.vfx.cycleSlash(d) end
  elseif kind == "fx" and v == nil then
    st.note = tr("这个特效只有一档，调不了轻重")
  elseif kind == "bool" then
    save(item, not v)
  elseif kind == "choice" then
    local list, at = item[5], 1
    for i, c in ipairs(list) do if c == v then at = i end end
    save(item, list[(at - 1 + d) % #list + 1])
  else
    local s, lo, hi = item[5] or 0.1, item[6] or -math.huge, item[7] or math.huge
    v = math.max(lo, math.min(hi, (tonumber(v) or 0) + d * s))
    save(item, math.floor(v / s + 0.5) * s)
  end
end

local function scroll(d)
  st.scroll = (st.scroll or 1) + d
end

-- What a click on the area `id` does.
local function act(id)
  local kind, n = tostring(id):match("^([%a]+):?(%d*)$")
  n = tonumber(n)
  -- While the language list is open, a click anywhere else only closes it.
  if st.langOpen and kind ~= "lang" and kind ~= "langopt" then
    st.langOpen = false
    HUD.render()
    return
  end
  local l = n and st.slotLines and st.slotLines[n]
  if id == "lang" then
    st.langOpen = not st.langOpen
  elseif kind == "langopt" then
    st.langOpen = false
    local pick = Lang.LIST[n or 0]
    if pick then HUD.setLanguage(pick.code) end
  elseif id == "enabled" then
    HUD.cancelTrial()
    save({ "Mod 总开关", nil, "Enabled", "bool" }, not S.cfg.Enabled)
  elseif id == "close" then
    HUD.close()
    return
  elseif id == "compare" then
    HUD.trial()
    return
  elseif kind == "preset" then
    applyPreset(n)
  elseif kind == "tab" then
    st.page, st.scroll = n, 1
  elseif kind == "row" and l and l.item then
    local k = l.item[4]
    if k == "action" then
      if S.update then st.note = U.try("hud.action", S.update.run, l.item.run) or st.note end
    elseif k ~= "bool" and k ~= "choice" and k ~= "fxchoice" then
      return
    else
      step(l.item, 1)
    end
  elseif kind == "dec" and l and l.item then
    step(l.item, -1)
  elseif kind == "inc" and l and l.item then
    step(l.item, 1)
  elseif kind == "rowreset" and l and l.item then
    resetItem(l.item, C.loadBase(U))
    C.saveTuning(U, HUD.overrides)
    st.note = trf("已恢复：%s", tr(l.item[1]))
  elseif id == "up" then
    scroll(-1)
  elseif id == "down" then
    scroll(1)
  elseif id == "reset" then
    resetPage()
  else
    return
  end
  HUD.render()
end

local REPEATS = { dec = true, inc = true, up = true, down = true }
local WHEEL = { { KeyName = FName("MouseScrollUp") }, { KeyName = FName("MouseScrollDown") } }
local WHEEL_AXIS = { KeyName = FName("MouseWheelAxis") }

-- One question to a click area's Button, "IsHovered" or "IsPressed" (no closure per call: it runs every frame).
local function ask(e, fn)
  local ok, v = pcall(e.w[fn], e.w)
  return ok and v == true
end

-- Each frame while the panel is open: which area the mouse is over and which is pressed. Slate hovers only the
-- topmost area under the mouse, so the one from the last frame is asked first and the others only after it lost the
-- mouse; only that area can go down, and one held from the last frame is asked until it lets go (2 or 3 questions a
-- frame instead of two per area; if no area reports the mouse at all, every area is asked whether it is pressed). A
-- press acts once; the arrows act again while held, after Keys.RepeatDelayMs and then every Keys.RepeatMs. The wheel
-- is read from the controller like the hotkeys (the panel gets no wheel events itself) and scrolls the panel wherever
-- the mouse is, while it is open: v0.6.1 also asked Slate whether the mouse was over the panel, and after a scroll had
-- moved the rows under a still mouse that answer was missing for a frame or more, so a notch was lost now and then. A
-- quick flick of several notches within one frame scrolls as many lines (the wheel axis holds their sum).
function HUD.pollButtons()
  local w = st.w
  if not (w and w.buttons) then return end
  if not U.valid(st.widget) then
    -- The level changed under the open panel: input goes back to the game, a new panel waits hidden.
    widget()
    return
  end
  local now, dirty = U.now(), false
  local cur = st.hoverArea and w.byId[st.hoverArea]
  if not (cur and st.active[cur.id] and ask(cur, "IsHovered")) then
    cur = nil
    for k = #w.buttons, 1, -1 do
      local b = w.buttons[k]
      if st.active[b.id] and ask(b, "IsHovered") then
        cur = b
        break
      end
    end
  end
  st.hoverArea = cur and cur.id
  local over = cur ~= nil and cur.id ~= "outside"
  local hovered = over and cur.id ~= "panel" and cur.id or nil
  local pressed, prev = {}, st.pressedPrev or {}
  if cur then
    if ask(cur, "IsPressed") then pressed[cur.id] = true end
    for id in pairs(prev) do
      local e = w.byId[id]
      if e and e ~= cur and st.active[id] and ask(e, "IsPressed") then pressed[id] = true end
    end
  else
    for _, b in ipairs(w.buttons) do
      if st.active[b.id] and ask(b, "IsPressed") then pressed[b.id] = true end
    end
  end
  local keys = S.cfg.Keys or {}
  st.pressedPrev = pressed
  for id in pairs(pressed) do
    if not st.shown then break end
    local kind = id:match("^(%a+)")
    if not prev[id] then
      st.repeatAt[id] = now + (keys.RepeatDelayMs or 450) / 1000
      act(id)
    elseif REPEATS[kind] and now >= (st.repeatAt[id] or math.huge) then
      st.repeatAt[id] = now + (keys.RepeatMs or 110) / 1000
      act(id)
    end
  end
  if not st.shown then return end
  local pc = U.pc()
  if pc then
    local d = 0
    for i, key in ipairs(WHEEL) do
      if U.try("hud.wheel", function() return pc:WasInputKeyJustPressed(key) end) == true then d = d + (i == 1 and -1 or 1) end
    end
    if d ~= 0 then
      local v = math.abs(tonumber(U.try("hud.wheelaxis", function() return pc:GetInputAnalogKeyState(WHEEL_AXIS) end)) or 0)
      scroll(d * (v >= 1.5 and math.min(5, math.floor(v + 0.5)) or 1))
      dirty = true
    end
  end
  if hovered ~= st.hover then
    st.hover = hovered
    dirty = true
  end
  if dirty then HUD.render() end
end

-- ------------------------------------------------------------------ try vanilla for a moment

-- The compare button: the mod off for Hud.TrialSec seconds and the panel closed, so you fight in vanilla at once;
-- then the mod comes back by itself (a notice and one rumble, as Ctrl+F7 gives). Clicking it again, Ctrl+F7 or the
-- master switch ends the trial early. For this session only, like Ctrl+F7.
function HUD.trial()
  if st.trialId then
    HUD.endTrial()
    return
  end
  if not S.cfg.Enabled then
    st.note = tr("mod 现在是关的，不用试打")
    HUD.render()
    return
  end
  local sec = tonumber((S.cfg.Hud or {}).TrialSec) or 10
  st.trials = (st.trials or 0) + 1
  local id = st.trials
  st.trialId = id
  S.cfg.Enabled = false
  if S.releaseAll then S.releaseAll() end
  if S.rumble then S.rumble.pulse(2) end
  U.log("hud: vanilla for %d s", sec)
  HUD.close()
  HUD.toast(trf("原版试打 %d 秒，到时自动恢复（Ctrl+F7 提前恢复）", sec), 3000)
  ExecuteInGameThreadWithDelay(math.floor(sec * 1000), function()
    local h = S.hud
    if S.hudState.trialId == id and h then U.try("hud.trialEnd", h.endTrial) end
  end)
end

function HUD.endTrial()
  if not st.trialId then return end
  st.trialId = nil
  S.cfg.Enabled = true
  if S.rumble then S.rumble.pulse(1) end
  U.log("hud: vanilla trial over, the mod is on again")
  HUD.toast(tr("打击感已恢复"))
  HUD.render()
end

-- Ctrl+F7 or the master switch during a trial: the trial ends and that choice stays.
function HUD.cancelTrial() st.trialId = nil end

-- Input that an open panel of an earlier run of the scripts held (hf_env took that panel down): back to the game, as
-- closing it would have done. The engine clamps each release, so one too many does nothing.
function HUD.releaseInput()
  local pc = U.pc()
  if not pc or st.shown then return end
  local hold = { pc = pc, move = true, look = true, pcOff = true, pawnOff = true }
  hold.pawn = U.try("hud.pawn", function() return pc.Pawn end)
  giveInput({ pc = pc, mode = true, hold = hold })
end

-- ------------------------------------------------------------------ open, close, input

-- While the panel is open the character does not act on keys: its input and the controller's are off, and moving
-- and looking are ignored (counted by the engine, so this pairs with whatever else ignores them). The key state
-- itself still updates, which the hotkey poller and the wheel read.
local function holdCharacter(pc)
  local b = { pc = pc }
  b.pawn = U.try("hud.pawn", function() return pc.Pawn end)
  b.move = pcall(function() pc:SetIgnoreMoveInput(true) end)
  b.look = pcall(function() pc:SetIgnoreLookInput(true) end)
  if U.valid(b.pawn) then b.pawnOff = pcall(function() b.pawn:DisableInput(pc) end) end
  b.pcOff = pcall(function() pc:DisableInput(pc) end)
  return b
end

local function freeCharacter(b)
  local pc = b and b.pc
  if not U.valid(pc) then return end
  if b.pcOff then pcall(function() pc:EnableInput(pc) end) end
  if b.pawnOff and U.valid(b.pawn) then pcall(function() b.pawn:EnableInput(pc) end) end
  if b.move then pcall(function() pc:SetIgnoreMoveInput(false) end) end
  if b.look then pcall(function() pc:SetIgnoreLookInput(false) end) end
end

local function paused(pc)
  local gs = U.cdo(HUD.GPS)
  return gs ~= nil and U.try("hud.paused", function() return gs:IsGamePaused(pc) end) == true
end

-- Opening: the cursor, "game and UI" input (no key flush: the poller must see Ctrl+F5 stay down), the character held.
-- Nothing changes while a menu of the game's own has the cursor: the game paused, or its cursor already on (the title
-- screen, menus that do not pause). Up to v0.6.4 the panel took input there too, and closing it set "game only" input
-- and hid the cursor, so such a menu took no more clicks.
local function takeInput()
  local pc = U.pc()
  if not pc or paused(pc) then return nil end
  if U.try("hud.cursor", function() return pc.bShowMouseCursor end) == true then return nil end
  local inp = { hold = holdCharacter(pc), pc = pc }
  pcall(function() pc.bShowMouseCursor = true end)
  local lib = U.cdo(HUD.WBL)
  inp.mode = lib ~= nil and U.try("hud.gameuimode", function()
    U.callNamed(lib, HUD.GAME_UI, { PlayerController = pc, InWidgetToFocus = st.widget, InMouseLockMode = 0,
      bHideCursorDuringCapture = false, bFlushInput = false })
    return true
  end) == true
  if not inp.mode then U.log("hud: could not set the input mode; a click may reach the game") end
  return inp
end

-- Closing: the character free, input to the game alone, the cursor off (on the controller of now, if the level
-- changed meanwhile: the input mode is the viewport's, not the controller's). If the game paused meanwhile (Esc
-- opened its menu after all), the cursor and the input mode are left to that menu.
giveInput = function(inp)
  freeCharacter(inp.hold)
  local pc = U.valid(inp.pc) and inp.pc or U.pc()
  if not pc or paused(pc) then return end
  local lib = U.cdo(HUD.WBL)
  if lib and inp.mode then
    U.try("hud.gamemode", U.callNamed, lib, HUD.GAME_ONLY, { PlayerController = pc, bFlushInput = false })
  end
  pcall(function() pc.bShowMouseCursor = false end)
end

-- After Esc the game gets its input back only once Esc is up, and two frames later: it never sees that press, so
-- its own menu does not open as the panel closes.
local ESC = { KeyName = FName("Escape") }
local function giveInputAfterEsc(inp)
  st.pendingInput = inp
  local frames, giveUp = 0, U.now() + 2
  U.everyFrame("hud.escUp", function()
    local s = S.hudState
    if s.pendingInput ~= inp then return true end
    local pc = inp.pc
    local down = U.valid(pc) and U.try("hud.esc", function() return pc:IsInputKeyDown(ESC) end) == true
    if down and U.now() < giveUp then return false end
    frames = frames + 1
    if frames < 3 then return false end
    s.pendingInput = nil
    giveInput(inp)
    return true
  end)
end

local function mouseLoop()
  if st.mouseLoop then return end
  st.mouseLoop = true
  U.everyFrame("hud.mouse", function()
    local s, h = S.hudState, S.hud
    if not s.shown or not h then
      s.mouseLoop = false
      return true
    end
    U.try("hud.poll", h.pollButtons)
    return false
  end)
end

function HUD.open()
  if st.shown or not (S.cfg.Hud or {}).Enabled then return end
  HUD.applyLanguage(true)
  if not widget() then return end
  U.try("hud.late", lateTextures)
  -- (Input still held back after an Esc a moment ago: handed over first.)
  if st.pendingInput then
    local inp = st.pendingInput
    st.pendingInput = nil
    giveInput(inp)
  end
  st.shown, st.openedAt, st.hover, st.hoverArea, st.langOpen = true, U.now(), nil, nil, false
  st.pressedPrev, st.repeatAt = {}, {}
  -- A notice still up (Ctrl+F6, the end of a trial) moves to the panel's status line instead of overlapping it.
  if st.toastMsg then
    st.note, st.toastMsg = st.toastMsg, nil
    st.toastId = (st.toastId or 0) + 1
    U.try("hud.toastOff", function() st.w.toast:SetVisibility(GONE) end)
  end
  U.try("hud.show", function()
    st.w.panel:SetVisibility(PASS)
    st.widget:SetVisibility(PASS)
  end)
  st.input = takeInput()
  if not st.loggedOpen then
    st.loggedOpen = true
    U.log("hud: opened for the mouse (%s)", st.input and (st.input.mode and "game-and-UI input, the character held"
      or "input mode not set") or "a menu of the game's has the cursor (paused, or its cursor on): input left to it")
  end
  HUD.render()
  HUD.startRefresh()
  mouseLoop()
end

-- `how` is "esc" when Esc closed it (see giveInputAfterEsc).
function HUD.close(how)
  if not st.shown then return end
  st.shown, st.hover, st.hoverArea, st.langOpen = false, nil, nil, false
  st.active = {}
  U.try("hud.hide", function()
    st.w.panel:SetVisibility(GONE)
    st.w.blocker:SetVisibility(GONE)
    if not st.toastMsg then st.widget:SetVisibility(GONE) end
  end)
  if st.w then st.cache[st.w.blocker] = nil end
  local inp = st.input
  st.input = nil
  if not inp then return end
  if how == "esc" then giveInputAfterEsc(inp) else giveInput(inp) end
end

function HUD.toggle()
  if not st.shown then return HUD.open() end
  -- (Not the Ctrl+F5 that opened it, seen again.)
  if U.now() - (st.openedAt or 0) > 0.3 then HUD.close() end
end

-- Live status while shown (4 times a second, on the tab that has it); stops when hidden.
function HUD.startRefresh()
  if st.refreshing then return end
  st.refreshing = true
  local loop = {}
  loop.handle = LoopInGameThreadWithDelay((S.cfg.Hud or {}).RefreshMs or 250, function()
    local s, h = S.hudState, S.hud
    if not s.shown or not h then
      CancelDelayedAction(loop.handle)
      s.refreshing = false
      return
    end
    for _, sec in ipairs(h.TABS[s.page].sections) do
      if sec.status then
        U.try("hud.refresh", h.render)
        return
      end
    end
  end)
end

-- A one-line notice for a moment while the panel is closed (Ctrl+F6 names the hit effect it switched to); with the
-- panel open it goes on the panel's status line instead.
function HUD.toast(msg, ms)
  if not (S.cfg.Hud or {}).Enabled then return end
  if st.shown then
    st.note = msg
    HUD.render()
    return
  end
  if not widget() then return end
  st.toastId = (st.toastId or 0) + 1
  st.toastMsg = msg
  local id = st.toastId
  U.try("hud.toast", function()
    st.w.toastTxt:SetText(FText(clip(U.keys(msg), 54)))
    st.w.toast:SetVisibility(SHOWN)
    st.widget:SetVisibility(SHOWN)
  end)
  ExecuteInGameThreadWithDelay(ms or (S.cfg.Hud or {}).ToastMs or 2500, function()
    local s = S.hudState
    if s.toastId ~= id or not (s.widget and U.valid(s.widget)) then return end
    s.toastMsg = nil
    U.try("hud.toastHide", function()
      s.w.toast:SetVisibility(GONE)
      if not s.shown then s.widget:SetVisibility(GONE) end
    end)
  end)
end

function HUD.toastShown() return st.toastMsg end

-- Remembers the last hit and deflect for the status lines (runs as a capture, mod on or off).
function HUD.capture(ctx)
  if ctx.kind == "hit" and ctx.byPlayer then
    local r = ctx.rhythm
    st.last.hit = { tier = ctx.tierName, bone = ctx.hitBone, estimated = ctx.impactEstimated,
      rhythm = r and { accent = r.accent, chain = r.chain, emph = r.emph } }
  elseif ctx.kind == "deflect" and ctx.byPlayer then
    st.last.deflect = { tier = ctx.tierName, mult = ctx.clashMult }
  end
end

function HUD.onHit() end

-- Mod off (Ctrl+F7, or a feature switched off): the panel itself stays as it is.
function HUD.release() end

function HUD.stats()
  return string.format("shown=%s built=%s building=%s failed=%d input=%s trial=%s lang=%s", tostring(st.shown),
    tostring(st.widget ~= nil), tostring(st.building ~= nil), st.failed or 0,
    st.input and (st.input.mode and "game+ui" or "cursor only") or "-", tostring(st.trialId ~= nil), tostring(Lang.code))
end

return HUD
