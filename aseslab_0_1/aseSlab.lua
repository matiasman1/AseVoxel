--------------------------------------------------------------------------------
--                                                                            --
--  brought to you by k.i.d marscat    _____   ___             ___            --
--      ______    _____    ______   .'      /\/  /\   ______  /  /\           --
--    _|___  /\.'  ____/\.' ___  |\/  ----'\\/  / / _|___  /\/  '--.          --
--   /  __  / /____   / /  _____/ |'---   | /  /_/ /  __  / /  ---  |\        --
--   |_____' /______.' /\______/\/______.' |_____/\______' /|_____.' / mmz    --
--   \_____.' \______\'  \_____\.'\_____\.' \____\/\_____.'  \_____.'   2024  --
--                                                                            --
-- dedicated to Ken Silverman - built from scratch cuz aseprite wouldn't! 8-) --
-- find it on kidmarscat.itch.io - and feel free to share it with a friend C: --
--------------------------------------------------------------------------------
-- What's this?                                                               --
--          aseSlab is an Aseprite script that generates and exports          --
--          like voxel preview of the current sprite.                         --
--                                                                     Cool!  --
--------------------------------------------------------------------------------

---- Initialize sprite ---------------------------------------------------------

  -- application
  local show_alert = app.alert
  
  local sprite = app.sprite
  if not sprite then
    show_alert("Error: No sprite available to voxelize."); return;
  end


---- Initialize default values -------------------------------------------------

  local eyedropper = app.pixelColor

  -- tablepool
  local tablePool = {}

  -- aseprite globals
  local aseSprite = Sprite; local aseImage  = Image
  local aseColor  = Color;  local aseRect   = Rectangle

  -- canvas
  local canvasWidth  = 512; local canvasHeight = 288
  local canvasBkgr   = false

  -- mouse and translation
  local mouseX = 0; local mouseY = 0
  local transX = 0; local transY = 0

  -- tiles
  local tileWidth  = 32;  local tileHeight = 32
  local tileCols   = 8;   local tileRows   = 4

  local tileWH_min = 1; local tileWH_max = 96
  local tileCR_min = 1; local tileCR_max = 96

  -- voxel geometry
  local voxelScale = 6; local voxelOver  = 2; local voxelRound = 0

  -- rotation
  local rotX = 0;  local rotY = 0;  local rotZ = 0
  local rotXYZ_min = -180; local rotXYZ_max = 180

  -- projection
  local projDist = 100
  local projDist_min = 1; local projDist_max = 1000
  local projType = { PERSP = 0, ORTHO = 1 };  local projMode = projType.PERSP
  local projInvr = false

  -- voxel preview rendering
  local voxelScale_min = 1;  local voxelScale_max = 32
  local voxelOver_min = -32; local voxelOver_max = 32  

  local drawAllLayers = false
  local cullVoxels = false
  local depthMap   = false
  local voxelEdge  = false

  -- voxel sprite rendering
  local brushCircle = BrushType.CIRCLE; local brushSquare = BrushType.SQUARE

  -- info
  local renderTime = 0; local voxelTotal = 0

                                                                              --

---- Custom functions ----------------------------------------------------------
-------: 1. basic functions ----------------------------------------------------

  local min = math.min
  local max = math.max
  local floor = math.floor

  -- Linear interpolation
  local function lerp(a,b,t) return (a * (1-t) + b * t) end

  -- background checker pattern
  local function drawBkgr(gc, canvas_w, canvas_h)
    if canvasBkgr then
      -- draw user selected background
      gc.color = app.bgColor
      gc:fillRect( Rectangle(0, 0, canvas_w, canvas_h) )
    else
      -- draw transparent grid background
      local docPref = app.preferences.document(sprite)
      local colors = {docPref.bg.color1, docPref.bg.color2}
      local size = docPref.bg.size.width
      local cols, rows = (canvas_w) // size, (canvas_h) // size

      for i=0, cols do
        for j=0, rows do
          gc.color = colors[(i + j) % 2 + 1]
          gc:fillRect(Rectangle(i * size, j * size, size, size))
        end
      end
    end
  end

                                                                              --

-------: 2. table pool (for optimization) --------------------------------------

  local function getTable()
    local table = tablePool[1] or {}; tablePool[1] = nil; return table
  end

  local function recycleTable(table)
    for t in pairs(table) do; table[t] = nil; end
    tablePool[1] = table
  end

                                                                              --

-------: 3. rotation and projection functions ----------------------------------

  -- precompute rotation functions
  local sin = math.sin; local cos = math.cos

  -- Function to convert degrees to radians
  local function degToRad(deg) return deg * math.pi / 180 end

  -- 3D Rotation matrices for X, Y, Z axes
  local function rotateX(point, cosX, sinX)
    return {
      x = point.x,
      y = point.y * cosX - point.z * sinX,
      z = point.y * sinX + point.z * cosX
    }
  end

  local function rotateY(point, cosY, sinY)
    return {
      x =  point.x * cosY + point.z * sinY,
      y =  point.y,
      z = -point.x * sinY + point.z * cosY
    }
  end

  local function rotateZ(point, cosZ, sinZ)
    return {
      x = point.x * cosZ - point.y * sinZ,
      y = point.x * sinZ + point.y * cosZ,
      z = point.z
    }
  end

  -- Project 3D coordinates into 2D
  local function project(point, scale, halfCanvasW, halfCanvasH)
    if projMode == projType.PERSP then
      -- Projection scale factor
      local projDir = projInvr and -point.z or point.z
      local factor  = projDist / (projDist - projDir)

      return {
        x = point.x * (factor * scale) + halfCanvasW,
        y = point.y * (factor * scale) + halfCanvasH,
        z = point.z * (factor * scale) + halfCanvasH
      }
    elseif projMode == projType.ORTHO then
      return {
        x = point.x * scale + halfCanvasW,
        y = point.y * scale + halfCanvasH,
        z = point.z * scale + halfCanvasH -- preserve original
      }
    end
  end

                                                                              --

-------: 4. color and eyedropper -----------------------------------------------

  local getR  = eyedropper.rgbaR
  local getG  = eyedropper.rgbaG
  local getB  = eyedropper.rgbaB
  local getA  = eyedropper.rgbaA
  local getGV = eyedropper.grayaV
  local getGA = eyedropper.grayaA

  local function getColorDepth(voxel_z, max_z)
    local gray = lerp( -64, 255, voxel_z / max_z )
    gray = min( max(gray,0) ,255)
    return aseColor(gray, gray, gray, 255)
  end

                                                                              --

---- The Main Rendering Function -----------------------------------------------
-------: 1. set-up the voxel rendering function --------------------------------

  -- set-up the table with 3d voxel data
  local voxel3d = getTable()

  -- Function to draw voxels on the canvas
  local function drawVoxels(gc)
    -- set-up voxel info
    renderTime = os.clock()
    voxelTotal = 0

    -- reset the voxel table
    recycleTable(voxel3d);  voxel3d = getTable()

    -- default color for voxels (in case of failure)
    local default_color = aseColor(0)

    -- copy sprite.cel data from one or all layers
    local colorMode = sprite.colorMode
    local celImage  = aseImage(tileWidth*tileCols,tileHeight*tileRows,colorMode)

    local spriteLayers = sprite.layers

    if (not drawAllLayers) or (#spriteLayers == 1) then
      -- render the current cel
      local cel = app.cel; if not cel then return end
      celImage:drawImage(cel.image, cel.position)
    else
      -- flatten layers if turned on and available
      for i = 1, #spriteLayers do
        local layer = spriteLayers[i]
        
        -- Only process visible layers with cels in the current frame
        if layer.isVisible and layer.isImage then
          local layerCel = layer:cel(app.frame.frameNumber)
          
          if layerCel then
            celImage:drawImage(layerCel.image, layerCel.position)
          end
        end
      end
    end

    local sprite_isIndexed = (colorMode == ColorMode.INDEXED)
    local sprite_isGrayscale = (colorMode == ColorMode.GRAY)

    -- set-up coords
    local halfCanvasW, halfCanvasH = gc.width  >> 1, gc.height >> 1

    -- tile data
    local tileTotal = (tileRows * tileCols)

    ---- calculate the tile center coordinate
    local tileWHalf = tileWidth  >> 1;  local tileHHalf = tileHeight >> 1
    local tileDHalf = tileTotal  >> 1 -- using the tile no. as depth

    -- precompute rotations
    local rotX_rad = degToRad(rotX)
    local rotX_cos, rotX_sin = cos(rotX_rad), sin(rotX_rad)

    local rotY_rad = degToRad(rotY)
    local rotY_cos, rotY_sin = cos(rotY_rad), sin(rotY_rad)

    local rotZ_rad = degToRad(rotZ)
    local rotZ_cos, rotZ_sin = cos(rotZ_rad), sin(rotZ_rad)

    -- set-up background
    drawBkgr(gc, gc.width, gc.height)

    -- precompute palette colors when in indexed mode
    local palcols = getTable();
    local sprite_palette = sprite.palettes[1]

    if sprite_isIndexed then
      for i = 0, #sprite_palette-1 do
        palcols[i] = sprite_palette:getColor(i)
      end
    end

    -- set-up color table
    local colors = getTable()

    -- set-up var for previous frame voxel culling map
    local cullMap_Zb = getTable();  local cullMap_Zf = getTable()
    local px_max, py_max, pz_max = tileWidth-1, tileHeight-1, tileTotal-1

    -- set-up default voxel size and shape
    local voxel_size  = voxelScale + voxelOver
    local voxel_shape = aseRect(0, 0, voxel_size, voxel_size)

    -- set-up voxel edge width and color
    gc.strokeWidth = 1; local color_edge = aseColor(0,0,0,32)

    -- position 
    local offset = (voxelOver * 0.5) -- no bitwise, we need the float precision
    local offset_x, offset_y = offset + transX, offset + transY

    -- set-up voxel render settings
    local voxel_isDepthMap = (depthMap == true)
    local voxel_isRounded  = (voxelRound > 0)
    local voxel_isEdged    = (voxelEdge == true)

    if voxel_size <= 0 then goto skipRender end

                                                                              --

-------: 2. set-up parsing of the pixel data in the current tile ---------------

    for i = 0, tileTotal - 1 do
      -- get the tile position
      local imageX = (i %  tileCols) * tileWidth
      local imageY = (i // tileCols) * tileHeight

      -- create a copy of the tile's content
      local tileImage = aseImage(tileWidth,tileHeight,colorMode)
      tileImage:drawImage(celImage, -imageX, -imageY)

      -- if the tile has no content, move on to the next tile
      if tileImage:isEmpty() then goto skipTile end

      local tileImageNext = nil
      
      -- copy the content of the next tile for culling purposes
      if cullVoxels then
        tileImageNext = aseImage(tileWidth,tileHeight,colorMode)

        if i < (tileTotal - 1) then
          local imageNextX = ( (i+1) %  tileCols) * tileWidth
          local imageNextY = ( (i+1) // tileCols) * tileHeight

          tileImageNext:drawImage(celImage, -imageNextX, -imageNextY)
        end
      end

      local isTileNextEmpty = (tileImageNext == nil) or tileImageNext:isEmpty()

-------: 3. parse the voxel data from the pixels in the tiles ------------------

      -- precompute the palette for culling and for easy access
      for it in tileImage:pixels() do
        local pixel = it()
        local px, py = it.x, it.y

        local color = default_color

        -- get color depending on sprite color mode
        if sprite_isIndexed then
          color = palcols[getR(pixel)]
        elseif sprite_isGrayscale then
          color = aseColor{ gray = getGV(pixel), alpha = getGA(pixel) }
        else
          color = aseColor(getR(pixel), getG(pixel), getB(pixel), getA(pixel))
        end

        if not colors[px] then colors[px] = {} end
        colors[px][py] = color
      end

      -- start parsing the pixels in the current tile
      for it in tileImage:pixels() do
        -- Current tile image
        local pixel = it()
        local px, py = it.x, it.y
      
        local color = colors[px][py]
      
        -- skip loop entirely if the pixel is empty
        if color.alpha == 0 then goto skipPixel end

        -- Voxel culling if enabled and tileImageNext is not empty
        if cullVoxels then
          if (tileImageNext ~= nil) and (not isTileNextEmpty) then
            local pixelNext = tileImageNext:getPixel(px, py) 
            local colorNext = default_color
        
            -- Get color depending on sprite color mode
            if sprite_isIndexed then
              colorNext = palcols[getR(pixelNext)]
            elseif sprite_isGrayscale then
              colorNext = aseColor(0, getGA(pixelNext))
            else
              colorNext = aseColor(0, 0, 0, getA(pixelNext))
            end
        
            -- Initialize the row if it doesn't exist yet
            if not cullMap_Zf[px] then cullMap_Zf[px] = {} end
        
            -- Save the voxel visibility at this position
            cullMap_Zf[px][py] = (colorNext.alpha > 0)
          end
        
          local hasNbrB, hasNbrF = false, false
          local hasNbrL, hasNbrR = false, false
          local hasNbrU, hasNbrD = false, false

          -- cull voxels based on neighbors
          if cullVoxels then
            if cullMap_Zb[px] then
              if i > 0 then hasNbrB = cullMap_Zb[px][py] end
            end
            if cullMap_Zf[px] then
              if i < pz_max then hasNbrF = cullMap_Zf[px][py] end
            end

            if px > 0 then hasNbrL = (colors[px-1][py].alpha > 0) end
            if px < px_max then hasNbrR = (colors[px+1][py].alpha > 0) end

            if py > 0 then hasNbrU = (colors[px][py-1].alpha > 0) end
            if py < py_max then hasNbrD = (colors[px][py+1].alpha > 0) end
          end

          -- as for the unculled voxels
          if  hasNbrB and hasNbrF
          and hasNbrL and hasNbrR
          and hasNbrU and hasNbrD then goto skipPixel end
        end

        -- define new point centered
        local point = { x = px-tileWHalf,
                        y = py-tileHHalf,
                        z = i-tileDHalf }

        -- rotate voxel
        point = rotateX(point, rotX_cos, rotX_sin)
        point = rotateY(point, rotY_cos, rotY_sin)
        point = rotateZ(point, rotZ_cos, rotZ_sin)

        -- project 3d voxel to 2d plane
        point = project(point, voxelScale, halfCanvasW, halfCanvasH)

        -- submit the voxel data to the 3d table
        table.insert(voxel3d, { x = point.x, y = point.y, z = point.z,
                                color = color })

        if cullVoxels then
          if not cullMap_Zb[px] then cullMap_Zb[px] = {} end
          cullMap_Zb[px][py] = true
        end

        ::skipPixel::
      end
      ::skipTile::
    end

                                                                              --

-------: 4. clean-up data tables -----------------------------------------------

    recycleTable(palcols)
    recycleTable(cullMap_Zb)
    recycleTable(colors)
    recycleTable(cullMap_Zf)

                                                                              --

-------: 5. set-up the voxel data for rendering --------------------------------

    -- depth-sort the voxels
    table.sort( voxel3d, function(a,b) return a.z < b.z end )

                                                                              --

-------: 6. render the voxel data to the preview dialog ------------------------

    for _, voxel in ipairs( voxel3d ) do
      -- set-up voxel position and color
      if voxel_shape.width > 0 and voxel_shape.height > 0 then
        voxel_shape.x, voxel_shape.y = voxel.x - offset_x, voxel.y - offset_y

        if sprite_isGrayscale then
          local light = voxel.color.gray
          gc.color = aseColor(light,light,light,255)
        else
          gc.color = voxel.color
        end

        -- render the voxel as a gray depth map
        if voxel_isDepthMap then
          gc.color = getColorDepth(voxel.z, gc.height)
        end

        -- draw voxel as a square/rounded square/circle
        if voxel_isRounded then
          gc:beginPath()
          gc:roundedRect(voxel_shape, voxelRound, voxelRound)
          gc:fill()

          if voxel_isEdged then gc.color = color_edge; gc:stroke() end
        else
          gc:fillRect(voxel_shape)

          if voxel_isEdged then
            gc.color = color_edge;
            gc:strokeRect(voxel_shape)
          end
        end
        voxelTotal = voxelTotal+1
      end
    end
    canvasWidth, canvasHeight = gc.width, gc.height

    ::skipRender::
    renderTime = os.clock() - renderTime
  end

                                                                              --

--------------------------------------------------------------------------------
---- The Save to New Sprite Function -------------------------------------------

  local function saveSprite()
    if not voxel3d or #voxel3d == 0 then
      voxel3d = {}
      show_alert("No voxel data available.")
    else
      local srcSprite = sprite

      local newSprite = aseSprite(canvasWidth, canvasHeight)
      newSprite:setPalette(srcSprite.palettes[1])
      app.sprite   = newSprite
      local newCel = newSprite.cels[1]

      local brushType = brushCircle and (voxelRound > 0) or brushSquare
      local brush = Brush{type = brushType, size = (voxelScale + voxelOver)}
      
      app.transaction("Draw voxels to new sprite", function()
        for _, voxel in ipairs(voxel3d) do
          local color = voxel.color
          if depthMap then color = getColorDepth(voxel.z, canvasHeight) end

          app.useTool{tool="pencil",
                      brush=brush,
                      color=color,
                      points={Point(voxel.x - transX,voxel.y - transY)},
                      cel=newCel}
        end
      end)

      app.refresh()
    end
  end

                                                                              --

--------------------------------------------------------------------------------
---- The Main Script Dialog ----------------------------------------------------
-------: 1. set-up the dialog box ----------------------------------------------

  -- create main dialog window
  local stopEvents
  local dlg = Dialog { id="main", title = "aseSlab", onclose = stopEvents }
  local dlgTabsVisible = true

  -- redraws the canvas when the settings are changed --------------------------
  local function refreshCanvas()
    -- update variables from settings
    tileWidth   = dlg.data.tileWidth; tileHeight  = dlg.data.tileHeight
    tileCols    = dlg.data.tileCols;  tileRows    = dlg.data.tileRows

    voxelScale  = dlg.data.voxelScale
    voxelRound  = dlg.data.voxelRound
    voxelOver   = dlg.data.voxelOver

    rotX = dlg.data.rotX; rotY = dlg.data.rotY; rotZ = dlg.data.rotZ

    projDist  = dlg.data.projDist

    -- redraw the canvas
    dlg:repaint()
  end

  -- prepare for event listening
  local refreshOnEvent = function(ev)
    if app.sprite == sprite then refreshCanvas() end
  end

  stopEvents = function()
    app.events:off(refreshOnEvent);   sprite.events:off(refreshOnEvent)
  end

  local refreshManual = function()
    -- refresh manual values tab text boxes

    dlg:modify{ id="inVoxelScale", text=voxelScale }
    dlg:modify{ id="inVoxelOver",  text=voxelOver }
    dlg:modify{ id="inProjDist",   text=projDist }
    dlg:modify{ id="inRotX",       text=rotX }
    dlg:modify{ id="inRotY",       text=rotY }
    dlg:modify{ id="inRotZ",       text=rotZ }

    refreshCanvas()
  end

  local function dataToRot(data)
    -- convert string data to a valid rotation
    local rot = tonumber(data) + 0
    return ( (max(rotXYZ_min,min(rot,rotXYZ_max)) + 180) % 360 ) - 180
  end

  local applyManual = function()
    -- apply manual values to variables
    local newVoxelScale = tonumber( dlg.data.inVoxelScale ) + 0
    voxelScale = max(voxelScale_min, min(newVoxelScale,voxelScale_max))
    local newVoxelOver = tonumber( dlg.data.inVoxelOver ) + 0
    voxelOver  = max(voxelOver_min, min(newVoxelOver,voxelOver_max))
    local newProjDist = tonumber( dlg.data.inProjDist ) + 0
    projDist = max(projDist_min, min(newProjDist, projDist_max) )
    rotX = dataToRot(dlg.data.inRotX)
    rotY = dataToRot(dlg.data.inRotY)
    rotZ = dataToRot(dlg.data.inRotZ)

    dlg:modify{ id="voxelScale", value=voxelScale }
    dlg:modify{ id="voxelOver",  value=voxelOver }
    dlg:modify{ id="projDist",   value=projDist }
    dlg:modify{ id="rotX",       value=rotX }
    dlg:modify{ id="rotY",       value=rotY }
    dlg:modify{ id="rotZ",       value=rotZ }

    refreshCanvas()
  end

                                                                              --

-------: 2. start app refresh events -------------------------------------------

  if app.sprite == sprite then
    -- Refresh the canvas when the sprite changes
    sprite.events:on('change', refreshOnEvent )
    -- Refresh the canvas when application changes
    app.events:on('sitechange', refreshOnEvent )
    -- Refresh the canvas when the background color changes
    app.events:on('bgcolorchange', refreshOnEvent )
  end

                                                                              --

-------: 3. set-up the render preview canvas -----------------------------------

  dlg:canvas{
    id = "canvas",
    width = canvasWidth, height = canvasHeight,

    onmousedown = function(mouseEvent)
      -- start dragging mouse to change rotation values
      if mouseEvent.x < 0 and mouseEvent.y < 0 then return end

      mouseX, mouseY = mouseEvent.x, mouseEvent.y

      -- hide the cursor while clicking
      dlg:modify{ id = "canvas", mouseCursor = MouseCursor.NONE}
    end,

    onmousemove = function(mouseEvent)
      -- drag mouse to change rotation values
      if app.sprite ~= sprite then return end

      if mouseEvent.button == MouseButton.LEFT then
        transX, transY = (mouseX - mouseEvent.x ), (mouseY - mouseEvent.y)
        refreshCanvas()

      elseif mouseEvent.button == MouseButton.RIGHT then
        -- X and Y rotations
        if (mouseY == mouseEvent.y) and (mouseX == mouseEvent.x) then return end

        local rotXtarget = rotX + ( (mouseY - mouseEvent.y) * 0.125 )
        local rotYtarget = rotY + ( (mouseEvent.x - mouseX) * 0.125 )
        rotX = ( (lerp(rotX, rotXtarget, 0.9) + 180) % 360 ) - 180
        rotY = ( (lerp(rotY, rotYtarget, 0.9) + 180) % 360 ) - 180
        dlg:modify{ id = "rotX", value = rotX }
        dlg:modify{ id = "rotY", value = rotY }
        if app.sprite ~= sprite then return end
        refreshCanvas()

      elseif mouseEvent.button == MouseButton.MIDDLE then
        -- Z rotations
        if (mouseY == mouseEvent.y) then return end

        local rotZtarget = rotZ + ( (mouseY - mouseEvent.y) * 0.125 )
        rotZ = ( (lerp(rotZ, rotZtarget, 0.9) + 180) % 360 ) - 180
        dlg:modify{ id = "rotZ", value = rotZ }
        if app.sprite ~= sprite then return end
        refreshCanvas()
      end
    end,

    onmouseup = function(mouseEvent)
      -- show the mouse again after not clicking anymore
      dlg:modify{ id = "canvas", mouseCursor = MouseCursor.ARROW}
    end,

    onwheel = function(mouseEvent)
      -- resize voxels with the mouse wheel
      if mouseEvent.delta ~= 0 then
        local newVoxelScale = voxelScale - mouseEvent.deltaY
        voxelScale = max(voxelScale_min, min(newVoxelScale, voxelScale_max) )
        dlg:modify{ id = "voxelScale", value = voxelScale }

        if app.sprite ~= sprite then return end
        refreshCanvas()
      end
    end,

    onpaint = function(ev)
      -- runs the voxel renderer
      local gc = ev.context

      if app.sprite ~= sprite then goto skipRender end

      drawVoxels(gc)

      ::skipRender::
    end
  }

                                                                              --

-------: 4. set-up custom functions for the user settings ----------------------

  local function resetTransform() transX, transY = 0, 0; refreshCanvas() end

  local function setAsSprite() sprite = app.sprite; refreshCanvas() end

  local function tileSizeGrid()
    tileWidth = sprite.gridBounds.width; tileHeight = sprite.gridBounds.height
    dlg:modify{ id="tileWidth",  value = tileWidth }
    dlg:modify{ id="tileHeight", value = tileHeight }
    refreshCanvas()
  end

  local function tileSizeSel()
    local selection = sprite.selection
    if selection.isEmpty then
      show_alert("Error: No selection available to get the tile size from.")
      return
    end

    tileWidth  = selection.bounds.width
    tileHeight = selection.bounds.height
    dlg:modify{ id="tileWidth",  value = tileWidth }
    dlg:modify{ id="tileHeight", value = tileHeight }
    refreshCanvas()
  end

  local function setPersp() projMode = projType.PERSP; refreshCanvas() end

  local function setOrtho() projMode = projType.ORTHO; refreshCanvas() end

  local function resetRotation()
    rotX, rotY, rotZ = 0, 0, 0;
    dlg:modify{ id = "rotX", value = 0 }
    dlg:modify{ id = "rotY", value = 0 }
    dlg:modify{ id = "rotZ", value = 0 }
    refreshCanvas()
  end

  local function f_drawAllLayers()
    drawAllLayers = not drawAllLayers;  refreshCanvas() end

  local function f_voxelEdge() voxelEdge = not voxelEdge; refreshCanvas() end

  local function f_showBkgr() canvasBkgr = not canvasBkgr; refreshCanvas() end

  local function f_cullVoxels()
    cullVoxels = not cullVoxels; refreshCanvas() end

  local function f_depthMap() depthMap = not depthMap; refreshCanvas() end

  local function f_projInvr() projInvr = not projInvr; refreshCanvas() end

                                                                              --

-------: 5. set-up the pop-ups with helpful information ------------------------

  local onPerformance = function()
    show_alert{ title="Performance tips...",
      text={  "To ensure that the voxel rendering is as fast as possible,",
              "consider removing as many of the pixels that will not be",
              "visible on the final render.",
              "",
              "However, avoid being too aggressive, since inevitably there",
              "will be gaps between some of the voxels.",
              "",
              "The Depth Map mode may be helpful in finding gaps between",
              "voxels, so you can fill in any pixels in the tiles as needed.",
              "",
              "You may also just activate the option to hide inner voxels.",
              "However, be aware that the logic behind it is extremely brute,",
              "and actually results in slower rendering times when the",
              "voxel data is already somewhat optimized. But, in case you",
              "need it, it's there if it helps." },
      buttons={"OK I'll see what I can do!"}
    }
  end

  local onRenderAllLayers = function()
    show_alert{ title="On rendering all layers...",
      text={  "In Aseprite, most operations you do on a given sprite can ",
              "notify a script to update, except (between other things) ",
              "changing the visibility of layers.",
              "",
              "(Internally, this is referring as Sprite events.)",
              "",
              "Due to this, you will have to press Refresh Preview manually ",
              "if you hide or show any layer while rendering all layers.",
              "",
              "Feel free to contact the Aseprite developers and ask them to ",
              "add a Sprite event for when layer visibility changes. This ",
              "script will start working properly, without any changes, from ",
              "then on." },
      buttons={"I see, OK"},
    }
  end

  local onImageGone = function()
    resetTransform()
    show_alert{ title="My image is gone...",
      text={  "...and it might be because you dragged or resized the dialog.",
              "",
              "This is a known bug unrelated to this script, but resulting",
              "from how Aseprite handles dialog mouse inputs.",
              "",
              "Just press Reset View and the image should come back into view.",
              "...actually, I already pressed the button for you :)",
              "",
              "If the image doesn't reappear, try running the script again.",
              "",
              "And if THAT doesn't help at all, we have a bug in our hands.",
              "Contact me on itch.io with any information about it. Thanks!" },
        buttons={"OK thanks"}
      }
  end

  local onHideBroken = function()
    show_alert{ title="Hide Settings is broken...",
      text={  "...and it might be because you maximized the dialog box.",
              "",
              "This is a known bug related to the way Aseprite handles",
              "dialog boxes, their size and the elements inside them.",
              "",
              "Faced with the choice to remove this otherwise useful feature,",
              "or not shipping this script at all, I decided to leave it in ",
              "for now. Make sure to set-up the render before hiding the",
              "settings, and only then maximizing the window.",
              "",
              "However, feel free to contact the Aseprite developers about it.",
              "But me, I won't. At this point I expect nothing from them but",
              "plushies and new features that barely work lol and also lmao.",
              "",
              "And don't get me started with how incomplete and undocumented",
              "the whole Aseprite API is...",
              "",
              "Until then, that button will remain broken. It is what it is."},
      buttons={"OK then..."}
    }
  end

  local onPadding = function()
    show_alert{ title = "Regarding voxel padding...",
      text = {"You can pad the size of the voxels. The value can be positive",
              "or negative, down to hiding the voxels entirely.",
              "",
              "Both can be very useful: e.g.",
              "- A value of zero will make the voxels perfectly grid-aligned",
              "  in Orthographic mode, and also in the render.",
              "- A negative value will render the voxels as dots.",
              "- When the voxel shape or angle leaves gaps between voxels,",
              "  a positive value over zero can fill those gaps.",
              "- Since Perspective Mode is the default mode for viewing, and",
              "  it generally tends to leave gaps between voxels, the default",
              "  value has been set to four.",
              "",
              "Note that a negative value will not reveal any hidden voxels,",
              "if you have selected that option on the Render Settings tab.",
            },
      buttons={"OK neat!"}
    }
  end

  local getRenderInfo = function()
    local voxel_max = tileWidth * tileHeight * (tileRows * tileCols)

    show_alert{ title = "Voxel total:",
      text = {"Voxel count: " .. voxelTotal .. "/" .. voxel_max   .. " voxels",
              "Render time: " .. string.format("%.3f",renderTime) .. "ms" },
      buttons = {"Got it"},
    }
  end

                                                                              --

-------: 6. add the user settings controls -------------------------------------  
  dlg
    :tab{ text = "Preview" }
      :separator{ text="Instructions"}
      :label{   text="Left click and drag to move the model preview" }
      :label{   text="Right click and drag to rotate the model preview (X, Y)" }
      :newrow()
      :label{   text="Middle click and drag to rotate the model preview (Z)" }
      :label{   text="Use the mouse wheel to zoom (affects voxel size)" }
      :button{  text="Optimizing Performance...", onclick = onPerformance }
      :button{  text="On rendering all layers...", onclick = onRenderAllLayers }
      :button{  text="My image is gone...", onclick = onImageGone }
      :button{  text="Hide/Show Settings is broken...", onclick = onHideBroken }
      :separator{ text="Rendering"}
      :check{   text="Render all layers (flattened)",
                onclick = f_drawAllLayers }
      :button{  text="Render to new sprite",   onclick = saveSprite }
      :newrow()
    :tab{ text = "Sprite settings" }
      :separator{ text="Select sprite to render as voxels" }
        :button { text = "Set the current sprite as the render target",
                  onclick = setAsSprite }
        :button{ text="Tile size from grid", onclick = tileSizeGrid }
        :button{ text="Tile size from selection", onclick = tileSizeSel }
      :separator { text = "Tile size" }
        :slider { label = "Width, Height",
                  id = "tileWidth",   min = tileWH_min, max = tileWH_max,
                  value = tileWidth,  onchange = refreshCanvas}
        :slider { id = "tileHeight",  min = tileWH_min, max = tileWH_max,
                  value = tileHeight, onchange = refreshCanvas }
      :separator { text = "Tiles per image" }
        :slider { label = "Columns, Rows",
                  id = "tileCols",   min = tileCR_min, max = tileCR_max,
                  value = tileCols,  onchange = refreshCanvas }
        :slider { id = "tileRows",   min = tileCR_min, max = tileCR_max,
                  value = tileRows,  onchange = refreshCanvas }

    :tab{ text = "Voxel settings" }
      :separator{ text="Voxel size:" }
        :slider { id = "voxelScale", label = "Scale", value = voxelScale,
                  min = voxelScale_min, max = voxelScale_max,
                  onchange = refreshCanvas }
        :slider { id = "voxelOver",  label = "Padding", value = voxelOver,
                  min = voxelOver_min, max = voxelOver_max,
                  onchange = refreshCanvas }
        :button { text = "Regarding voxel padding...", onclick=onPadding }
      :separator{ text="Voxel shape:" }
        :slider { id = "voxelRound", label = "Roundness", value = voxelRound,
                  min = 0, max = 12, onchange = refreshCanvas }
      
    :tab{ text = "Camera settings" }
      :separator  { text = "Projection" }
        :radio{ selected = true, text = "Perspective", onclick = setPersp }
        :radio{ text = "Orthographic", onclick  = setOrtho }

      :separator { text = "Projection Distance" }
        :slider { id = "projDist", min = projDist_min, max = projDist_max,
                  value = projDist, onchange = refreshCanvas }
    
      :separator  { text = "Rotation (X,Y,Z)" }
        :slider { id = "rotY",  min = rotXYZ_min, max = rotXYZ_max,
                  value = rotY, onchange = refreshCanvas }
        :slider { id = "rotX",  min = rotXYZ_min, max = rotXYZ_max,
                  value = rotX, onchange = refreshCanvas }
        :slider { id = "rotZ",  min = rotXYZ_min, max = rotXYZ_max,
                  value = rotZ, onchange = refreshCanvas }
        :button { text = "Reset rotation", onclick = resetRotation }

    :tab{ text = "Render settings" }
      :separator{ text="Preview-only features"}
        :check{     text="Draw borders around voxels", onclick = f_voxelEdge  }
        :check{     text="Show background as secondary brush color",
                    onclick = f_showBkgr   }

      :separator{ text="Improve rendering time for unoptimized model:" }
        :check{  text="Hide inner voxels " ..
                      "(Performs worse the less voxels it draws)",
                      onclick = f_cullVoxels }
        :newrow()
      :separator{ text="Advanced features" }
        :check{  text="Show depth map. " ..
                      "Changes voxel colors to represent their distance " ..
                      "to the camera viewpoint.", onclick = f_depthMap   }
        :label{  text="Note: The depth map WILL be rendered in export!" }
        :newrow()
        :check{  text="Inverted depth projection. " .. "Useless but fun :P",
                onclick = f_projInvr }

    :tab{ text = "Manual Input", onclick = refreshManual }
      :separator{ text="Voxel size | Voxel padding" }
        :number{  id="inVoxelScale"}
        :number{  id="inVoxelOver"}
      :separator{ text="Projection Distance" }
        :number{  id="inProjDist"}
      :separator{ text="Rotation (X,Y,Z)" }
        :number{  id="inRotY"}
        :number{  id="inRotX"}
        :number{  id="inRotZ"}
      
      :modify{ id="inVoxelScale", text=voxelScale }
      :modify{ id="inVoxelOver",  text=voxelOver  }
      :modify{ id="inProjDist",   text=projDist   }
      :modify{ id="inRotX",       text=rotX       }
      :modify{ id="inRotY",       text=rotY       }
      :modify{ id="inRotZ",       text=rotZ       }

      :separator()
        :button{ text="Refresh values", onclick = refreshManual }
        :button{ text="Apply changes",  onclick = applyManual }
    :endtabs{ id = "tabs" }

    :newrow{ text="Main Menu" }
      :button{  text="Refresh preview", onclick = refreshCanvas }
      :button{  text="Hide/Show Settings", onclick = function()
        if dlgTabsVisible then
          dlg:modify{ id = "tabs", visible = false }
          dlgTabsVisible = false
        else
          dlg:modify{ id = "tabs", visible = true }
          dlgTabsVisible = true
        end
        refreshCanvas()
      end}
      :button{  text="Reset view", onclick = resetTransform }
      :button{  text="Reset rotation", onclick = resetRotation }
      :button{  text="Render to Sprite", onclick = saveSprite }
      :button{  text="Get render info", onclick = getRenderInfo }
      :button{  text="Exit", onclick = function() dlg:close() end }

                                                                              --

-------: 7. show the dialog box ------------------------------------------------
  dlg:show { wait = false }

                                                                              --

------------------------------------------------------------------------ EOF ---