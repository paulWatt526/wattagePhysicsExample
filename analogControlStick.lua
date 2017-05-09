local TileEngine = require "plugin.wattageTileEngine"
local Utils = TileEngine.Utils

-- Localize external function calls.
local sqrt = math.sqrt

local AnalogControlStick = {}
AnalogControlStick.new = function(params)
    Utils.requireParams({
        "parentGroup",
        "centerX",
        "centerY",
        "centerDotRadius",
        "outerCircleRadius"
    },params)

    local self = {}

    local touchId                                       -- Used to set touch focus on the control stick
    local centerDot                                     -- The center of the control stick
    local outerCircle                                   -- The outer circle of the control stick
    local outerCircleRadius = params.outerCircleRadius  -- private variable to store the outer circle radius

    -- Vector whose magnitude is a percentage of the radius from the center dot.  For example, if the outer
    -- ring of the control is touched, this vector would have a magnitude of 1, representing 100% of the radius.
    -- If the control was touched half way between the center dot and the outer ring, this vector would have a
    -- magnitude of 0.5 representing 50%.  If the touch point moves outside the radius, the value will be
    -- greater than 1 representing a value greater than 100%.  This can be used like a throttle control by
    -- setting an entity's velocity to a percentage of the max velocity.
    local currentRawDirectionVectorX
    local currentRawDirectionVectorY

    -- Same as currentRawDirectionVector except it is capped at 1 (or 100%).
    local currentDirectionVectorX
    local currentDirectionVectorY

    local function calculateDirectionVectors(x, y)
        -- Create vector for the control center point
        local centerPointVectorX = centerDot.x
        local centerPointVectorY = centerDot.y

        -- Create vector for the touch point
        local touchPointVectorX = x
        local touchPointVectorY = y

        -- Subtract the center vector from the touch point vector to get the control direction vector.
        local vectorToTouchPointX = touchPointVectorX - centerPointVectorX
        local vectorToTouchPointY = touchPointVectorY - centerPointVectorY

        -- Determine the magnitude of the vector
        local magnitude = math.sqrt(
            vectorToTouchPointX * vectorToTouchPointX + vectorToTouchPointY * vectorToTouchPointY)

        -- Determine the magnitude's percent of the outer circle radius
        local percent = magnitude / outerCircleRadius

        -- Store the capped percent.  This will result in any value greater than 1 being set to 1 instead.
        local cappedPercent = math.min(percent, 1)

        -- Calculates the vector where magnitude is the distance from the center dot represented as a
        -- percentage of the outer ring radius as described in the variable's declaration.
        currentRawDirectionVectorX = vectorToTouchPointX / magnitude * percent
        currentRawDirectionVectorY = vectorToTouchPointY / magnitude * percent

        -- Calculates the vector where magnitude is the distance from the center dot represented as a
        -- percentage of the outer ring radius and capped at 1 (100%) as described in the variable's declaration.
        currentDirectionVectorX = vectorToTouchPointX / magnitude * cappedPercent
        currentDirectionVectorY = vectorToTouchPointY / magnitude * cappedPercent
    end

    -- Handle for touch events
    local function touchHandler(event)
        -- If the control is already focused on a touch and this touch
        -- is not the current touch, exit early.
        if touchId ~= nil and touchId ~= event.id then
            return false
        end

        if event.phase == "began" then
            -- Touch has began

            -- Store the ID of the touch
            touchId = event.id

            -- Set the focus of the current touch to this control exclusively.
            display.getCurrentStage():setFocus(outerCircle, touchId)

            -- calculate the direction vectors
            calculateDirectionVectors(event.x, event.y)
        elseif event.phase == "moved" then
            -- Touch has moved

            -- calculate the direction vectors
            calculateDirectionVectors(event.x, event.y)
        elseif event.phase == "ended" or event.phase == "cancelled" then
            -- Touch has ended or was cancelled

            -- Remove the focus
            display.getCurrentStage():setFocus(outerCircle, nil)

            -- Clear the touchID
            touchId = nil

            -- Set direction vectors to nil
            currentRawDirectionVectorX = nil
            currentRawDirectionVectorY = nil
            currentDirectionVectorX = nil
            currentDirectionVectorY = nil
        end

        -- Indicate that the touch was handled by returning true
        return true
    end

    -- Return both the raw and capped vector values
    function self.getCurrentValues()
        return {
            cappedDirectionVector = {x = currentDirectionVectorX, y = currentDirectionVectorY},
            rawDirectionVector = {x = currentRawDirectionVectorX, y = currentRawDirectionVectorY}
        }
    end

    -- Perform cleanup of resources allocated by this class
    function self.destroy()
        outerCircle:removeEventListener("touch", touchHandler)
        display.getCurrentStage():setFocus(outerCircle, nil)
        outerCircle:removeSelf()
        outerCircle = nil

        centerDot:removeSelf()
        centerDot = nil
    end

    -- Initiallizes the managed resources
    local function initialize()
        centerDot = display.newCircle(
            params.parentGroup,
            params.centerX,
            params.centerY,
            params.centerDotRadius
        )
        centerDot:setFillColor(1,1,1,1)
        centerDot:setStrokeColor(1,1,1,1)
        centerDot.strokeWidth = 1
        centerDot.alpha = 0.25

        outerCircle = display.newCircle(
            params.parentGroup,
            params.centerX,
            params.centerY,
            params.outerCircleRadius
        )
        outerCircle:setFillColor(1,1,1,1)
        outerCircle.alpha = 0.25

        outerCircle:addEventListener("touch", touchHandler)
    end

    initialize()

    return self
end

return AnalogControlStick