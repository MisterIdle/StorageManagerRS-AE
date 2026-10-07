local version = "10.4 - AE2 Control Panel"
dofile("/usr/apis/touchpoint.lua")

local me, mon
local sizex, sizey
local t

local currentState = "MENU"

local THEMES = {
    MENU    = { main = colors.red,   text = colors.white },
    ITEMS   = { main = colors.orange, text = colors.white },
    DISQUES = { main = colors.blue, text = colors.white },
    CRAFTS  = { main = colors.lime,   text = colors.white }
}

local allItems = {}
local allCells = {}
local allCPUs = {}
local energy, maxEnergy, energyUsage = 0, 1, 0
local totalItemUsed, totalItemMax, totalItemsCount = 0, 0, 0
local totalFluidUsed, totalFluidMax = 0, 0

local currentPage = 1
local totalPages = 1
local itemsPerPage = 3

local function formatBytes(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    if bytes >= 1024 * 1024 * 1024 then return string.format("%.1f GB", bytes / (1024 * 1024 * 1024))
    elseif bytes >= 1024 * 1024 then return string.format("%.1f MB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then return string.format("%.1f KB", bytes / 1024)
    else return math.floor(bytes) .. " B" end
end

local function formatNumber(num)
    if not num then return "0" end
    if num >= 1000000000 then return string.format("%.1fG", num / 1000000000)
    elseif num >= 1000000 then return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then return string.format("%.1fK", num / 1000)
    else 
        if num == math.floor(num) then return tostring(num)
        else return string.format("%.1f", num) end
    end
end

local function cleanName(raw)
    raw = raw:gsub("^.+:", ""):gsub("_", " "):gsub("%[", ""):gsub("%]", "")
    return raw:sub(1,1):upper() .. raw:sub(2)
end

local function getDisplayName(item)
    if not item then return "Inconnu" end
    if item.displayName then return cleanName(item.displayName)
    elseif item.name then return cleanName(item.name) end
    return "Objet"
end

local function drawHorizontalChart(x, y, w, h, themeMain, title, percent, textLeft, textRight, barColor)
    mon.setBackgroundColor(themeMain)
    
    mon.setCursorPos(x, y)
    mon.write(string.rep(" ", w))
    
    mon.setCursorPos(x, y + h - 1)
    mon.write(string.rep(" ", w))
    
    for i = 1, h - 2 do
        mon.setCursorPos(x, y + i)
        mon.write(" ")
        mon.setCursorPos(x + w - 1, y + i)
        mon.write(" ")
    end
    
    mon.setBackgroundColor(colors.black)

    mon.setCursorPos(x + 2, y)
    mon.setTextColor(colors.white)
    mon.write(" " .. title .. " ")
    
    local barY = y + 2
    mon.setCursorPos(x + 2, barY)
    local barW = w - 4 
    percent = math.max(0, math.min(100, percent))
    local filled = math.floor((percent / 100) * barW)
    
    if filled > 0 then
        mon.setBackgroundColor(barColor)
        mon.write(string.rep(" ", filled))
    end
    if barW - filled > 0 then
        mon.setBackgroundColor(colors.gray)
        mon.write(string.rep(" ", barW - filled))
    end
    mon.setBackgroundColor(colors.black)
    
    local textY = y + 4
    mon.setCursorPos(x + 2, textY)
    mon.setTextColor(colors.lightGray)
    mon.write(textLeft)
    
    if textRight then
        local rightPos = x + w - 2 - string.len(textRight)
        mon.setCursorPos(rightPos, textY)
        mon.setTextColor(themeMain)
        mon.write(textRight)
    end
end

local function drawListFrame(x, y, w, h, themeMain, title)
    mon.setBackgroundColor(themeMain)
    
    mon.setCursorPos(x, y - 1)
    mon.write(string.rep(" ", w))
    
    mon.setCursorPos(x, y + h - 1)
    mon.write(string.rep(" ", w))
    
    for i = 1, h - 1 do
        mon.setCursorPos(x, y - 1 + i)
        mon.write(" ")
        mon.setCursorPos(x + w - 1, y - 1 + i)
        mon.write(" ")
    end
    
    mon.setBackgroundColor(colors.black)
    
    if title then
        mon.setCursorPos(x + 2, y - 1)
        mon.setTextColor(colors.white)
        mon.write(" " .. title .. " ")
    end
end

local function updateData()
    if not me then return end
    
    pcall(function() energy = me.getStoredEnergy() or energy end)
    pcall(function() maxEnergy = me.getEnergyCapacity() or maxEnergy end)
    pcall(function() energyUsage = me.getEnergyUsage() or energyUsage end)

    local okI, rawItems = pcall(function() return me.getItems({}) end)
    allItems = {}
    totalItemsCount = 0
    if okI and rawItems and type(rawItems) == "table" then
        for _, item in pairs(rawItems) do
            local count = item.count or item.amount or 0
            item.realCount = count
            totalItemsCount = totalItemsCount + count
            table.insert(allItems, item)
        end
        table.sort(allItems, function(a, b) return a.realCount > b.realCount end)
    end

    local okC2, cells = pcall(function() return me.getCells() end)
    allCells = {}
    local itemCells = {}
    local fluidCells = {}
    totalItemUsed, totalItemMax = 0, 0
    totalFluidUsed, totalFluidMax = 0, 0

    if okC2 and cells and type(cells) == "table" then
        for _, cell in pairs(cells) do
            local name = getDisplayName(cell.item or cell)
            local used = cell.usedBytes or cell.used or cell.storedBytes or 0
            local total = cell.bytes or cell.capacity or cell.maxBytes or cell.totalBytes or 0
            local isFluid = string.find(string.lower(name), "fluid") or string.find(string.lower(name), "infinity") or (cell.type and string.find(string.lower(cell.type), "fluid"))
            local isInfinite = (used == 0 and total == 0) or (isFluid and total == 0)
            
            local cData = { name = name, used = used, total = total, isFluid = isFluid, isInfinite = isInfinite }
            
            if isFluid then
                table.insert(fluidCells, cData)
                if not isInfinite then
                    totalFluidUsed = totalFluidUsed + used
                    totalFluidMax = totalFluidMax + total
                end
            else
                table.insert(itemCells, cData)
                if not isInfinite then
                    totalItemUsed = totalItemUsed + used
                    totalItemMax = totalItemMax + total
                end
            end
        end
        table.sort(itemCells, function(a, b) return a.used > b.used end)
        table.sort(fluidCells, function(a, b) return a.used > b.used end)

        if #itemCells > 0 then
            for _, c in ipairs(itemCells) do table.insert(allCells, c) end
        end
        if #fluidCells > 0 then
            for _, c in ipairs(fluidCells) do table.insert(allCells, c) end
        end
    end

    local okCPU, cpus = pcall(function() return me.getCraftingCPUs() end)
    allCPUs = {}
    if okCPU and cpus and type(cpus) == "table" then
        for _, cpu in pairs(cpus) do
            table.insert(allCPUs, cpu)
        end
    end
end

local function pageNext()
    if currentPage < totalPages then currentPage = currentPage + 1; drawDisplay() end
end

local function pagePrev()
    if currentPage > 1 then currentPage = currentPage - 1; drawDisplay() end
end

local function switchState(newState)
    currentState = newState
    currentPage = 1
    
    t = touchpoint.new(peripheral.getName(mon))
    
    local btnY = sizey - 1
    local startX = 2
    local endX = sizex - 2
    local usableW = endX - startX + 1
    
    local w1 = startX + math.floor(usableW * 0.25)
    local w2 = startX + math.floor(usableW * 0.50)
    local w3 = startX + math.floor(usableW * 0.75)
    
    local function btnColor(state)
        return currentState == state and THEMES[state].main or colors.gray
    end
    local function txtColor(state)
        return currentState == state and colors.black or colors.white
    end

    t:add("MENU",    function() switchState("MENU") end,    startX, btnY, w1 - 1,   btnY, btnColor("MENU"),    txtColor("MENU"))
    t:add("ITEMS",   function() switchState("ITEMS") end,   w1,     btnY, w2 - 1,   btnY, btnColor("ITEMS"),   txtColor("ITEMS"))
    t:add("DISQUES", function() switchState("DISQUES") end, w2,     btnY, w3 - 1,   btnY, btnColor("DISQUES"), txtColor("DISQUES"))
    t:add("CRAFTS",  function() switchState("CRAFTS") end,  w3,     btnY, endX,     btnY, btnColor("CRAFTS"),  txtColor("CRAFTS"))

    if currentState ~= "MENU" then
        local th = THEMES[currentState].main
        t:add("<", pagePrev, sizex - 7, 2, sizex - 5, 2, th, colors.black)
        t:add(">", pageNext, sizex - 4, 2, sizex - 2, 2, th, colors.black)
    end
    
    drawDisplay()
end

function drawDisplay()
    if not mon then return end
    mon.setBackgroundColor(colors.black)
    mon.clear()

    local theme = THEMES[currentState]

    if currentState == "MENU" then
        local h = 6
        local totalHeight = (h * 3) + 2
        local startY = math.floor((sizey - totalHeight) / 2)
        local startX = 3 
        local chartW = sizex - 5
        
        local y1 = startY
        local pctE = maxEnergy > 0 and math.floor((energy / maxEnergy) * 100) or 0
        local txtUse = formatNumber(energyUsage) .. " AE/t "
        drawHorizontalChart(startX, y1, chartW, h, THEMES.MENU.main, "ENERGIE", pctE, (pctE .. "% "), txtUse, colors.red)

        local y2 = y1 + h + 1
        local itemPct = totalItemMax > 0 and math.floor((totalItemUsed / totalItemMax) * 100) or 0
        local txtItems = formatNumber(totalItemsCount) .. " pcs "
        drawHorizontalChart(startX, y2, chartW, h, THEMES.ITEMS.main, "STOCK ITEMS", itemPct, (itemPct .. "% "), txtItems, colors.orange)

        local y3 = y2 + h + 1
        local fluidPct = totalFluidMax > 0 and math.floor((totalFluidUsed / totalFluidMax) * 100) or 0
        local txtFluids = formatBytes(totalFluidUsed) .. " "
        drawHorizontalChart(startX, y3, chartW, h, THEMES.DISQUES.main, "STOCK FLUIDES", fluidPct, (fluidPct .. "% "), txtFluids, colors.cyan)

    else
        local dataList = {}
        local frameTitle = ""
        
        if currentState == "ITEMS" then 
            dataList = allItems; frameTitle = "INVENTAIRE"
        elseif currentState == "DISQUES" then 
            dataList = allCells; frameTitle = "DISQUES"
        elseif currentState == "CRAFTS" then
            dataList = allCPUs; frameTitle = "CPUS"
        end

        local startX = 3
        local listW = sizex - 4 
        local availY = sizey - 4 

        itemsPerPage = math.max(1, math.floor((availY - 2) / 2))
        totalPages = math.ceil(#dataList / itemsPerPage)

        if totalPages == 0 then totalPages = 1 end
        if currentPage > totalPages then currentPage = totalPages end

        drawListFrame(startX, 2, listW, availY, theme.main, frameTitle)

        local startIdx = (currentPage - 1) * itemsPerPage + 1
        local endIdx = math.min(startIdx + itemsPerPage - 1, #dataList)

        local y = 3
        
        for i = startIdx, endIdx do
            if y <= sizey - 3 then
                local entry = dataList[i]
                mon.setCursorPos(startX + 2, y)

                if currentState == "ITEMS" then
                    local name = i .. ". " .. getDisplayName(entry)
                    local count = formatNumber(entry.realCount) .. " "
                    local maxNameLen = math.max(2, listW - string.len(count) - 2)
                    
                    mon.setTextColor(colors.white)
                    mon.write(string.sub(name, 1, maxNameLen))
                    
                    mon.setCursorPos(startX + listW - 2 - string.len(count), y)
                    mon.setTextColor(colors.lime)
                    mon.write(count)

                elseif currentState == "DISQUES" then
                    if entry.isHeader then
                        mon.setTextColor(colors.yellow)
                        mon.write(entry.name)
                    else
                        local info
                        if entry.isInfinite then
                            info = "INFINI "
                        else
                            info = string.format("%s/%s ", formatBytes(entry.used), formatBytes(entry.total))
                        end
                        local maxNameLen = math.max(2, listW - string.len(info) - 3)
                        
                        mon.setTextColor(entry.isFluid and colors.cyan or colors.white)
                        mon.write(string.sub(entry.name, 1, maxNameLen))
                        
                        mon.setCursorPos(startX + listW - 1 - string.len(info), y)
                        mon.setTextColor(colors.lightGray)
                        mon.write(info)
                    end

                elseif currentState == "CRAFTS" then
                    local cpuName = "CPU #" .. i
                    local status = entry.isBusy and "[ACTIF] " or "[LIBRE] "
                    
                    mon.setTextColor(colors.yellow)
                    mon.write(cpuName)
                    
                    mon.setCursorPos(startX + listW - 1 - string.len(status), y)
                    mon.setTextColor(entry.isBusy and colors.lime or colors.gray)
                    mon.write(status)
                    
                    if entry.isBusy then
                        local craftName = "Processus en cours..."
                        if entry.craftingJob then craftName = getDisplayName(entry.craftingJob)
                        elseif entry.activeCrafting then craftName = getDisplayName(entry.activeCrafting)
                        end
                        
                        mon.setCursorPos(startX + 2, y + 1)
                        mon.setTextColor(colors.lightGray)
                        mon.write("-> " .. string.sub(craftName, 1, listW - 5))
                    end
                end
                y = y + 2
            end
        end
        
        if #dataList == 0 then
            mon.setCursorPos(startX + 2, 3)
            mon.setTextColor(colors.gray)
            mon.write("Aucune donnee.")
        end
    end
    t:draw()
end

local function init()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then mon = peripheral.wrap(name) break end
    end
    if not mon then error("Moniteur introuvable !") end

    mon.setTextScale(1.0)
    sizex, sizey = mon.getSize()

    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        if pType and (pType == "me_bridge" or pType:find("bridge")) then me = peripheral.wrap(name) break end
    end
    if not me then error("ME Bridge introuvable !") end

    updateData()
    switchState("MENU")
end

init()

local timer = os.startTimer(3)
while true do
    local event = {os.pullEvent()}
    
    if event[1] == "timer" and event[2] == timer then
        updateData()
        drawDisplay()
        timer = os.startTimer(3)
    elseif event[1] == "me_inventory" or event[1] == "me_crafting" then
        updateData()
        drawDisplay()
    end

    local touchEvent = {t:handleEvents(unpack(event))}
    if touchEvent[1] == "button_click" and t.buttonList[touchEvent[2]] then
        t.buttonList[touchEvent[2]].func()
    end
end