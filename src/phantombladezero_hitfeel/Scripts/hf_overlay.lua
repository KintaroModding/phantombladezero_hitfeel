-- PBZ HitFeel: a dark-red edge over the screen, for hf_guard's Sha-Chi and guard-break cues. A full-screen image with a
-- clear middle and dark-red edges, deepest in the corners (ui/edge_red.png, drawn by dev/make_edge.py), stretched over
-- the viewport. It sits under the game's own HUD (Z order -100), so the health and Sha-Chi bars stay sharp, is never
-- hit-testable, and is collapsed while clear. How strong it is: the image's opacity, set only when it changes.
-- Built per player controller (a new level means a new widget; the old one went with its world), on the first cue
-- rather than at map load: one small texture and three widgets.
local Ov = { name = "overlay", builds = 0 }
local S, U, C
local st

Ov.Z = -100
Ov.TEXTURE = "edge_red"
Ov.IMPORT = "/Script/Engine.KismetRenderingLibrary:ImportFileAsTexture2D"
-- (The widget layout; one kept over a reload from code with another is built again.)
local LAYOUT = 1
local GONE, SHOWN = 1, 3

function Ov.init(state)
  S, U, C = state, state.U, state.C
  S.overlayState = S.overlayState or { alpha = 0 }
  st = S.overlayState
end

local function construct(cname, outer, name)
  local cls = StaticFindObject("/Script/UMG." .. cname)
  if not U.valid(cls) then error("UMG class not found: " .. cname) end
  local o = name and StaticConstructObject(cls, outer, name) or StaticConstructObject(cls, outer)
  if not U.valid(o) then error("could not construct " .. cname) end
  return o
end

local function ready(pc)
  return st.widget ~= nil and st.owner == U.addr(pc) and st.layout == LAYOUT and U.valid(st.widget) and U.valid(st.img)
end

-- The widget for the current controller, built if need be; nil when there is no controller or the build failed (it
-- is tried again after 10 s).
local function widget()
  local pc = U.pc()
  if not pc then return nil end
  if ready(pc) then return st.img end
  if st.widget and st.owner == U.addr(pc) and U.valid(st.widget) then pcall(function() st.widget:RemoveFromParent() end) end
  st.widget, st.img, st.alpha = nil, nil, 0
  if U.now() < (st.retryAt or 0) then return nil end
  local t0 = os.clock()
  local ok, err = pcall(function()
    local lib = U.cdo("/Script/Engine.Default__KismetRenderingLibrary")
    local tex = lib and U.callNamed(lib, Ov.IMPORT, { WorldContextObject = pc,
      Filename = U.root .. "/ui/" .. Ov.TEXTURE .. ".png" })
    if not U.valid(tex) then error("ui/" .. Ov.TEXTURE .. ".png did not load") end
    local w = construct("UserWidget", pc, S.env and S.env.widgetName("Edge"))
    local tree = construct("WidgetTree", w)
    w.WidgetTree = tree
    pcall(function() w:SetOwningPlayer(pc) end)
    local root = construct("CanvasPanel", tree)
    tree.RootWidget = root
    pcall(function() root:SetVisibility(4) end)
    local img = construct("Image", tree)
    -- (The image holds the texture from here on: a Lua value does not keep it alive.)
    img:SetBrushFromTexture(tex, false)
    pcall(function() img:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0 }) end)
    img:SetVisibility(GONE)
    local slot = root:AddChildToCanvas(img)
    pcall(function() slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } }) end)
    pcall(function() slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
    w:AddToViewport(Ov.Z)
    st.widget, st.img, st.owner, st.layout = w, img, U.addr(pc), LAYOUT
  end)
  Ov.builds = Ov.builds + 1
  if not ok then
    st.retryAt = U.now() + 10
    U.log("overlay: could not build the screen edge (%s); the guard cues keep their camera and rumble", tostring(err))
    return nil
  end
  U.note("overlay: screen edge built")
  if Ov.builds <= 3 then U.log("overlay: screen edge built (%.0f ms)", (os.clock() - t0) * 1000) end
  return st.img
end

-- The edge's strength, 0 (clear, collapsed) to 1. Only a change of more than a little reaches the widget.
function Ov.set(alpha)
  alpha = math.max(0, math.min(1, tonumber(alpha) or 0))
  if alpha < 0.004 then alpha = 0 end
  if math.abs(alpha - (st.alpha or 0)) < 0.004 and (alpha > 0 or (st.alpha or 0) == 0) then return end
  if alpha == 0 and not st.img then return end
  local img = widget()
  if not img then return end
  local was = st.alpha or 0
  st.alpha = alpha
  U.try("overlay.set", function()
    img:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = alpha })
    if (was > 0) ~= (alpha > 0) then img:SetVisibility(alpha > 0 and SHOWN or GONE) end
  end)
end

function Ov.alpha() return st.alpha or 0 end

function Ov.release() Ov.set(0) end

function Ov.stats() return string.format("built=%s alpha=%.2f builds=%d", tostring(st.img ~= nil), st.alpha or 0, Ov.builds) end

return Ov
