#!/usr/bin/env node
/**
 * A complete JavaScript program demonstrating various syntax elements.
 * @module example
 */

'use strict';

// Imports (ES6 modules)
import { readFile, writeFile } from 'fs/promises';
import path from 'path';
import defaultExport, { namedExport } from './module.js';

// CommonJS require (for comparison)
const express = require('express');
const { Router } = require('express');

// Constants
const MAX_VALUE = 100;
const PI = 3.14159;
const GREETING = "Hello, World!";

// Variables with different declarations
let count = 42;
var legacy = "old style";  // var is still valid

// Array and object literals
const items = [1, 2, 3, 'four', "five"];
const config = {
    host: 'localhost',
    port: 8080,
    nested: {
        deep: true,
    },
};

// Destructuring
const { host, port } = config;
const [first, second, ...rest] = items;

// Template literals
const message = `Hello, ${host}:${port}!`;
const multiline = `
  This is a
  multiline template literal
`;

// Functions
function greet(who) {
    return `Hello, ${who}!`;
}

// Arrow functions
const add = (a, b) => a + b;
const square = x => x * x;
const process = (data) => {
    console.log(data);
    return data;
};

// Async/await
async function fetchData(url) {
    try {
        const response = await fetch(url);
        const data = await response.json();
        return data;
    } catch (error) {
        console.error('Failed:', error.message);
        throw error;
    }
}

// Promises
const promise = new Promise((resolve, reject) => {
    setTimeout(() => resolve('done'), 1000);
});

promise
    .then(result => console.log(result))
    .catch(err => console.error(err))
    .finally(() => console.log('cleanup'));

// Classes
class Calculator {
    #privateField = 0;  // Private field
    static count = 0;   // Static field

    constructor(initial = 0) {
        this.value = initial;
        Calculator.count++;
    }

    get current() {
        return this.value;
    }

    set current(val) {
        this.value = val;
    }

    add(n) {
        this.value += n;
        return this;  // Method chaining
    }

    static multiply(a, b) {
        return a * b;
    }
}

// Class inheritance
class ScientificCalculator extends Calculator {
    constructor(initial) {
        super(initial);
    }

    sqrt() {
        this.value = Math.sqrt(this.value);
        return this;
    }
}

// Control structures
if (count > 0) {
    console.log("Positive");
} else if (count === 0) {
    console.log("Zero");
} else {
    console.log("Negative");
}

// Switch
switch (count) {
    case 0:
        console.log("zero");
        break;
    case 1:
    case 2:
        console.log("one or two");
        break;
    default:
        console.log("other");
}

// Loops
for (let i = 0; i < 10; i++) {
    if (i % 2 === 0) continue;
    if (i > 5) break;
    console.log(i);
}

for (const item of items) {
    console.log(item);
}

for (const key in config) {
    console.log(key, config[key]);
}

while (count > 0) {
    count--;
}

do {
    count++;
} while (count < 5);

// Array methods
const doubled = items.filter(x => typeof x === 'number').map(x => x * 2);
const sum = [1, 2, 3].reduce((acc, x) => acc + x, 0);

// Spread operator
const combined = [...items, ...doubled];
const cloned = { ...config, extra: true };

// Optional chaining and nullish coalescing
const value = config?.nested?.deep ?? 'default';
const callback = config.onSuccess?.();

// Regular expressions
const pattern = /^[a-z]+$/gi;
const matches = "hello".match(pattern);
const replaced = "hello".replace(/l/g, 'L');

// Numbers
const integer = 42;
const float = 3.14;
const hex = 0xFF;
const octal = 0o755;
const binary = 0b1010;
const scientific = 1.5e10;
const bigInt = 9007199254740991n;

// Symbols and WeakMap
const sym = Symbol('description');
const weakMap = new WeakMap();

// Generators
function* numberGenerator() {
    yield 1;
    yield 2;
    yield* [3, 4, 5];
    return 'done';
}

// Tagged template literal
function highlight(strings, ...values) {
    return strings.reduce((acc, str, i) =>
        acc + str + (values[i] !== undefined ? `<b>${values[i]}</b>` : ''), '');
}

const highlighted = highlight`Hello ${name}, count is ${count}`;

// Export
export { greet, add };
export default Calculator;
