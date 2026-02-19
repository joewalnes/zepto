// Kotlin sample file demonstrating syntax features
package com.example.demo

import kotlin.math.PI
import kotlin.math.sqrt
import kotlinx.coroutines.*

/**
 * Multi-line KDoc comment
 * @param name The name parameter
 */

// Constants
const val MAX_SIZE = 100
val PI_VALUE = 3.14159

// Data class
data class Person(
    val name: String,
    val age: Int,
    val email: String? = null
)

// Sealed class
sealed class Result<out T> {
    data class Success<T>(val data: T) : Result<T>()
    data class Error(val message: String) : Result<Nothing>()
    object Loading : Result<Nothing>()
}

// Interface
interface Repository<T> {
    suspend fun getAll(): List<T>
    suspend fun getById(id: Int): T?
    suspend fun save(item: T)
}

// Enum class
enum class Status(val code: Int) {
    PENDING(0),
    ACTIVE(1),
    COMPLETED(2);

    fun isTerminal() = this == COMPLETED
}

// Class with primary constructor
class Calculator(private val initialValue: Int = 0) {
    var value: Int = initialValue
        private set

    fun add(n: Int): Calculator {
        value += n
        return this
    }

    fun multiply(n: Int) = apply { value *= n }

    companion object {
        fun create() = Calculator()
    }
}

// Extension function
fun String.addExclamation() = "$this!"

// Extension property
val String.wordCount: Int
    get() = this.split(" ").size

// Inline function with reified type
inline fun <reified T> printType() {
    println(T::class.java.simpleName)
}

// Higher-order function
fun <T> List<T>.customFilter(predicate: (T) -> Boolean): List<T> {
    return filter(predicate)
}

// Suspend function
suspend fun fetchData(url: String): String {
    delay(1000)
    return "Data from $url"
}

// Main function
fun main() {
    // Variable declarations
    val immutable: String = "Hello"
    var mutable = "World"

    // String template
    val greeting = "Say: $immutable ${mutable.uppercase()}!"

    // Null safety
    val nullableString: String? = null
    val length = nullableString?.length ?: 0
    val forced = nullableString!!.length  // Will throw NPE

    // Collections
    val numbers = listOf(1, 2, 3, 4, 5)
    val mutableList = mutableListOf("a", "b", "c")
    val map = mapOf("key" to "value", "foo" to "bar")

    // Lambda and functional operations
    val doubled = numbers.map { it * 2 }
    val filtered = numbers.filter { it > 2 }
    val sum = numbers.reduce { acc, n -> acc + n }

    // When expression
    val result = when (val x = numbers.first()) {
        1 -> "one"
        2, 3 -> "two or three"
        in 4..10 -> "between 4 and 10"
        else -> "unknown"
    }

    // Control flow
    for (i in 1..10 step 2) {
        if (i % 2 == 0) continue
        println(i)
    }

    while (mutable.length < 10) {
        mutable += "x"
    }

    // Try-catch
    try {
        val parsed = "42".toInt()
    } catch (e: NumberFormatException) {
        println("Parse error: ${e.message}")
    } finally {
        println("Cleanup")
    }

    // Object expression
    val listener = object : Runnable {
        override fun run() {
            println("Running")
        }
    }

    // Destructuring
    val (name, age) = Person("Alice", 30)

    // Coroutines
    runBlocking {
        launch {
            val data = async { fetchData("https://example.com") }
            println(data.await())
        }
    }

    // Numbers
    val integer = 42
    val long = 42L
    val float = 3.14f
    val double = 3.14
    val hex = 0xFF
    val binary = 0b1010
}
