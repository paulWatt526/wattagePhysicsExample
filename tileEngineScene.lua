local AnalogControlStick = require "analogControlStick"
local Composer = require "composer"
local Physics = require "physics"
local TileEngine = require "plugin.wattageTileEngine"

local scene = Composer.newScene()

-- -----------------------------------------------------------------------------------
-- This table represents a simple environment.  Replace this with
-- the model needed for your application.
-- -----------------------------------------------------------------------------------
local ENVIRONMENT = {
    {2,2,2,2,2,1,1,1,1,1,2,2,2,2,2},
    {2,2,2,2,2,1,0,0,0,1,2,2,2,2,2},
    {2,2,2,2,2,1,0,0,0,1,2,2,2,2,2},
    {2,2,2,2,2,1,0,0,0,1,2,2,2,2,2},
    {2,2,2,2,2,1,0,0,0,1,2,2,2,2,2},
    {1,1,1,1,1,1,0,0,0,1,1,1,1,1,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
    {1,1,1,1,1,1,0,0,0,1,1,1,1,1,1},
    {2,2,2,2,2,1,0,0,0,1,2,2,2,2,2},
    {2,2,2,2,2,1,0,0,0,1,2,2,2,2,2},
    {2,2,2,2,2,1,0,0,0,1,2,2,2,2,2},
    {2,2,2,2,2,1,0,0,0,1,2,2,2,2,2},
    {2,2,2,2,2,1,1,1,1,1,2,2,2,2,2},
}

local TILE_SIZE         = 32                -- Constant for the tile size
local ROW_COUNT         = #ENVIRONMENT      -- Row count of the environment
local COLUMN_COUNT      = #ENVIRONMENT[1]   -- Column count of the environment
local MAX_FORCE         = 10                -- The maximum force that will be applied to the player entity
local LINEAR_DAMPING    = 1                 -- Provides a little resistance to linear motion.

local playerCategory = {categoryBits=1, maskBits=2} -- Category for the player physics object.  Will collide with walls.
local wallCategory = {categoryBits=2, maskBits=1}   -- Category for the wall physics objects.  Will collide with players.

local tileEngine                            -- Reference to the tile engine
local lightingModel                         -- Reference to the lighting model
local tileEngineViewControl                 -- Reference to the UI view control
local controlStick                          -- Reference to the control stick
local playerSprite                          -- Reference to the player sprite
local lastTime                              -- Used to track how much time passes between frames

-- -----------------------------------------------------------------------------------
-- This will load in the example sprite sheet.  Replace this with the sprite
-- sheet needed for your application.
-- -----------------------------------------------------------------------------------
local spriteSheetInfo = require "tiles"
local spriteSheet = graphics.newImageSheet("tiles.png", spriteSheetInfo:getSheet())

-- -----------------------------------------------------------------------------------
-- A sprite resolver is required by the engine.  Its function is to create a
-- SpriteInfo object for the supplied key.  This function will utilize the
-- example sprite sheet.
-- -----------------------------------------------------------------------------------
local spriteResolver = {}
spriteResolver.resolveForKey = function(key)
    local frameIndex = spriteSheetInfo:getFrameIndex(key)
    local frame = spriteSheetInfo.sheet.frames[frameIndex]
    local displayObject = display.newImageRect(spriteSheet, frameIndex, frame.width, frame.height)
    return TileEngine.SpriteInfo.new({
        imageRect = displayObject,
        width = frame.width,
        height = frame.height
    })
end

-- -----------------------------------------------------------------------------------
-- A helper function to set up the physical environment.  This will add a static
-- box physics object for each wall tile.
-- -----------------------------------------------------------------------------------
local function addPhysicsObjectsForWalls(displayGroup, module)
    for row=1,ROW_COUNT do
        for col=1,COLUMN_COUNT do
            local value = ENVIRONMENT[row][col]
            if value == 1 then
                local displayObject = display.newRect(
                    displayGroup,
                    (col - 1) * TILE_SIZE + TILE_SIZE / 2,
                    (row - 1) * TILE_SIZE + TILE_SIZE / 2,
                    TILE_SIZE,
                    TILE_SIZE)
                displayObject.isVisible = false
                Physics.addBody(displayObject, "static", {
                    density=0.1,
                    friction=0.1,
                    filter=wallCategory
                })
                module.addPhysicsBody(displayObject)
            end
        end
    end
end

-- -----------------------------------------------------------------------------------
-- A simple helper function to add floor tiles to a layer.
-- -----------------------------------------------------------------------------------
local function addFloorToLayer(layer)
    for row=1,ROW_COUNT do
        for col=1,COLUMN_COUNT do
            local value = ENVIRONMENT[row][col]
            if value == 0 then
                layer.updateTile(
                    row,
                    col,
                    TileEngine.Tile.new({
                        resourceKey="tiles_0"
                    })
                )
            elseif value == 1 then
                layer.updateTile(
                    row,
                    col,
                    TileEngine.Tile.new({
                        resourceKey="tiles_1"
                    })
                )
            end
        end
    end
end

-- -----------------------------------------------------------------------------------
-- This is a callback required by the lighting model to determine whether a tile
-- is transparent.  In this implementation, the cells with a value of zero are
-- transparent.  The engine may ask about the transparency of tiles that are outside
-- the boundaries of our environment, so the implementation must handle these cases.
-- That is why nil is checked for in this example callback.
-- -----------------------------------------------------------------------------------
local function isTileTransparent(column, row)
    local rowTable = ENVIRONMENT[row]
    if rowTable == nil then
        return true
    end
    local value = rowTable[column]
    return value == nil or value == 0
end

-- -----------------------------------------------------------------------------------
-- This is a callback required by the lighting model to determine whether a tile
-- should be affected by ambient light.  This simple implementation always returns
-- true which indicates that all tiles are affected by ambient lighting.  If an
-- environment had a section which should not be affected by ambient lighting, this
-- callback can be used to indicate that.  For example, the environment my be
-- an outdoor environment where the ambient lighting is the sun.  A few tiles in this
-- environment may represent the inside of a cabin, and these tiles would need to
-- not be affected by ambient lighting.
-- -----------------------------------------------------------------------------------
local function allTilesAffectedByAmbient(row, column)
    return true
end

-- -----------------------------------------------------------------------------------
-- This will be called every frame.  It is responsible for setting the camera
-- positiong, updating the lighting model, rendering the tiles, and reseting
-- the dirty tiles on the lighting model.
-- -----------------------------------------------------------------------------------
local function onFrame(event)
    local camera = tileEngineViewControl.getCamera()
    local lightingModel = tileEngine.getActiveModule().lightingModel

    if lastTime ~= 0 then
        -- Determine the amount of time that has passed since the last frame and
        -- record the current time in the lastTime variable to be used in the next
        -- frame.
        local curTime = event.time
        local deltaTime = curTime - lastTime
        lastTime = curTime

        -- Get the direction vectors from the control stick
        local cappedPercentVector = controlStick.getCurrentValues().cappedDirectionVector

        -- If the control stick is currently being pressed, then apply the appropriate force
        if cappedPercentVector.x ~= nil and cappedPercentVector.y ~= nil then
            -- Determine the percent of max force to apply.  The magnitude of the vector from the
            -- conrol stick indicates the percentate of the max force to apply.
            local forceVectorX = cappedPercentVector.x * MAX_FORCE
            local forceVectorY = cappedPercentVector.y * MAX_FORCE
            -- Apply the force to the center of the player entity.
            playerSprite:applyForce(forceVectorX, forceVectorY, playerSprite.x, playerSprite.y)
        end

        -- Have the camera follow the player
        local tileXCoord = playerSprite.x / TILE_SIZE
        local tileYCoord = playerSprite.y / TILE_SIZE
        camera.setLocation(tileXCoord, tileYCoord)

        -- Update the lighting model passing the amount of time that has passed since
        -- the last frame.
        lightingModel.update(deltaTime)
    else
        -- This is the first call to onFrame, so lastTime needs to be initialized.
        lastTime = event.time

        -- This is the initial position of the camera
        camera.setLocation(7.5, 7.5)

        -- Since a time delta cannot be calculated on the first frame, 1 is passed
        -- in here as a placeholder.
        lightingModel.update(1)
    end

    -- Render the tiles visible to the passed in camera.
    tileEngine.render(camera)

    -- The lighting model tracks changes, then acts on all accumulated changes in
    -- the lightingModel.update() function.  This call resets the change tracking
    -- and must be called after lightingModel.update().
    lightingModel.resetDirtyFlags()
end

-- -----------------------------------------------------------------------------------
-- Scene event functions
-- -----------------------------------------------------------------------------------

-- create()
function scene:create( event )
    local sceneGroup = self.view

    -- Start physics
    Physics.start()
    -- This example does not want any gravity, set it to 0.
    Physics.setGravity(0,0)
    -- Set scale (determined by trial and error for what feels right)
    Physics.setScale(32)

    -- Create a group to act as the parent group for all tile engine DisplayObjects.
    local tileEngineLayer = display.newGroup()

    -- Create an instance of TileEngine.
    tileEngine = TileEngine.Engine.new({
        parentGroup=tileEngineLayer,
        tileSize=TILE_SIZE,
        spriteResolver=spriteResolver,
        compensateLightingForViewingPosition=false,
        hideOutOfSightElements=false
    })

    -- The tile engine needs at least one Module.  It can support more than
    -- one, but this template sets up only one which should meet most use cases.
    -- A module is composed of a LightingModel and a number of Layers
    -- (TileLayer or EntityLayer).  An instance of the lighting model is created
    -- first since it is needed to instantiate the Module.
    lightingModel = TileEngine.LightingModel.new({
        isTransparent = isTileTransparent,
        isTileAffectedByAmbient = allTilesAffectedByAmbient,
        useTransitioners = false,
        compensateLightingForViewingPosition = false
    })

    -- Instantiate the module.
    local module = TileEngine.Module.new({
        name="moduleMain",
        rows=ROW_COUNT,
        columns=COLUMN_COUNT,
        lightingModel=lightingModel,
        losModel=TileEngine.LineOfSightModel.ALL_VISIBLE
    })

    -- Next, layers will be added to the Module...

    -- Create a TileLayer for the floor.
    local floorLayer = TileEngine.TileLayer.new({
        rows = ROW_COUNT,
        columns = COLUMN_COUNT
    })

    -- Use the helper function to populate the layer.
    addFloorToLayer(floorLayer)

    -- It is necessary to reset dirty tile tracking after the layer has been
    -- fully initialized.  Not doing so will result in unnecessary processing
    -- when the scene is first rendered which may result in an unnecessary
    -- delay (especially for larger scenes).
    floorLayer.resetDirtyTileCollection()

    -- Add physics objects for the walls
    addPhysicsObjectsForWalls(sceneGroup, module)

    -- Add the layer to the module at index 1 (indexes start at 1, not 0).  Set
    -- the scaling delta to zero.
    module.insertLayerAtIndex(floorLayer, 1, 0)

    -- Add an entity layer for the player
    local entityLayer = TileEngine.EntityLayer.new({
        tileSize = TILE_SIZE,
        spriteResolver = spriteResolver
    })

    -- Add the player entity to the entity layer
    local entityId, spriteInfo = entityLayer.addEntity("tiles_2")

    -- Move the player entity to the center of the environment.
    entityLayer.centerEntityOnTile(entityId, 8, 8)

    -- Store a reference to the player entity sprite.  It will be
    -- used to apply forces to and to align the camera with.
    playerSprite = spriteInfo.imageRect

    -- Make the player sprite a physical entity
    Physics.addBody(playerSprite, "dynamic", {
        density=1,
        friction=0.5,
        bounce=0.2,
        radius=12,
        filter= playerCategory
    })

    -- Handle the player sprite as a bullet to prevent passing through walls
    -- when moving very quickly.
    playerSprite.isBullet = true

    -- This will prevent the player from "sliding" too much.
    playerSprite.linearDamping = LINEAR_DAMPING

    -- Add the entity layer to the module at index 2 (indexes start at 1, not 0).  Set
    -- the scaling delta to zero.
    module.insertLayerAtIndex(entityLayer, 2, 0)

    -- Add the module to the engine.
    tileEngine.addModule({module = module})

    -- Set the module as the active module.
    tileEngine.setActiveModule({
        moduleName = "moduleMain"
    })

    -- To render the tiles to the screen, create a ViewControl.  This example
    -- creates a ViewControl to fill the entire screen, but one may be created
    -- to fill only a portion of the screen if needed.
    tileEngineViewControl = TileEngine.ViewControl.new({
        parentGroup = sceneGroup,
        centerX = display.contentCenterX,
        centerY = display.contentCenterY,
        pixelWidth = display.actualContentWidth,
        pixelHeight = display.actualContentHeight,
        tileEngineInstance = tileEngine
    })

    -- Finally, set the ambient light to white light with medium-high intensity.
    lightingModel.setAmbientLight(1,1,1,0.7)

    local radius = 150
    controlStick = AnalogControlStick.new({
        parentGroup = sceneGroup,
        centerX = display.screenOriginX + radius,
        centerY = display.screenOriginY + display.viewableContentHeight - radius,
        centerDotRadius = 0.1 * radius,
        outerCircleRadius = radius
    })
end


-- show()
function scene:show( event )
    local sceneGroup = self.view
    local phase = event.phase

    if ( phase == "will" ) then
        -- Code here runs when the scene is still off screen (but is about to come on screen)

        -- Set the lastTime variable to 0.  This will indicate to the onFrame event handler
        -- that it is the first frame.
        lastTime = 0

        -- Register the onFrame event handler to be called before each frame.
        Runtime:addEventListener( "enterFrame", onFrame )
    elseif ( phase == "did" ) then
        -- Code here runs when the scene is entirely on screen
    end
end


-- hide()
function scene:hide( event )
    local sceneGroup = self.view
    local phase = event.phase

    if ( phase == "will" ) then
        -- Code here runs when the scene is on screen (but is about to go off screen)

        -- Remove the onFrame event handler.
        Runtime:removeEventListener( "enterFrame", onFrame )
    elseif ( phase == "did" ) then
        -- Code here runs immediately after the scene goes entirely off screen
    end
end


-- destroy()
function scene:destroy( event )

    local sceneGroup = self.view
    -- Code here runs prior to the removal of scene's view

    -- Destroy the tile engine instance to release all of the resources it is using
    tileEngine.destroy()
    tileEngine = nil

    -- Destroy the ViewControl to release all of the resources it is using
    tileEngineViewControl.destroy()
    tileEngineViewControl = nil

    controlStick.destroy()
    controlStick = nil

    -- Set the reference to the lighting model to nil.
    lightingModel = nil
end


-- -----------------------------------------------------------------------------------
-- Scene event function listeners
-- -----------------------------------------------------------------------------------
scene:addEventListener( "create", scene )
scene:addEventListener( "show", scene )
scene:addEventListener( "hide", scene )
scene:addEventListener( "destroy", scene )
-- -----------------------------------------------------------------------------------

return scene