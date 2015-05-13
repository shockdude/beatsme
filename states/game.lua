local util = require "lib.util"
local state = {}

-- function state:run(filename)
--     if love.filesystem.isFile("delaytest.txt") then
--         local delay = love.filesystem.read("delaytest.txt")
--         gamestate.switch(self, tonumber(delay), filename)
--     else
--         gamestate.switch(states.delaytest, function(delay)
--             love.filesystem.write("delaytest.txt", tostring(delay))
--             gamestate.switch(self, delay, filename)
--         end)
--     end
-- end

function state:init()
    self.fonts = {
        normal = love.graphics.getFont(),
        combo = love.graphics.newFont(24)
    }
end

function state:enter(previous, filename, song, data, delay)
    self.filename = filename
    self.song = love.filesystem.load(filename)()
    self.delay = delay

    self.modifier = 1
    -- self.cheapstart = 256
    self.startTimer = 3
    self.fade = 0
    self.score = 0
    self.combo = 0
    self.rewind = false
    self.noteUsed = {}
    self.laneUsed = {
        [1] = false,
        [2] = false,
        [3] = false
    }

    self.faderErrorAccum = 0
    self.faderPointCount = 0
    self.faderPointTime = 0
    self.faderAnimLeft  = 1
    self.faderAnimRight = 0
    self.messageText = ""
    self.messageTime = 0
    self.shakeHit = 0
    self.shakeMiss = 0
    self.hitEffects = {}
    self.laneFillAnim = {
        [1] = 0,
        [2] = 0,
        [3] = 0
    }

    -- self.audioData = love.sound.newSoundData("songs/" .. self.song.audio)
    self.audioData = data
    self.audioSource = love.audio.newSource(self.audioData)
end

function state:getCurrentPosition()
    local time = self.audioSource:tell("seconds") - self.startTimer - (self.song.offset or 0)
    return time / (1 / (self.song.bpm / 60))
end

function state:getMultiplier()
    return math.min(4, 1 + math.floor(self.combo / 8))
end

function state:increaseCombo()
    self.combo = self.combo + 1

    if self.combo > 0 and self.combo % 50 == 0 then
        self.messageTime = 2
        self.messageText = self.combo .. " note streak!"
    end

    if self.combo > 0 and self.combo % 60 == 0 then
        self.rewind = true

        self.messageTime = 2
        self.messageText = "Rewind ready!"
    end
end

function state:noteHit(note, offset)
    self.shakeHit = math.min(1, self.shakeHit + 0.3)

    self.score = self.score + 100 * self:getMultiplier()
    self:increaseCombo()

    if note[2] == 1 or note[2] == 2 then
        self.laneUsed[1] = true
    elseif note[2] == 4 or note[2] == 5 then
        self.laneUsed[3] = true
    elseif note[2] == 3 then
        self.laneUsed[2] = true
    end

    table.insert(self.hitEffects, {0, note[2]})
end

function state:noteMiss(note)
    if self.combo > 0 then
        self.shakeMiss = 1
    end

    self.combo = 0

    if note[2] == 1 or note[2] == 2 then
        self.laneUsed[1] = false
    elseif note[2] == 4 or note[2] == 5 then
        self.laneUsed[3] = false
    elseif note[2] == 3 then
        self.laneUsed[2] = false
    end
end

function state:setFade(offset)
    self.fade = math.max(-1, math.min(1, offset))
end

function state:lanePressed(lane)
    local position = self:getCurrentPosition()

    for i, note in ipairs(self.song.notes) do
        local offset = note[1] - position

        if offset > 0.5 then
            break
        end

        if note[2] == lane and not self.noteUsed[note] then
            self.noteUsed[note] = true
            self:noteHit(note, offset)
            break
        end
    end
end

function state:laneReleased(lane)
end

function state:activateEuphoria()
end

function state:keypressed(key, unicode)
    if key == "escape" then
        gamestate.push(states.pause)
    elseif key == "kp1" or key == "," then
        self:lanePressed(self.fade == -1 and 1 or 2)
    elseif key == "kp2" or key == "." then
        self:lanePressed(3)
    elseif key == "kp3" or key == "/" then
        self:lanePressed(self.fade == 1 and 5 or 4)
    elseif key == "kpenter" or key == "application" then
        self:activateEuphoria()
    end
end

function state:keyreleased(key, unicode)
    if key == "kp1" then
        self:laneReleased(self.fade == -1 and 1 or 2)
    elseif key == "kp2" then
        self:laneReleased(3)
    elseif key == "kp3" then
        self:laneReleased(self.fade == 1 and 5 or 4)
    end
end

function state:gamepadpressed(joystick, key)
    if key == "x" then
        self:lanePressed(self.fade == -1 and 1 or 2)
    elseif key == "a" then
        self:lanePressed(3)
    elseif key == "b" then
        self:lanePressed(self.fade == 1 and 5 or 4)
    elseif key == "y" then
        self:activateEuphoria()
    end
end

function state:gamepadreleased(joystick, key)
    if key == "start" then
        gamestate.push(states.pause)
    elseif key == "x" then
        self:laneReleased(self.fade == -1 and 1 or 2)
    elseif key == "a" then
        self:laneReleased(3)
    elseif key == "b" then
        self:laneReleased(self.fade == 1 and 5 or 4)
    end
end

function state:isLanePressed(lane)
    local joystick = love.joystick.getJoysticks()[1]

    if lane == 1 then
        return love.keyboard.isDown("kp1") or (joystick and joystick:isGamepadDown("x"))
    elseif lane == 2 then
        return love.keyboard.isDown("kp2") or (joystick and joystick:isGamepadDown("a"))
    elseif lane == 3 then
        return love.keyboard.isDown("kp3") or (joystick and joystick:isGamepadDown("b"))
    end
end

function state:update(dt)
    dt = dt * self.modifier

    for i=1, 3 do
        if self.laneUsed[i] then
            self.laneFillAnim[i] = math.min(1, self.laneFillAnim[i] + dt)
        else
            self.laneFillAnim[i] = 0
        end
    end

    local position = self:getCurrentPosition()

    -- Handle proper fading
    local fade = 0
    local time = 0

    for i, entry in ipairs(self.song.lanes) do
        if entry[1] < position then
            fade = entry[2]
        end
    end

    self.correctFade = fade

    if fade ~= 0 then
        -- Give points
        self.faderPointTime = self.faderPointTime - dt

        while self.faderPointTime <= 0 do
            if self.fade == fade then
                self.score = self.score + 10 * self:getMultiplier()
                self.faderPointCount = self.faderPointCount + 1

                if self.faderPointCount == 5 then
                    self:increaseCombo()
                    self.faderPointCount = 0
                end
            end

            self.faderPointTime = self.faderPointTime + 0.2
        end

        -- Drop combo
        if self.fade == fade then
            self.faderErrorAccum = math.max(0, self.faderErrorAccum - dt)
        else
            self.faderErrorAccum = self.faderErrorAccum + dt
            local threshold = 1 / (self.song.bpm / 60) / self.modifier * 2

            if self.faderErrorAccum > threshold then
                self.faderErrorAccum = 0
                self.combo = 0
            end
        end
    end

    if self.messageTime > 0 then
        self.messageTime = math.max(0, self.messageTime - dt)
    end

    local joystick = love.joystick:getJoysticks()[1]
    local i = 1

    while i <= #self.hitEffects do
        local t = self.hitEffects[i][1] + dt

        if t >= 1 then
            table.remove(self.hitEffects, i)
        else
            self.hitEffects[i][1] = t
            i = i + 1
        end
    end

    if self.shakeHit > 0 then
        self.shakeHit = math.max(self.shakeHit - dt, 0)
    end

    if self.shakeMiss > 0 then
        self.shakeMiss = math.max(self.shakeMiss - dt / 2, 0)
    end

    local started = true
    local spinning = false

    if self.startTimer > 0 then
        self.startTimer = self.startTimer - dt

        if self.startTimer <= 0 then
            self.audioSource:play()
            self.audioSource:setPitch(self.modifier)

            if self.cheapstart then
                self.audioSource:seek(self.cheapstart * (1 / (self.song.bpm / 60)))
            end

            self.startTimer = 0
        else
            started = false
        end
    end

    -- Update stick control
    -- joystick = nil

    local isSpinning = false
    local spinAngle

    if joystick then
        if started then
            -- Spin to win
            local rx = joystick:getGamepadAxis("rightx")
            local ry = joystick:getGamepadAxis("righty")

            local rd = math.min(1, math.sqrt(rx^2 + ry^2))
            local rt = math.atan2(ry / rd, rx / rd)

            isSpinning = rd > 0.34
            spinAngle = rt

            -- if rd > 0.34 then
            --     if self.lastSpinAngle then
            --         local delta = rt - self.lastSpinAngle
            --
            --         if delta > math.pi then
            --             delta = delta - math.pi * 2
            --         elseif delta < -math.pi then
            --             delta = delta + math.pi * 2
            --         end
            --
            --         -- print(delta)
            --         local scrobble = (delta / math.pi) * 4
            --         local target = self.audioSource:tell("seconds") + scrobble
            --         local limit = self.audioData:getDuration("seconds")
            --         self.audioSource:seek(math.max(0, math.min(limit, target)))
            --
            --         -- Try to revive some notes
            --         if delta < 0 then
            --             local newNoteUsed = {}
            --             local position = self:getCurrentPosition()
            --
            --             for note in pairs(self.noteUsed) do
            --                 local offset = note[1] - position
            --
            --                 if offset < 0 then
            --                     newNoteUsed[note] = true
            --                 end
            --             end
            --
            --             self.noteUsed = newNoteUsed
            --         end
            --     end
            --
            --     self.lastSpinAngle = rt
            --     self.audioSource:pause()
            --
            --     spinning = true
            -- else
            --     self.lastSpinAngle = nil
            --     self.audioSource:play()
            -- end
        end

        -- Crossfading
        local x = joystick:getGamepadAxis("leftx")
        local fade

        if x < -1/3 then
            fade = -1
        elseif x > 1/3 then
            fade = 1
        else
            fade = 0
        end

        if fade ~= self.fade then
            self:setFade(fade)
        end

        joystick:setVibration(self.shakeMiss, self.shakeHit)
    else
        local fade = 0

        if love.keyboard.isDown("z") then
            fade = fade - 1
        end

        if love.keyboard.isDown("x") then
            fade = fade + 1
        end

        if fade ~= self.fade then
            self:setFade(fade)
        end

        local rx = 0
        local ry = 0

        if love.keyboard.isDown("a") then rx = rx - 1 end
        if love.keyboard.isDown("d") then rx = rx + 1 end
        if love.keyboard.isDown("w") then ry = ry - 1 end
        if love.keyboard.isDown("s") then ry = ry + 1 end

        local rd = math.min(1, math.sqrt(rx^2 + ry^2))
        local rt = math.atan2(ry / rd, rx / rd)

        isSpinning = rd > 0.34
        spinAngle = rt
    end

    if started then
        if isSpinning then
            if self.lastSpinAngle then
                local delta = spinAngle - self.lastSpinAngle

                if delta > math.pi then
                    delta = delta - math.pi * 2
                elseif delta < -math.pi then
                    delta = delta + math.pi * 2
                end

                local scrobble = (delta / math.pi) * 4
                local target = self.audioSource:tell("seconds") + scrobble
                local limit = self.audioData:getDuration("seconds")
                self.audioSource:seek(math.max(0, math.min(limit, target)))

                -- Try to revive some notes
                if delta < 0 then
                    local newNoteUsed = {}
                    local position = self:getCurrentPosition()

                    for note in pairs(self.noteUsed) do
                        local offset = note[1] - position

                        if offset < 0 then
                            newNoteUsed[note] = true
                        end
                    end

                    self.noteUsed = newNoteUsed
                end
            end

            self.lastSpinAngle = spinAngle
            self.audioSource:pause()

            spinning = true
        else
            self.lastSpinAngle = nil
            self.audioSource:play()
        end
    end

    local targetAnimLeft = self.fade == -1 and 0 or 1
    local targetAnimRight = self.fade == 1 and 1 or 0
    local animChange = dt / 0.1

    if self.faderAnimLeft < targetAnimLeft then
        self.faderAnimLeft = math.min(targetAnimLeft, self.faderAnimLeft + animChange)
    elseif self.faderAnimLeft > targetAnimLeft then
        self.faderAnimLeft = math.max(targetAnimLeft, self.faderAnimLeft - animChange)
    end

    if self.faderAnimRight < targetAnimRight then
        self.faderAnimRight = math.min(targetAnimRight, self.faderAnimRight + animChange)
    elseif self.faderAnimRight > targetAnimRight then
        self.faderAnimRight = math.max(targetAnimRight, self.faderAnimRight - animChange)
    end

    -- Check for missed notes
    if started and not spinning then
        for i, note in ipairs(self.song.notes) do
            local offset = note[1] - position

            if offset >= -0.5 then
                break
            end

            if not self.noteUsed[note] then
                self.noteUsed[note] = true
                self:noteMiss(note)
            end
        end
    end

    love.graphics.setBackgroundColor(100, 100, 100)
end

local BEAT_SCALE = 64

local function draw_fader_back(x, y)
    love.graphics.setColor( 50,  50,  50)
    love.graphics.circle("fill", x,      y, 24)
    love.graphics.circle("fill", x + 64, y, 24)
    love.graphics.setColor(150, 150, 150)
    love.graphics.circle("line", x,      y, 24)
    love.graphics.circle("line", x + 64, y, 24)
    love.graphics.setColor( 50,  50,  50)
    love.graphics.rectangle("fill", x, y - 24, 64, 48)
    love.graphics.setColor(150, 150, 150)
    love.graphics.line(x, y - 24, x + 64, y - 24)
    love.graphics.line(x, y + 24, x + 64, y + 24)
end

local function draw_button(x, y, color, dot)
    dot = dot or {130, 130, 130}
    color = color or {255, 255, 255}

    love.graphics.setColor(color[1] * 0.2, color[2] * 0.2, color[3] * 0.2)
    love.graphics.circle("fill", x, y, 20)
    love.graphics.setColor(color[1] * 0.8, color[2] * 0.8, color[3] * 0.8)
    love.graphics.circle("line", x, y, 20)
    love.graphics.setColor(dot[1], dot[2], dot[3])
    love.graphics.circle("fill", x, y, 6)
end

function state:draw()
    local width, height = love.graphics.getDimensions()
    local position = self:getCurrentPosition()

    love.graphics.setFont(self.fonts.normal)
    love.graphics.setColor(255, 255, 255)
    -- love.graphics.print(math.floor(position * 4) / 4, 2, 2)

    local x = width / 2
    local y = height - 64

    local lanes = {
        [1] = x - 128,
        [2] = x - 64,
        [3] = x,
        [4] = x + 64,
        [5] = x + 128
    }

    local colors = {
        [1] = {127, 255,  50},
        [2] = {255,  50,  50},
        [3] = {  0, 127, 255},
    }

    local colorsByLane = {
        [1] = colors[1],
        [2] = colors[1],
        [3] = colors[2],
        [4] = colors[3],
        [5] = colors[3]
    }

    -- Find line segments for left and right lanes
    local vertices_left  = {lanes[2], y}
    local vertices_mid   = {lanes[3], y, lanes[3], 0}
    local vertices_right = {lanes[4], y}

    local i = 1

    local last_offset = 0
    local last_fading = 0

    while i <= #self.song.lanes do
        local offset = self.song.lanes[i][1] - position
        local fading = self.song.lanes[i][2]

        if y - offset * BEAT_SCALE < 0 then
            break
        end

        if offset <= 0 then
            vertices_left  = {lanes[fading == -1 and 1 or 2], y}
            vertices_right = {lanes[fading ==  1 and 5 or 4], y}
        elseif offset > 0 then
            -- Do we need to shift insert a point in the left lane?
            if (last_fading == -1 and fading ~= -1) or (last_fading ~= -1 and fading == -1) then
                table.insert(vertices_left,  lanes[last_fading == -1 and 1 or 2])
                table.insert(vertices_left,  y - offset * BEAT_SCALE)
                table.insert(vertices_left,  lanes[     fading == -1 and 1 or 2])
                table.insert(vertices_left,  y - offset * BEAT_SCALE)
            end

            if (last_fading ==  1 and fading ~=  1) or (last_fading ~=  1 and fading ==  1) then
                table.insert(vertices_right, lanes[last_fading ==  1 and 5 or 4])
                table.insert(vertices_right, y - offset * BEAT_SCALE)
                table.insert(vertices_right, lanes[     fading ==  1 and 5 or 4])
                table.insert(vertices_right, y - offset * BEAT_SCALE)
            end
        end

        last_offset = offset
        last_fading = fading

        i = i + 1
    end

    table.insert(vertices_left,  lanes[last_fading == -1 and 1 or 2])
    table.insert(vertices_left,  0)
    table.insert(vertices_right, lanes[last_fading ==  1 and 5 or 4])
    table.insert(vertices_right, 0)

    -- Get your wiggle game on
    if (self.correctFade == -1 and self.fade ~= -1) or (self.correctFade ~= -1 and self.fade == -1) then
        vertices_left = util.undulo(vertices_left)
    end

    if (self.correctFade == 1 and self.fade ~= 1) or (self.correctFade ~= 1 and self.fade == 1) then
        vertices_right = util.undulo(vertices_right)
    end

    love.graphics.push()
    love.graphics.translate((love.math.random() - 0.5) * self.shakeMiss * 4, 0)

    -- Draw scratchboard
    love.graphics.setColor(30, 30, 30)
    love.graphics.rectangle("fill", x - 192, 0, 384, height)

    -- Draw beat lines
    local beatX1 = x - 192
    local beatX2 = x + 192

    love.graphics.setColor(255, 255, 255, 20)
    love.graphics.setLineWidth(1)

    love.graphics.push()
    love.graphics.translate(0, -BEAT_SCALE * (1 - (position - math.floor(position))))

    for i=0, height / BEAT_SCALE do
        love.graphics.line(beatX1, height - i * BEAT_SCALE, beatX2, height - i * BEAT_SCALE)
    end

    love.graphics.pop()

    -- Draw combo steps
    for i=1, 7 do
        if self.combo >= 24 or self.combo % 8 >= i then
            love.graphics.setColor(200, 100, 30)
        else
            love.graphics.setColor(50, 50, 60)
        end

        love.graphics.rectangle("fill", x + 168, y - 64 - i * 12, 16, 8)
        love.graphics.setColor(255, 255, 255, 10)
        love.graphics.rectangle("fill", x + 168, y - 64 - i * 12, 16, 4)
    end

    if self.combo >= 8 then
        local mult = math.min(4, 1 + math.floor(self.combo / 8))
        love.graphics.setFont(self.fonts.combo)
        love.graphics.setColor(60, 60, 60)
        love.graphics.printf("x" .. mult, x + 119, y - 64 - 7 * 12 - 36, 64, "right")
        love.graphics.setColor(200, 100, 30)
        love.graphics.printf("x" .. mult, x + 120, y - 64 - 7 * 12 - 35, 64, "right")
    end

    if self.rewind then
        love.graphics.setFont(self.fonts.normal)
        love.graphics.setColor(60, 60, 60)
        love.graphics.printf("REWIND", x + 119, y - 64 - 7 * 12 - 36 - 24, 64, "right")
        love.graphics.setColor(200, 100, 30)
        love.graphics.printf("REWIND", x + 120, y - 64 - 7 * 12 - 35 - 24, 64, "right")
    end

    -- Draw controls for fading and notes
    love.graphics.setLineWidth(2)
    draw_fader_back(lanes[1], y)
    draw_fader_back(lanes[4], y)
    draw_button(lanes[1] + self.faderAnimLeft  * 64, y, self:isLanePressed(1) and colors[1], self.laneUsed[1] and colors[1])
    draw_button(lanes[3]                           , y, self:isLanePressed(2) and colors[2], self.laneUsed[2] and colors[2])
    draw_button(lanes[4] + self.faderAnimRight * 64, y, self:isLanePressed(3) and colors[3], self.laneUsed[3] and colors[3])

    -- Draw lanes
    local beat_strength = 1 - (position / 2 - math.floor(position / 2))
    beat_strength = beat_strength ^ 2

    love.graphics.setLineWidth(2)
    love.graphics.setColor(127, 127, 127)
    love.graphics.line(vertices_mid)
    if self.laneFillAnim[2] > 0 then
        love.graphics.setLineWidth(2 + 2 * beat_strength)
        love.graphics.setColor(colors[2])
        love.graphics.line(util.cutLine(vertices_mid, self.laneFillAnim[2]))
    end

    love.graphics.setLineWidth(2)
    love.graphics.setColor(127, 127, 127)
    love.graphics.line(vertices_left)
    if self.laneFillAnim[1] > 0 then
        love.graphics.setLineWidth(2 + 2 * beat_strength)
        love.graphics.setColor(colors[1])
        love.graphics.line(util.cutLine(vertices_left, self.laneFillAnim[1]))
    end

    love.graphics.setLineWidth(2)
    love.graphics.setColor(127, 127, 127)
    love.graphics.line(vertices_right)
    if self.laneFillAnim[3] > 0 then
        love.graphics.setLineWidth(2 + 2 * beat_strength)
        love.graphics.setColor(colors[3])
        love.graphics.line(util.cutLine(vertices_right, self.laneFillAnim[3]))
    end

    -- Draw notes
    for i, note in ipairs(self.song.notes) do
        local offset = note[1] - position

        if note[3] then
            local last = offset + note[3]

            if last >= 0 then
                local color = colorsByLane[note[2]]
                local length = note[3]

                if offset < 0 then
                    length = length + offset
                    offset = 0
                end

                love.graphics.setColor(color[1] * 0.65, color[2] * 0.65, color[3] * 0.65)
                love.graphics.circle("fill", lanes[note[2]], y - last * BEAT_SCALE, 16, 32)
                love.graphics.setColor(color[1] * 0.10, color[2] * 0.10, color[3] * 0.10)
                love.graphics.circle("line", lanes[note[2]], y - last * BEAT_SCALE, 16, 32)
                love.graphics.setColor(color[1] * 0.65, color[2] * 0.65, color[3] * 0.65)
                love.graphics.rectangle("fill", lanes[note[2]] - 16, y - last * BEAT_SCALE, 32, length * BEAT_SCALE)
                love.graphics.setColor(color[1] * 0.10, color[2] * 0.10, color[3] * 0.10)
                love.graphics.line(lanes[note[2]] - 16, y - last * BEAT_SCALE, lanes[note[2]] - 16, y - offset * BEAT_SCALE)
                love.graphics.line(lanes[note[2]] + 16, y - last * BEAT_SCALE, lanes[note[2]] + 16, y - offset * BEAT_SCALE)
                love.graphics.setColor(color[1] * 0.65, color[2] * 0.65, color[3] * 0.65)
                love.graphics.circle("fill", lanes[note[2]], y - offset * BEAT_SCALE, 16, 32)
                love.graphics.setColor(color[1] * 0.10, color[2] * 0.10, color[3] * 0.10)
                love.graphics.circle("line", lanes[note[2]], y - offset * BEAT_SCALE, 16, 32)
            end
        elseif not self.noteUsed[note] and offset >= 0 then
            local color = colorsByLane[note[2]]

            love.graphics.setColor(color[1] * 0.65, color[2] * 0.65, color[3] * 0.65)
            love.graphics.circle("fill", lanes[note[2]], y - offset * BEAT_SCALE, 16, 32)
            love.graphics.setColor(color[1] * 0.10, color[2] * 0.10, color[3] * 0.10)
            love.graphics.circle("line", lanes[note[2]], y - offset * BEAT_SCALE, 16, 32)
        end
    end

    love.graphics.pop()

    -- Score..
    love.graphics.setFont(self.fonts.combo)
    love.graphics.setColor(0, 0, 0)
    love.graphics.print(util.addSeparators(self.score), 71, 47)
    love.graphics.setColor(255, 255, 255)
    love.graphics.print(util.addSeparators(self.score), 72, 48)

    -- Draw hit effects
    love.graphics.setLineWidth(4)

    for i, effect in ipairs(self.hitEffects) do
        local color = colorsByLane[effect[2]]
        local radius = 16 + 12 * effect[1]
        love.graphics.setColor(color[1], color[2], color[3], 255 * (1 - effect[1]))
        love.graphics.circle("line", lanes[effect[2]], y, radius, radius * 2)
    end

    if self.messageTime > 0 then
        local fade = self.messageTime <= 0.5 and self.messageTime / 0.5 or 1

        love.graphics.setColor(255, 255, 255, 255 * fade)
        love.graphics.setFont(self.fonts.combo)
        love.graphics.printf(self.messageText, 128, height / 3 - 24, width - 256, "center")
    end

    -- Draw song title & author
    if self.startTimer > 0 then
        local fade = math.min(1, self.startTimer)

        love.graphics.setColor(0, 0, 0, 50 * fade)
        love.graphics.rectangle("fill", 128, height / 3 - 24 - 8, width - 256, 56)

        love.graphics.setColor(255, 255, 255, 255 * fade)
        love.graphics.setFont(self.fonts.combo)
        love.graphics.printf(self.song.title .. " - " .. self.song.author, 128, height / 3 - 24, width - 256, "center")
    end

    -- Draw subtitles
    local subtitle_y = y + 30
    love.graphics.setFont(self.fonts.normal)
    love.graphics.setColor(255, 255, 255)

    for i, entry in ipairs(self.song.subtitles) do
        if position < entry[1] then
            break
        end

        if position < entry[1] + entry[3] then
            love.graphics.printf(entry[2], x - 192, subtitle_y, 384, "center")
            subtitle_y = subtitle_y + 18
        end
    end
end

return state