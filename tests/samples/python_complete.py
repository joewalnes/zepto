#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""A complete Python program demonstrating various syntax elements."""

# This is a very long comment that extends well beyond the typical terminal width of eighty columns to test word wrap behavior in code files. When wrap is toggled on with Alt+Z, this line should break at word boundaries and display a continuation indicator on wrapped rows.

LONG_MESSAGE = "This is a very long string literal that also extends well beyond eighty columns to test how the editor handles syntax highlighting when a single string value wraps across multiple visual rows in the terminal viewport."

import os
import sys
from typing import List, Dict, Optional
from dataclasses import dataclass

# Constants
MAX_VALUE = 100
PI = 3.14159

# Type-annotated variables
name: str = "World"
count: int = 42
items: List[int] = [1, 2, 3, 4, 5]
config: Dict[str, any] = {
    'host': 'localhost',
    'port': 8080,
}

# Dataclass
@dataclass
class Person:
    name: str
    age: int
    email: Optional[str] = None

# Function definition
def greet(who: str) -> str:
    """Return a greeting message."""
    return f"Hello, {who}!"

# Control structures
if count > 0:
    print("Positive")
elif count == 0:
    print("Zero")
else:
    print("Negative")

# Loops
for i in range(10):
    if i % 2 == 0:
        continue
    if i > 5:
        break
    print(i)

while count > 0:
    count -= 1

for item in items:
    print(item)

# List comprehension
squares = [x**2 for x in range(10) if x % 2 == 0]

# Dictionary comprehension
square_dict = {x: x**2 for x in range(5)}

# Lambda function
add = lambda a, b: a + b

# Class definition
class Calculator:
    """A simple calculator class."""

    def __init__(self, initial: int = 0):
        self._value = initial

    @property
    def value(self) -> int:
        return self._value

    @staticmethod
    def multiply(a: int, b: int) -> int:
        return a * b

    @classmethod
    def from_string(cls, s: str) -> 'Calculator':
        return cls(int(s))

# Exception handling
try:
    result = 10 / 0
except ZeroDivisionError as e:
    print(f"Error: {e}")
except Exception:
    raise
finally:
    print("Cleanup")

# Context manager
with open('/tmp/test.txt', 'w') as f:
    f.write("Hello")

# Async/await (syntax only)
async def fetch_data(url: str) -> bytes:
    await some_async_call()
    return b"data"

# Numbers
integer = 42
floating = 3.14
hexadecimal = 0xFF
octal = 0o755
binary = 0b1010
scientific = 1.5e10
complex_num = 3 + 4j

# Operators
total = integer + floating
concatenated = name + "!"
boolean = (count and integer) or 0
ternary = 'yes' if count > 0 else 'no'

# F-strings
message = f"Count is {count}, name is {name.upper()}"

# Raw and byte strings
raw = r"C:\Users\test"
byte_string = b"binary data"

# Multiline string
multiline = """
This is a
multiline string
"""

# Walrus operator (Python 3.8+)
if (n := len(items)) > 3:
    print(f"List has {n} items")

# Match statement (Python 3.10+)
match count:
    case 0:
        print("zero")
    case 1 | 2:
        print("one or two")
    case _:
        print("other")

if __name__ == "__main__":
    print(greet("World"))
