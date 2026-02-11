#!/usr/bin/env ts-node
/**
 * Complete TypeScript example demonstrating various syntax elements
 * @module example
 */

// Imports
import { readFile, writeFile } from 'fs/promises';
import type { Config, Handler } from './types';
import defaultExport, { namedExport } from './module';

// Re-exports
export { readFile } from 'fs/promises';
export * from './utils';
export type { Config };

// Constants
const MAX_VALUE = 100;
const PI: number = 3.14159;
const GREETING: string = "Hello, World!";

// Type aliases
type ID = string | number;
type Nullable<T> = T | null;
type ReadOnly<T> = { readonly [K in keyof T]: T[K] };

// Interfaces
interface User {
    id: ID;
    name: string;
    email?: string;
    readonly createdAt: Date;
}

interface ApiResponse<T> {
    data: T;
    status: number;
    message: string;
}

// Extending interfaces
interface Admin extends User {
    permissions: string[];
}

// Enums
enum Status {
    Pending = 'PENDING',
    Active = 'ACTIVE',
    Completed = 'COMPLETED',
}

const enum Direction {
    Up = 1,
    Down,
    Left,
    Right,
}

// Classes
class Person implements User {
    readonly id: ID;
    name: string;
    email?: string;
    readonly createdAt: Date;

    private _age: number = 0;
    protected address?: string;
    static count: number = 0;

    constructor(id: ID, name: string) {
        this.id = id;
        this.name = name;
        this.createdAt = new Date();
        Person.count++;
    }

    get age(): number {
        return this._age;
    }

    set age(value: number) {
        if (value >= 0) {
            this._age = value;
        }
    }

    greet(): string {
        return `Hello, I'm ${this.name}`;
    }

    static create(name: string): Person {
        return new Person(Date.now().toString(), name);
    }
}

// Abstract class
abstract class Animal {
    abstract makeSound(): string;

    move(): void {
        console.log('Moving...');
    }
}

class Dog extends Animal {
    makeSound(): string {
        return 'Woof!';
    }
}

// Generic class
class Stack<T> {
    private items: T[] = [];

    push(item: T): void {
        this.items.push(item);
    }

    pop(): T | undefined {
        return this.items.pop();
    }
}

// Functions
function greet(name: string): string {
    return `Hello, ${name}!`;
}

// Function with optional and default parameters
function createUser(
    name: string,
    age?: number,
    status: Status = Status.Pending
): User {
    return {
        id: Date.now().toString(),
        name,
        createdAt: new Date(),
    };
}

// Generic function
function identity<T>(arg: T): T {
    return arg;
}

// Function with constraints
function getProperty<T, K extends keyof T>(obj: T, key: K): T[K] {
    return obj[key];
}

// Arrow functions
const add = (a: number, b: number): number => a + b;
const square = (x: number) => x * x;

// Async functions
async function fetchData<T>(url: string): Promise<ApiResponse<T>> {
    const response = await fetch(url);
    const data = await response.json();
    return { data, status: response.status, message: 'OK' };
}

// Function overloads
function process(x: string): string;
function process(x: number): number;
function process(x: string | number): string | number {
    if (typeof x === 'string') {
        return x.toUpperCase();
    }
    return x * 2;
}

// Decorators (requires experimentalDecorators)
function logged(target: any, key: string, descriptor: PropertyDescriptor) {
    const original = descriptor.value;
    descriptor.value = function (...args: any[]) {
        console.log(`Calling ${key} with`, args);
        return original.apply(this, args);
    };
    return descriptor;
}

class Calculator {
    @logged
    add(a: number, b: number): number {
        return a + b;
    }
}

// Type guards
function isString(value: unknown): value is string {
    return typeof value === 'string';
}

function isUser(obj: any): obj is User {
    return obj && typeof obj.name === 'string' && 'id' in obj;
}

// Discriminated unions
interface Circle {
    kind: 'circle';
    radius: number;
}

interface Rectangle {
    kind: 'rectangle';
    width: number;
    height: number;
}

type Shape = Circle | Rectangle;

function getArea(shape: Shape): number {
    switch (shape.kind) {
        case 'circle':
            return Math.PI * shape.radius ** 2;
        case 'rectangle':
            return shape.width * shape.height;
    }
}

// Mapped types
type Partial<T> = { [P in keyof T]?: T[P] };
type Required<T> = { [P in keyof T]-?: T[P] };
type Pick<T, K extends keyof T> = { [P in K]: T[P] };

// Conditional types
type NonNullable<T> = T extends null | undefined ? never : T;
type ReturnType<T extends (...args: any) => any> = T extends (...args: any) => infer R ? R : any;

// Template literal types
type EventName = `on${Capitalize<string>}`;
type CSSValue = `${number}px` | `${number}em` | `${number}%`;

// Utility types
type UserKeys = keyof User;
type UserValues = User[keyof User];

// As const
const config = {
    host: 'localhost',
    port: 8080,
} as const;

// Satisfies operator (TS 4.9+)
const palette = {
    red: [255, 0, 0],
    green: '#00ff00',
} satisfies Record<string, string | number[]>;

// Control flow
const count: number = 42;

if (count > 0) {
    console.log('Positive');
} else if (count === 0) {
    console.log('Zero');
} else {
    console.log('Negative');
}

// Nullish coalescing and optional chaining
const user: User | null = null;
const name = user?.name ?? 'Anonymous';

// Type assertions
const element = document.getElementById('app') as HTMLDivElement;
const value = <string>someValue;

// Non-null assertion
const definitelyString = possiblyNull!;

// Numbers
const integer = 42;
const float = 3.14;
const hex = 0xFF;
const octal = 0o755;
const binary = 0b1010;
const bigInt = 9007199254740991n;

// Template strings
const message = `Hello, ${name}! Count is ${count}`;

// Regex
const pattern: RegExp = /^[a-z]+$/gi;

export { Person, Status, greet };
export default Calculator;
