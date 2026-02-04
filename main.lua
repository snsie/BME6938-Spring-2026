-- Snake (LÖVE2D)
-- Controls: WASD or Arrow Keys
-- Space: start/restart, R: restart, Esc: quit

local CELL_SIZE = 24
local GRID_W, GRID_H = 24, 18

local HUD_H = 48
local WINDOW_W, WINDOW_H = GRID_W * CELL_SIZE, GRID_H * CELL_SIZE + HUD_H

local BASE_TICK = 0.14
local MIN_TICK = 0.05
local TICK_STEP_PER_POINT = 0.004

local COLORS = {
  bg = { 14/255, 17/255, 22/255 },
  panel = { 22/255, 26/255, 34/255 },
  grid = { 1, 1, 1, 0.05 },
  snakeHead = { 77/255, 214/255, 126/255 },
  snakeBody = { 57/255, 165/255, 101/255 },
  food = { 241/255, 91/255, 91/255 },
  text = { 235/255, 240/255, 248/255 },
  muted = { 170/255, 180/255, 195/255 },
}

local game = {
  state = "start", -- start | playing | gameover
  score = 0,
  accum = 0,
  tick = BASE_TICK,
  snake = {},
  dir = { x = 1, y = 0 },
  queuedDir = nil,
  food = { x = 1, y = 1 },
}

local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function cellToPixels(x, y)
  local px = (x - 1) * CELL_SIZE
  local py = HUD_H + (y - 1) * CELL_SIZE
  return px, py
end

local function snakeOccupancyMap()
  local occ = {}
  for i = 1, #game.snake do
    local s = game.snake[i]
    occ[s.x .. "," .. s.y] = true
  end
  return occ
end

local function spawnFood()
  local occ = snakeOccupancyMap()
  for _ = 1, 5000 do
    local x = love.math.random(1, GRID_W)
    local y = love.math.random(1, GRID_H)
    if not occ[x .. "," .. y] then
      game.food.x, game.food.y = x, y
      return
    end
  end
end

local function recalcTick()
  game.tick = clamp(BASE_TICK - (game.score * TICK_STEP_PER_POINT), MIN_TICK, BASE_TICK)
end

local function resetGame()
  game.score = 0
  game.accum = 0
  game.dir = { x = 1, y = 0 }
  game.queuedDir = nil
  game.snake = {}

  local startX = math.floor(GRID_W / 2)
  local startY = math.floor(GRID_H / 2)
  local startLen = 5
  for i = 0, startLen - 1 do
    game.snake[#game.snake + 1] = { x = startX - i, y = startY }
  end

  recalcTick()
  spawnFood()
end

local function isOpposite(a, b)
  return a and b and (a.x == -b.x and a.y == -b.y)
end

local function setQueuedDirection(dx, dy)
  local newDir = { x = dx, y = dy }
  if isOpposite(newDir, game.dir) then return end
  game.queuedDir = newDir
end

local function collideWithSelf(x, y)
  for i = 1, #game.snake do
    local s = game.snake[i]
    if s.x == x and s.y == y then
      return true
    end
  end
  return false
end

local function stepSnake()
  if game.queuedDir and not isOpposite(game.queuedDir, game.dir) then
    game.dir = game.queuedDir
  end
  game.queuedDir = nil

  local head = game.snake[1]
  local nx = head.x + game.dir.x
  local ny = head.y + game.dir.y

  -- Walls = game over
  if nx < 1 or nx > GRID_W or ny < 1 or ny > GRID_H then
    game.state = "gameover"
    return
  end

  -- Self collision = game over
  if collideWithSelf(nx, ny) then
    game.state = "gameover"
    return
  end

  table.insert(game.snake, 1, { x = nx, y = ny })

  local ate = (nx == game.food.x and ny == game.food.y)
  if ate then
    game.score = game.score + 1
    recalcTick()
    spawnFood()
  else
    table.remove(game.snake)
  end
end

function love.load()
  love.window.setTitle("Snake")
  love.window.setMode(WINDOW_W, WINDOW_H, { resizable = false, vsync = 1 })
  love.math.setRandomSeed(os.time())

  love.graphics.setFont(love.graphics.newFont(16))

  resetGame()
  game.state = "start"
end

function love.update(dt)
  if game.state ~= "playing" then return end

  game.accum = game.accum + dt
  while game.accum >= game.tick do
    game.accum = game.accum - game.tick
    stepSnake()
    if game.state ~= "playing" then break end
  end
end

local function drawGrid()
  love.graphics.setColor(COLORS.grid)
  for x = 0, GRID_W do
    local px = x * CELL_SIZE
    love.graphics.line(px, HUD_H, px, HUD_H + GRID_H * CELL_SIZE)
  end
  for y = 0, GRID_H do
    local py = HUD_H + y * CELL_SIZE
    love.graphics.line(0, py, GRID_W * CELL_SIZE, py)
  end
end

local function drawFood()
  local x, y = cellToPixels(game.food.x, game.food.y)
  love.graphics.setColor(COLORS.food)
  love.graphics.rectangle("fill", x + 3, y + 3, CELL_SIZE - 6, CELL_SIZE - 6, 6, 6)
end

local function drawSnake()
  for i = #game.snake, 1, -1 do
    local s = game.snake[i]
    local x, y = cellToPixels(s.x, s.y)
    if i == 1 then
      love.graphics.setColor(COLORS.snakeHead)
    else
      love.graphics.setColor(COLORS.snakeBody)
    end
    love.graphics.rectangle("fill", x + 2, y + 2, CELL_SIZE - 4, CELL_SIZE - 4, 6, 6)
  end
end

local function drawHud()
  love.graphics.setColor(COLORS.panel)
  love.graphics.rectangle("fill", 0, 0, WINDOW_W, HUD_H)

  love.graphics.setColor(COLORS.text)
  love.graphics.print("Score: " .. tostring(game.score), 12, 14)
  love.graphics.print(string.format("Tick: %.3fs", game.tick), 160, 14)

  love.graphics.setColor(COLORS.muted)
  love.graphics.print("WASD / Arrows  •  Space: start  •  R: restart  •  Esc: quit", 320, 14)
end

local function drawCenteredText(lines)
  local font = love.graphics.getFont()
  local lineH = font:getHeight() + 6
  local totalH = #lines * lineH
  local startY = HUD_H + (GRID_H * CELL_SIZE) / 2 - totalH / 2
  for i = 1, #lines do
    local text = lines[i]
    local w = font:getWidth(text)
    love.graphics.setColor(COLORS.text)
    love.graphics.print(text, (WINDOW_W - w) / 2, startY + (i - 1) * lineH)
  end
end

function love.draw()
  love.graphics.clear(COLORS.bg)

  drawHud()
  drawGrid()
  drawFood()
  drawSnake()

  if game.state == "start" then
    drawCenteredText({
      "Snake",
      "Press Space to start",
      "Move with WASD or Arrow Keys",
      "Don’t hit the walls or yourself",
    })
  elseif game.state == "gameover" then
    drawCenteredText({
      "Game Over",
      "Score: " .. tostring(game.score),
      "Press Space or R to restart",
    })
  end
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end

  if key == "space" then
    resetGame()
    game.state = "playing"
    return
  end

  if key == "r" then
    resetGame()
    game.state = "playing"
    return
  end

  if game.state ~= "playing" then return end

  if key == "w" or key == "up" then
    setQueuedDirection(0, -1)
  elseif key == "s" or key == "down" then
    setQueuedDirection(0, 1)
  elseif key == "a" or key == "left" then
    setQueuedDirection(-1, 0)
  elseif key == "d" or key == "right" then
    setQueuedDirection(1, 0)
  end
end