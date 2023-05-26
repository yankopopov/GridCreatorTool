-- Constants
local TILE_HEIGHT = 5
local TILE_WIDTH = TILE_HEIGHT * 2
local BUTTON_HEIGHT = 20
local BUTTON_FONT_SIZE = 8
local BUTTON_FILL_COLOR = {0.5, 0.5, 0.5}

-- Variable declarations
local json = require("json")
local tfd = require("plugin.tinyfiledialogs")
local lfs = require("lfs")
local grid, lastTile, mouseDown, makePassable
local tilesToFlip, lastTouchX, lastTouchY, overlayImage
local gridArray = {}
local gridHistory = {}
local moveGridMode = false
local moveImageMode = false
local gridXOffset = 0
local gridYOffset = 0

-- Function definitions
local loadGridFromFile, loadImageFromFile, createTile, createIsometricGrid, createGrid, gridToGridArray, saveGridToFile
local onButtonTouch, button, buttonText, instructionsVisible

-- Create display groups
local backGroup = display.newGroup()  -- This will contain the grid and image
local frontGroup = display.newGroup()  -- This will contain the buttons


loadGridFromFile = function() 
    local path = tfd.openFileDialog{
        title = "Load Grid",
        initialPath = "grid.json",
        filter_patterns = {"*.json", ".json"},
        filter_description = "JSON file",
        allow_multiple_selects = false
    }
    if path then
        local file, errorString = io.open(path, "r")
        if file then
            local contents = file:read("*a")
            io.close(file)
            local gridArray = json.decode(contents)
            return gridArray
        else
            print("File error: " .. errorString)
        end
    end
    return nil
end

local function moveImage(event)
    if not overlayImage then
        print("No image loaded to move.")
        return
    end

    if moveImageMode then
        local phase = event.phase
        local target = overlayImage

        if "began" == phase then
            display.getCurrentStage():setFocus(target)
            target.isFocus = true
            target.markX = target.x
            target.markY = target.y
        elseif target.isFocus then
            if "moved" == phase then
                local x = (event.x - event.xStart) + target.markX
                local y = (event.y - event.yStart) + target.markY
                target.x, target.y = x, y  -- move the image
            elseif "ended" == phase or "cancelled" == phase then
                display.getCurrentStage():setFocus(nil)
                target.isFocus = false
            end
        end
        return true
    end
end

loadImageFromFile = function() 
    local path = tfd.openFileDialog{
        title = "Load Image",
        initialPath = lfs.currentdir(),
        filter_patterns = {"*.png", "*.jpg", "*.jpeg"},
        filter_description = "Image file",
        allow_multiple_selects = false
    }
    if path then
        local filename = path:match("([^/]+)$")  -- extract the filename from the path
        local destPath = system.pathForFile(filename, system.TemporaryDirectory)
        
        -- Use LFS to copy the file
        local sourceFile, error = io.open(path, "rb")
        if error then 
            print("Could not open source file: " .. error)
            return
        end
        local content = sourceFile:read("*a")
        sourceFile:close()

        local destFile, error = io.open(destPath, "wb")
        if error then 
            print("Could not open destination file: " .. error)
            return
        end
        destFile:write(content)
        destFile:close()

        -- Now load the image from the destination path
        if overlayImage then
            overlayImage:removeEventListener("touch", moveImage)  -- remove the listener
            overlayImage:removeSelf()
            overlayImage = nil
        end
        overlayImage = display.newImage(filename, system.TemporaryDirectory)
        if overlayImage then
            overlayImage.x = display.contentCenterX
            overlayImage.y = display.contentCenterY
            overlayImage.alpha = 0.5
            overlayImage.isHitTestable = moveImageMode
            overlayImage:addEventListener("touch", moveImage)  -- add the listener
            backGroup:insert(overlayImage)  -- Insert the overlayImage into the backGroup
        else
            print("Error loading image: " .. path)
        end
        
    end
end

createTile = function(x, y, isPassable, i, j) 
    local vertices = {0, -TILE_HEIGHT / 2, -TILE_WIDTH / 2, 0, 0, TILE_HEIGHT / 2, TILE_WIDTH / 2, 0}
    local tile = display.newPolygon(x, y, vertices)
    tile.isPassable = isPassable
    tile.gridPosition = {i, j}
    tile:setFillColor(isPassable and 0.5 or 1)
    
    function tile:touch(event)
        if moveGridMode then
            if event.phase == "began" then
                lastTouchX = event.x
                lastTouchY = event.y
            elseif event.phase == "moved" then
                local dx = event.x - lastTouchX
                local dy = event.y - lastTouchY
                gridXOffset = gridXOffset + dx
                gridYOffset = gridYOffset + dy
                for i = 1, #grid do
                    for j = 1, #grid[i] do
                        local tile = grid[i][j]
                        tile.x = tile.x + dx
                        tile.y = tile.y + dy
                    end
                end
                lastTouchX = event.x
                lastTouchY = event.y
            end
        else
            if event.phase == "began" or (event.phase == "moved" and mouseDown) then
                if self ~= lastTile then
                    if not mouseDown then
                        -- If the mouse was just clicked down, save the current grid state before editing it
                        table.insert(gridHistory, gridToGridArray(grid))
                        print("inserted!")
                    end
                    self.isPassable = makePassable
                    tile:setFillColor(self.isPassable and 0.5 or 1)
                    lastTile = self
        
                    if tilesToFlip > 1 then
                        local i, j = self.gridPosition[1], self.gridPosition[2]
                        for di = -tilesToFlip + 1, tilesToFlip - 1 do
                            for dj = -tilesToFlip + 1, tilesToFlip - 1 do
                                local tile = grid[i + di] and grid[i + di][j + dj]
                                if tile then
                                    tile.isPassable = self.isPassable
                                    tile:setFillColor(tile.isPassable and 0.5 or 1)
                                end
                            end
                        end
                    end
                end
                mouseDown = true
            elseif event.phase == "ended" or event.phase == "cancelled" then
                lastTile = nil
                mouseDown = false
            end
        end
        return true
    end
    tile:addEventListener("touch")
    return tile
end

createIsometricGrid = function(gridArray) 
    local grid = {}
    local offsetX = display.contentCenterX
    local offsetY = display.contentCenterY
    for i, row in ipairs(gridArray) do
        grid[i] = {}
        for j, isPassable in ipairs(row) do
            local x = (j - i) * TILE_WIDTH / 2 + offsetX
            local y = (j + i) * TILE_HEIGHT / 2 + offsetY
            grid[i][j] = createTile(x, y, isPassable == 1, i, j)
        end
    end
    return grid
end

createGrid = function(width, height) 
    local gridArray = {}
    for i = 1, height do
        gridArray[i] = {}
        for j = 1, width do
            gridArray[i][j] = 1
        end
    end
    return gridArray
end

gridToGridArray = function(grid) 
    local gridArray = {}
    for i = 1, #grid do
        gridArray[i] = {}
        for j = 1, #grid[i] do
            gridArray[i][j] = grid[i][j].isPassable and 1 or 0
        end
    end
    return gridArray
end

saveGridToFile = function(gridArray, filename) 
    local path = tfd.saveFileDialog{
        title = "Save Grid",
        default_path_and_file = "grid.json",
        filter_patterns = "*.json",
        filter_description = ".json file"
    }
    if path then
        local file = io.open(path, "w")
        if file then
            file:write(json.encode(gridArray))
            file:close()
        end
    end
end

local function createButton(x, y, text, touchFunction)
    local buttonGroup = display.newGroup()

    -- Create a rectangle for the button
    local rect = display.newRect(buttonGroup, 0, 0, (#text*3.5) + 8, BUTTON_HEIGHT)
    rect:setFillColor(unpack(BUTTON_FILL_COLOR))

    -- Create a text for the button
    local buttonText = display.newText(buttonGroup, text, 0, 0, native.systemFont, BUTTON_FONT_SIZE)
    buttonText:setFillColor(1)

    -- Position the text at the center of the rectangle
    buttonText.x = rect.x
    buttonText.y = rect.y
    buttonGroup.text = buttonText

    -- Position the button group at the specified coordinates
    buttonGroup.x = x
    buttonGroup.y = y

    -- Function to handle button press
    function buttonGroup:touch(event)
        if event.phase == "began" then
            touchFunction(buttonGroup)
        end
        return true
    end
    buttonGroup:addEventListener("touch")
    frontGroup:insert(buttonGroup)
    return buttonGroup, buttonText
end

-- Set initial state
tilesToFlip = 1
local function onEditRadiusButtonTouch(button)
        tilesToFlip = tilesToFlip % 3 + 1  -- cycles through the values 1, 2, 3
        button.text.text = tostring(tilesToFlip)
end
makePassable = false
local function onPassableButtonTouch(button)
        makePassable = not makePassable
        button.text.text = "Passable: " .. tostring(makePassable)
end
local function insertGridToBack(grid) 
    for i = 1, #grid do
        for j = 1, #grid[i] do
            backGroup:insert(grid[i][j])
        end
    end
end
local function onLoadButtonTouch(button)
    local gridArray = loadGridFromFile()
    if gridArray then
        for i = 1, #grid do
            for j = 1, #grid[i] do
                grid[i][j]:removeSelf()
            end
        end
        grid = createIsometricGrid(gridArray)
        insertGridToBack(grid)
    end
end
local function onSaveButtonTouch(button)
        saveGridToFile(gridToGridArray(grid), "grid.json")
end
local function onImageButtonTouch(button)
    loadImageFromFile()
end
local function onMoveGridButtonTouch(button)
        moveGridMode = not moveGridMode
        button.text.text = "Move Grid: " .. tostring(moveGridMode)
end
local function onMoveImageButtonTouch(button)
        if overlayImage then
            moveImageMode = not moveImageMode
            overlayImage.isHitTestable = moveImageMode
            button.text.text = "Move Image: " .. tostring(moveImageMode)
        else
            print("No image loaded to move.")
        end
end
local function onIncreaseSizeButtonTouch(button)
    if overlayImage then
        overlayImage.xScale = overlayImage.xScale * 1.1
        overlayImage.yScale = overlayImage.yScale * 1.1
    else
        print("No image loaded to resize.")
    end
end

local function onDecreaseSizeButtonTouch(button)
    if overlayImage then
        overlayImage.xScale = overlayImage.xScale / 1.1
        overlayImage.yScale = overlayImage.yScale / 1.1
    else
        print("No image loaded to resize.")
    end
end

createButton(10, 0, tostring(tilesToFlip), onEditRadiusButtonTouch)
createButton(50, 0, "Passable: " .. tostring(makePassable), onPassableButtonTouch)
createButton(100, 0, "Load", onPassableButtonTouch)
createButton(124, 0, "Save", onSaveButtonTouch)
createButton(164, 0, "Load Image", onImageButtonTouch)
createButton(230, 0, "Move Grid: " .. tostring(moveGridMode), onMoveGridButtonTouch)
createButton(300, 0, "Move Image: " .. tostring(moveImageMode), onMoveImageButtonTouch)
createButton(370, 0, "+", onIncreaseSizeButtonTouch)
createButton(390, 0, "-", onDecreaseSizeButtonTouch)


gridArray = createGrid(50, 50)
grid = createIsometricGrid(gridArray)
insertGridToBack(grid)


local function onKeyEvent(event)
    if event.keyName == "z" and event.phase == "down" then
        if #gridHistory > 0 then
            -- Get the previous grid state
            local gridArray = table.remove(gridHistory)
            -- Clear the current grid
            for i = 1, #grid do
                for j = 1, #grid[i] do
                    grid[i][j]:removeSelf()
                end
            end
            -- Create the grid from the previous state
            grid = createIsometricGrid(gridArray)
            insertGridToBack(grid)
            for i = 1, #grid do
                for j = 1, #grid[i] do
                    local tile = grid[i][j]
                    tile.x = tile.x + gridXOffset
                    tile.y = tile.y + gridYOffset
                end
            end
        end
        return true
    end
    return false
end
Runtime:addEventListener("key", onKeyEvent)