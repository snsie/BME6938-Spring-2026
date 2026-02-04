-- Snake + Power-ups (LÖVE2D)
-- Beginner-friendly single-file implementation.

-- =====================
-- Constants / Settings
-- =====================
local WINDOW_W, WINDOW_H = 800, 600
local CELL = 20

local GRID_COLS = math.floor(WINDOW_W / CELL)
local GRID_ROWS = math.floor(WINDOW_H / CELL)

local START_MOVES_PER_SEC = 8
local MAX_MOVES_PER_SEC = 18
local SPEEDUP_PER_FOOD = 0.35

local FOOD_POINTS = 10

local POWERUP_MAX_ON_BOARD = 2
local POWERUP_SPAWN_EVERY_SEC = 8
local POWERUP_DESPAWN_AFTER_SEC = 14

local POWERUP_DURATION_SPEED_SEC = 6
local POWERUP_DURATION_DOUBLE_SEC = 8
local POWERUP_SPEED_MULT = 1.6

local COLORS = {
	bg = { 0.06, 0.07, 0.09 },
	gridA = { 0.09, 0.10, 0.13 },
	gridB = { 0.07, 0.08, 0.10 },
	snakeHead = { 0.30, 0.92, 0.45 },
	snakeBody = { 0.20, 0.70, 0.35 },
	food = { 0.95, 0.30, 0.35 },
	ui = { 0.92, 0.92, 0.94 },
	uiDim = { 0.70, 0.72, 0.78 },
	warn = { 0.98, 0.85, 0.25 },
	puSpeed = { 0.35, 0.65, 0.98 },
	puShield = { 0.98, 0.82, 0.30 },
	puDouble = { 0.80, 0.45, 0.98 },
}

local STATE = {
	start = "start",
	playing = "playing",
	paused = "paused",
	gameover = "gameover",
}

-- =====================
-- Game State
-- =====================
local game = {
	state = STATE.start,
	score = 0,
	best = 0,
	moveTimer = 0,
	pulseT = 0,
	shakeT = 0,
	shakeMag = 0,
}

local snake = {
	body = {}, -- list of {x,y}, head at index 1
	dir = { x = 1, y = 0 },
	nextDir = { x = 1, y = 0 },
	canTurn = true, -- prevents multiple direction changes within the same tick
	grow = 0,
}

local food = { x = 0, y = 0 }

-- Power-ups on the board: list of { kind, x, y, ttl }
local powerups = {}

-- Active power-ups: map kind -> { remaining=sec, charges=int }
local active = {}

local powerupSpawnTimer = 0

-- =====================
-- Helpers
-- =====================
local function clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local function cellKey(x, y)
	return tostring(x) .. "," .. tostring(y)
end

local function isOpposite(a, b)
	return a.x == -b.x and a.y == -b.y
end

local function inBounds(x, y)
	return x >= 1 and x <= GRID_COLS and y >= 1 and y <= GRID_ROWS
end

local function startShake(seconds, magnitude)
	game.shakeT = math.max(game.shakeT, seconds)
	game.shakeMag = math.max(game.shakeMag, magnitude)
end

local function randomEmptyCell(avoidFoodAndPowerups)
	-- Build a set of occupied cells (snake + optionally food + powerups).
	local occupied = {}
	for i = 1, #snake.body do
		local s = snake.body[i]
		occupied[cellKey(s.x, s.y)] = true
	end

	if avoidFoodAndPowerups then
		occupied[cellKey(food.x, food.y)] = true
		for i = 1, #powerups do
			local p = powerups[i]
			occupied[cellKey(p.x, p.y)] = true
		end
	end

	local freeCount = GRID_COLS * GRID_ROWS - 0
	for _ in pairs(occupied) do
		freeCount = freeCount - 1
	end
	if freeCount <= 0 then
		return nil
	end

	-- Try random picks first (fast, simple).
	for _ = 1, 400 do
		local x = love.math.random(1, GRID_COLS)
		local y = love.math.random(1, GRID_ROWS)
		if not occupied[cellKey(x, y)] then
			return { x = x, y = y }
		end
	end

	-- Fallback: deterministic scan.
	for y = 1, GRID_ROWS do
		for x = 1, GRID_COLS do
			if not occupied[cellKey(x, y)] then
				return { x = x, y = y }
			end
		end
	end

	return nil
end

local function placeFood()
	local pos = randomEmptyCell(true)
	if not pos then
		-- Board is full: win condition / graceful end.
		game.state = STATE.gameover
		return false
	end
	food.x, food.y = pos.x, pos.y
	return true
end

local function addPowerup(kind)
	local pos = randomEmptyCell(true)
	if not pos then
		return false
	end

	powerups[#powerups + 1] = {
		kind = kind,
		x = pos.x,
		y = pos.y,
		ttl = POWERUP_DESPAWN_AFTER_SEC,
	}
	return true
end

local function trySpawnPowerup()
	if #powerups >= POWERUP_MAX_ON_BOARD then
		return
	end

	-- Weighted random: speed-up slightly more common.
	local r = love.math.random()
	if r < 0.45 then
		addPowerup("speed")
	elseif r < 0.75 then
		addPowerup("shield")
	else
		addPowerup("double")
	end
end

local function resetGame()
	game.state = STATE.playing
	game.score = 0
	game.moveTimer = 0
	game.pulseT = 0
	game.shakeT = 0
	game.shakeMag = 0

	snake.body = {}
	snake.dir = { x = 1, y = 0 }
	snake.nextDir = { x = 1, y = 0 }
	snake.canTurn = true
	snake.grow = 0

	-- Spawn snake near center.
	local cx = math.floor(GRID_COLS / 2)
	local cy = math.floor(GRID_ROWS / 2)
	snake.body[1] = { x = cx, y = cy }
	snake.body[2] = { x = cx - 1, y = cy }
	snake.body[3] = { x = cx - 2, y = cy }

	powerups = {}
	active = {}
	powerupSpawnTimer = 0

	placeFood()
end

local function movesPerSecond()
	local base = START_MOVES_PER_SEC + (game.score / FOOD_POINTS) * SPEEDUP_PER_FOOD
	base = clamp(base, START_MOVES_PER_SEC, MAX_MOVES_PER_SEC)

	-- Active speed boost multiplies speed.
	local speedEffect = active.speed and active.speed.remaining and active.speed.remaining > 0
	if speedEffect then
		base = base * POWERUP_SPEED_MULT
	end

	return base
end

local function tickDuration()
	return 1 / movesPerSecond()
end

local function applyPowerup(kind)
	if kind == "shield" then
		active.shield = active.shield or { charges = 0 }
		active.shield.charges = (active.shield.charges or 0) + 1
		startShake(0.12, 3)
		return
	end

	if kind == "speed" then
		active.speed = { remaining = POWERUP_DURATION_SPEED_SEC }
		startShake(0.15, 4)
		return
	end

	if kind == "double" then
		active.double = { remaining = POWERUP_DURATION_DOUBLE_SEC }
		startShake(0.15, 4)
		return
	end
end

local function hasShield()
	return active.shield and (active.shield.charges or 0) > 0
end

local function consumeShield()
	if not hasShield() then
		return false
	end
	active.shield.charges = active.shield.charges - 1
	startShake(0.20, 6)
	return true
end

local function scoreMultiplier()
	if active.double and active.double.remaining and active.double.remaining > 0 then
		return 2
	end
	return 1
end

local function updateActiveTimers(dt)
	-- Only runs while playing (pause freezes timers by design).
	for _, k in ipairs({ "speed", "double" }) do
		if active[k] and active[k].remaining then
			active[k].remaining = math.max(0, active[k].remaining - dt)
			if active[k].remaining <= 0 then
				active[k] = nil
			end
		end
	end
end

local function updatePowerupsOnBoard(dt)
	for i = #powerups, 1, -1 do
		powerups[i].ttl = powerups[i].ttl - dt
		if powerups[i].ttl <= 0 then
			table.remove(powerups, i)
		end
	end
end

local function checkSelfCollision(x, y)
	for i = 1, #snake.body do
		local s = snake.body[i]
		if s.x == x and s.y == y then
			return true
		end
	end
	return false
end

local function setNextDirection(dx, dy)
	local candidate = { x = dx, y = dy }
	if not snake.canTurn then
		return
	end
	if isOpposite(candidate, snake.dir) then
		return
	end
	snake.nextDir = candidate
	snake.canTurn = false
end

local function stepSnakeOnce()
	-- Apply queued direction at the start of the tick.
	snake.dir = { x = snake.nextDir.x, y = snake.nextDir.y }
	local head = snake.body[1]
	local nx = head.x + snake.dir.x
	local ny = head.y + snake.dir.y

	-- Wall collision (classic: game over).
	if not inBounds(nx, ny) then
		if consumeShield() then
			-- Shield saves you: cancel this move (stay in place this tick).
			return
		end
		game.state = STATE.gameover
		game.best = math.max(game.best, game.score)
		return
	end

	-- Self collision.
	if checkSelfCollision(nx, ny) then
		if consumeShield() then
			-- Shield saves you: cancel this move.
			return
		end
		game.state = STATE.gameover
		game.best = math.max(game.best, game.score)
		return
	end

	-- Move: add new head.
	table.insert(snake.body, 1, { x = nx, y = ny })

	-- Power-up pickup.
	for i = #powerups, 1, -1 do
		local p = powerups[i]
		if p.x == nx and p.y == ny then
			applyPowerup(p.kind)
			table.remove(powerups, i)
			break
		end
	end

	-- Food.
	if nx == food.x and ny == food.y then
		snake.grow = snake.grow + 1
		game.score = game.score + FOOD_POINTS * scoreMultiplier()
		startShake(0.10, 2)
		placeFood()
	else
		-- Normal movement: remove tail unless we're growing.
		if snake.grow > 0 then
			snake.grow = snake.grow - 1
		else
			table.remove(snake.body, #snake.body)
		end
	end
end

-- =====================
-- LÖVE Callbacks
-- =====================
function love.load()
	love.window.setMode(WINDOW_W, WINDOW_H, { resizable = false, vsync = true })
	love.window.setTitle("Snake + Power-ups")
	love.graphics.setBackgroundColor(COLORS.bg)
	resetGame()
	game.state = STATE.start
end

function love.update(dt)
	game.pulseT = game.pulseT + dt

	if game.shakeT > 0 then
		game.shakeT = math.max(0, game.shakeT - dt)
		if game.shakeT == 0 then
			game.shakeMag = 0
		end
	end

	if game.state ~= STATE.playing then
		return
	end

	updateActiveTimers(dt)
	updatePowerupsOnBoard(dt)

	powerupSpawnTimer = powerupSpawnTimer + dt
	if powerupSpawnTimer >= POWERUP_SPAWN_EVERY_SEC then
		powerupSpawnTimer = powerupSpawnTimer - POWERUP_SPAWN_EVERY_SEC
		trySpawnPowerup()
	end

	game.moveTimer = game.moveTimer + dt
	local step = tickDuration()
	local maxSteps = 6 -- prevents huge dt spikes from stepping too many times
	local steps = 0
	while game.moveTimer >= step and game.state == STATE.playing and steps < maxSteps do
		game.moveTimer = game.moveTimer - step
		steps = steps + 1
		stepSnakeOnce()
		snake.canTurn = true
	end
end

local function drawGrid()
	-- Subtle checkerboard background.
	for y = 1, GRID_ROWS do
		for x = 1, GRID_COLS do
			local isA = ((x + y) % 2) == 0
			local c = isA and COLORS.gridA or COLORS.gridB
			love.graphics.setColor(c)
			love.graphics.rectangle("fill", (x - 1) * CELL, (y - 1) * CELL, CELL, CELL)
		end
	end
end

local function drawCell(x, y, color)
	love.graphics.setColor(color)
	local px = (x - 1) * CELL
	local py = (y - 1) * CELL
	-- Slight inset for a nicer look.
	local inset = 2
	love.graphics.rectangle("fill", px + inset, py + inset, CELL - 2 * inset, CELL - 2 * inset, 4, 4)
end

local function drawFood()
	local t = game.pulseT
	local pulse = 0.55 + 0.45 * math.sin(t * 6)
	local r = (CELL * 0.25) + (CELL * 0.12) * pulse
	local cx = (food.x - 0.5) * CELL
	local cy = (food.y - 0.5) * CELL
	love.graphics.setColor(COLORS.food)
	love.graphics.circle("fill", cx, cy, r)
end

local function powerupVisual(kind)
	if kind == "speed" then
		return COLORS.puSpeed, "S"
	end
	if kind == "shield" then
		return COLORS.puShield, "H"
	end
	if kind == "double" then
		return COLORS.puDouble, "2"
	end
	return COLORS.warn, "?"
end

local function drawPowerups()
	for i = 1, #powerups do
		local p = powerups[i]
		local col, label = powerupVisual(p.kind)
		drawCell(p.x, p.y, col)
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", (p.x - 1) * CELL + 4, (p.y - 1) * CELL + 4, CELL - 8, CELL - 8, 4, 4)
		love.graphics.setColor(1, 1, 1, 0.95)
		love.graphics.printf(label, (p.x - 1) * CELL, (p.y - 1) * CELL + (CELL / 2) - 7, CELL, "center")
	end
end

local function drawSnake()
	for i = #snake.body, 1, -1 do
		local s = snake.body[i]
		if i == 1 then
			drawCell(s.x, s.y, COLORS.snakeHead)
		else
			drawCell(s.x, s.y, COLORS.snakeBody)
		end
	end
end

local function drawHUD()
	love.graphics.setColor(COLORS.ui)
	love.graphics.print("Score: " .. tostring(game.score), 10, 10)
	love.graphics.setColor(COLORS.uiDim)
	love.graphics.print(string.format("Speed: %.1f moves/s", movesPerSecond()), 10, 28)

	local y = 10
	local x = WINDOW_W - 220
	love.graphics.setColor(COLORS.ui)
	love.graphics.print("Power-ups:", x, y)
	y = y + 18

	local any = false
	if hasShield() then
		any = true
		love.graphics.setColor(COLORS.puShield)
		love.graphics.print("Shield x" .. tostring(active.shield.charges), x, y)
		y = y + 16
	end
	if active.speed then
		any = true
		love.graphics.setColor(COLORS.puSpeed)
		love.graphics.print(string.format("Speed %.1fs", active.speed.remaining), x, y)
		y = y + 16
	end
	if active.double then
		any = true
		love.graphics.setColor(COLORS.puDouble)
		love.graphics.print(string.format("2x Score %.1fs", active.double.remaining), x, y)
		y = y + 16
	end
	if not any then
		love.graphics.setColor(COLORS.uiDim)
		love.graphics.print("(none)", x, y)
	end
end

local function centerText(lines, y)
	for i = 1, #lines do
		love.graphics.printf(lines[i], 0, y + (i - 1) * 22, WINDOW_W, "center")
	end
end

function love.draw()
	local ox, oy = 0, 0
	if game.shakeT > 0 and game.shakeMag > 0 then
		ox = love.math.random(-game.shakeMag, game.shakeMag)
		oy = love.math.random(-game.shakeMag, game.shakeMag)
	end

	love.graphics.push()
	love.graphics.translate(ox, oy)

	drawGrid()
	drawFood()
	drawPowerups()
	drawSnake()

	love.graphics.pop()

	drawHUD()

	if game.state == STATE.start then
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", 0, 0, WINDOW_W, WINDOW_H)
		love.graphics.setColor(COLORS.ui)
		centerText({
			"SNAKE + POWER-UPS",
			"Arrows / WASD to move (no reverse)",
			"Eat food to grow and speed up",
			"Power-ups: S=Speed, H=Shield, 2=Double Score",
			"Press Enter/Space to start",
			"P to pause, R to restart, Esc to quit",
		}, 180)
	end

	if game.state == STATE.paused then
		love.graphics.setColor(0, 0, 0, 0.45)
		love.graphics.rectangle("fill", 0, 0, WINDOW_W, WINDOW_H)
		love.graphics.setColor(COLORS.ui)
		centerText({ "PAUSED", "Press P to resume", "Press R to restart" }, 240)
	end

	if game.state == STATE.gameover then
		love.graphics.setColor(0, 0, 0, 0.60)
		love.graphics.rectangle("fill", 0, 0, WINDOW_W, WINDOW_H)
		love.graphics.setColor(COLORS.ui)
		centerText({
			"GAME OVER",
			"Score: " .. tostring(game.score) .. "   Best: " .. tostring(game.best),
			"Press R to restart",
			"Press Enter/Space for start screen",
		}, 230)
	end
end

function love.keypressed(key)
	if key == "escape" then
		love.event.quit()
		return
	end

	if key == "p" then
		if game.state == STATE.playing then
			game.state = STATE.paused
		elseif game.state == STATE.paused then
			game.state = STATE.playing
		end
		return
	end

	if key == "r" then
		resetGame()
		return
	end

	if key == "return" or key == "kpenter" or key == "space" then
		if game.state == STATE.start then
			resetGame()
			return
		end
		if game.state == STATE.gameover then
			game.state = STATE.start
			return
		end
	end

	-- Movement controls (Arrows + WASD).
	if game.state ~= STATE.playing then
		return
	end

	if key == "up" or key == "w" then
		setNextDirection(0, -1)
	elseif key == "down" or key == "s" then
		setNextDirection(0, 1)
	elseif key == "left" or key == "a" then
		setNextDirection(-1, 0)
	elseif key == "right" or key == "d" then
		setNextDirection(1, 0)
	end
end

