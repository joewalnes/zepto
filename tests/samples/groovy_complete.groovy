#!/usr/bin/env groovy
// Groovy sample file demonstrating syntax features
package com.example.demo

import groovy.transform.*
import groovy.json.JsonSlurper
import groovy.json.JsonOutput
import java.util.regex.Pattern

/**
 * Groovydoc comment
 * @param name The name parameter
 */

// Constants
final MAX_SIZE = 100
static final PI = 3.14159

// Enum
enum Status {
    PENDING, ACTIVE, COMPLETED

    boolean isTerminal() {
        this == COMPLETED
    }
}

// Interface
interface Repository<T> {
    List<T> findAll()
    T findById(int id)
    void save(T entity)
}

// Trait
trait Greetable {
    String greeting = "Hello"

    String greet(String name) {
        "$greeting, $name!"
    }
}

// Class with AST transformation
@ToString(includeNames = true)
@EqualsAndHashCode
class Person implements Greetable {
    String name
    int age
    String email

    // Constructor
    Person(String name, int age) {
        this.name = name
        this.age = age
    }

    // Getter with custom logic
    String getDisplayName() {
        name?.toUpperCase() ?: "Unknown"
    }

    // Method
    boolean isAdult() {
        age >= 18
    }
}

// Class with immutable annotation
@Immutable
class Point {
    int x
    int y
}

// Main class
class GroovyDemo {

    // Static method
    static void main(String[] args) {
        // Variable declarations
        def message = "Hello, World!"
        String typed = "Typed string"
        int number = 42

        // GString interpolation
        def greeting = "Message: $message, Number: ${number * 2}"
        def multiline = """
            |This is a
            |multiline string
            |with ${number}
        """.stripMargin()

        // Single-quoted (no interpolation)
        def literal = 'No $interpolation here'

        // Triple single-quoted
        def rawMultiline = '''
            Raw multiline
            no interpolation
        '''

        // Slashy string (regex)
        def pattern = /\d+\.\d+/
        def dollarSlashy = $/
            Allows $ without escape
            and / without escape
        /$

        // Lists
        def numbers = [1, 2, 3, 4, 5]
        def mixed = [1, "two", 3.0, true]
        def empty = []

        // Maps
        def map = [key: "value", "foo": "bar"]
        def emptyMap = [:]

        // Ranges
        def range = 1..10
        def exclusiveRange = 1..<10

        // Closures
        def double = { x -> x * 2 }
        def add = { a, b -> a + b }
        def noArgs = { -> println "No args" }
        def implicit = { it * 2 }

        // Collection operations
        def doubled = numbers.collect { it * 2 }
        def filtered = numbers.findAll { it > 2 }
        def sum = numbers.inject(0) { acc, n -> acc + n }
        def first = numbers.find { it > 3 }

        // Spread operator
        def args = [1, 2, 3]
        def result = sum(*args)

        // Elvis operator
        def nullVal = null
        def safe = nullVal ?: "default"

        // Safe navigation
        def person = new Person("Alice", 30)
        def nameLength = person?.name?.length()

        // Spaceship operator
        def compare = 5 <=> 10

        // Pattern matching
        def text = "Hello 123 World"
        def matcher = text =~ /\d+/
        def match = text ==~ /.*\d+.*/

        // Switch with various matches
        def value = 42
        switch (value) {
            case 0:
                println "Zero"
                break
            case 1..10:
                println "Small"
                break
            case [42, 100, 200]:
                println "Special"
                break
            case ~/\d+/:
                println "Number"
                break
            case { it > 50 }:
                println "Large"
                break
            default:
                println "Unknown"
        }

        // Try-catch
        try {
            def parsed = Integer.parseInt("42")
        } catch (NumberFormatException e) {
            println "Parse error: ${e.message}"
        } finally {
            println "Cleanup"
        }

        // With statement
        def builder = new StringBuilder()
        builder.with {
            append("Hello")
            append(" ")
            append("World")
        }

        // Tap method
        new Person("Bob", 25).tap {
            println "Created: $name"
        }

        // JSON handling
        def json = new JsonSlurper().parseText('{"name": "test"}')
        def jsonStr = JsonOutput.toJson([key: "value"])

        // Operators overloading
        def p1 = new Point(1, 2)
        def p2 = new Point(3, 4)
        def nums = [1, 2, 3] + [4, 5]  // Plus operator
        def str = "Hello" * 3  // Multiply

        // Numbers
        def integer = 42
        def bigInteger = 42G
        def bigDecimal = 42.0G
        def float = 3.14f
        def double = 3.14d
        def hex = 0xFF
        def binary = 0b1010

        // Power operator
        def squared = 2**10
    }
}

// Extension methods
String.metaClass.shout = { -> delegate.toUpperCase() + "!" }
