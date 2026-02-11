#!/usr/bin/env ruby
# frozen_string_literal: true

# A complete Ruby program demonstrating various syntax elements

require 'json'
require_relative 'helper'

# Constants
MAX_VALUE = 100
PI = 3.14159

# Module definition
module Greetable
  def greet
    "Hello from #{self.class}!"
  end
end

# Class definition with inheritance
class Person
  include Greetable
  extend Comparable

  attr_reader :name
  attr_accessor :age
  attr_writer :email

  @@count = 0

  def initialize(name, age = 0)
    @name = name
    @age = age
    @@count += 1
  end

  def self.count
    @@count
  end

  def to_s
    "#{@name} (#{@age})"
  end

  def <=>(other)
    age <=> other.age
  end

  private

  def secret_method
    "This is private"
  end

  protected

  def shared_method
    "This is protected"
  end
end

# Symbols
status = :active
states = %i[pending active completed]
string_array = %w[one two three]

# Strings
name = "World"
single = 'Hello'
interpolated = "Hello, #{name}!"
heredoc = <<~HEREDOC
  This is a heredoc
  with multiple lines
  and interpolation: #{name}
HEREDOC

# Numbers
integer = 42
float = 3.14
hex = 0xFF
octal = 0o755
binary = 0b1010
scientific = 1.5e10
underscore = 1_000_000

# Regular expressions
pattern = /^[a-z]+$/i
matches = name =~ /World/
replaced = name.gsub(/o/, '0')

# Arrays and Hashes
items = [1, 2, 3, 'four', :five]
config = {
  host: 'localhost',
  port: 8080,
  'string_key' => 'value'
}

# Control structures
if integer > 0
  puts "Positive"
elsif integer == 0
  puts "Zero"
else
  puts "Negative"
end

result = integer > 0 ? 'yes' : 'no'

unless integer.zero?
  puts "Not zero"
end

case status
when :pending
  puts "Waiting"
when :active, :running
  puts "Working"
else
  puts "Unknown"
end

# Loops
for i in 0..10
  next if i.even?
  break if i > 5
  puts i
end

items.each do |item|
  puts item
end

items.each_with_index { |item, idx| puts "#{idx}: #{item}" }

counter = 0
while counter < 5
  counter += 1
end

begin
  counter -= 1
end until counter.zero?

5.times { |n| puts n }
1.upto(5) { |n| puts n }

# Blocks and lambdas
square = ->(x) { x * x }
multiply = lambda { |a, b| a * b }
add = proc { |a, b| a + b }

def with_block
  yield if block_given?
end

with_block { puts "Block executed" }

# Exception handling
begin
  result = 10 / 0
rescue ZeroDivisionError => e
  puts "Error: #{e.message}"
rescue StandardError
  raise
ensure
  puts "Cleanup"
end

# Method with keyword arguments
def greet_person(name:, greeting: "Hello")
  "#{greeting}, #{name}!"
end

# Splat operators
def variadic(*args, **kwargs)
  puts args.inspect
  puts kwargs.inspect
end

first, *rest = items
combined = [*items, *states]
merged = { **config, extra: true }

# Safe navigation and nil handling
value = config&.dig(:nested, :key) || 'default'

# Struct and OpenStruct
Point = Struct.new(:x, :y)
point = Point.new(10, 20)

# Range
range = 1..10
exclusive = 1...10
endless = 1..

# Boolean operators
flag = true && false
other = true || false
negated = !flag
