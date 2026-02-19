#!/usr/bin/env lua
-- Lua sample file demonstrating syntax features

--[[
Multi-line comment
for documentation
]]

-- Constants (by convention)
local MAX_SIZE = 100
local PI = 3.14159

-- Variables
local name = "World"
local count = 42
local enabled = true
local nothing = nil

-- Table (array-like)
local numbers = {1, 2, 3, 4, 5}

-- Table (dictionary-like)
local person = {
    name = "Alice",
    age = 30,
    ["full-name"] = "Alice Smith"
}

-- Mixed table
local mixed = {
    "first",
    key = "value",
    100,
    nested = {a = 1, b = 2}
}

-- Function definition
local function greet(who)
    return "Hello, " .. who .. "!"
end

-- Function with multiple returns
local function divmod(a, b)
    return math.floor(a / b), a % b
end

-- Anonymous function
local double = function(x)
    return x * 2
end

-- Variadic function
local function sum(...)
    local args = {...}
    local total = 0
    for _, v in ipairs(args) do
        total = total + v
    end
    return total
end

-- Method-style function (colon syntax)
local obj = {}
function obj:method(arg)
    print("Method called with:", arg)
    return self
end

-- Metatables
local Vector = {}
Vector.__index = Vector

function Vector.new(x, y)
    return setmetatable({x = x, y = y}, Vector)
end

function Vector:magnitude()
    return math.sqrt(self.x^2 + self.y^2)
end

function Vector.__add(a, b)
    return Vector.new(a.x + b.x, a.y + b.y)
end

function Vector.__tostring(v)
    return string.format("(%g, %g)", v.x, v.y)
end

-- Control structures
if count > 0 then
    print("Positive")
elseif count == 0 then
    print("Zero")
else
    print("Negative")
end

-- Numeric for loop
for i = 1, 10, 2 do
    if i > 5 then
        break
    end
    print(i)
end

-- Generic for loop
for i, v in ipairs(numbers) do
    print(i, v)
end

for k, v in pairs(person) do
    print(k, v)
end

-- While loop
local i = 0
while i < 10 do
    i = i + 1
end

-- Repeat-until loop
repeat
    i = i - 1
until i == 0

-- String operations
local str = "Hello, World!"
local upper = string.upper(str)
local sub = string.sub(str, 1, 5)
local formatted = string.format("Count: %d, Name: %s", count, name)

-- Pattern matching (Lua's regex-like)
local match = string.match(str, "(%w+)")
local gmatch_iter = string.gmatch(str, "%w+")

-- Long string
local long_str = [[
This is a long string
that spans multiple lines
without escape sequences
]]

-- Long string with equals
local nested = [=[
Can contain [[brackets]]
]=]

-- Tables operations
table.insert(numbers, 6)
local removed = table.remove(numbers)
local sorted = {3, 1, 4, 1, 5}
table.sort(sorted)
local joined = table.concat(sorted, ", ")

-- Math operations
local abs_val = math.abs(-42)
local sqrt_val = math.sqrt(16)
local rand = math.random(1, 100)
local sin_val = math.sin(math.pi / 2)

-- I/O operations
local file = io.open("test.txt", "r")
if file then
    local content = file:read("*all")
    file:close()
end

-- Error handling
local status, err = pcall(function()
    error("Something went wrong!")
end)

local result = xpcall(
    function() return 1 / 0 end,
    function(e) return debug.traceback(e) end
)

-- Coroutines
local co = coroutine.create(function(x)
    for i = 1, x do
        coroutine.yield(i)
    end
end)

-- Module pattern
local MyModule = {}

function MyModule.public_func()
    return "I'm public"
end

local function private_func()
    return "I'm private"
end

-- Numbers
local integer = 42
local float = 3.14
local scientific = 1.5e10
local hex = 0xFF
local hex_float = 0x1.5p10

-- Operators
local arith = 10 + 5 - 3 * 2 / 4 % 3 ^ 2
local concat = "Hello" .. " " .. "World"
local compare = 10 == 10 and 5 ~= 3
local logic = true and false or true
local length = #numbers
local not_val = not false

-- Return module
return MyModule
