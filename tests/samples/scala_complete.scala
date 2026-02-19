// Scala sample file demonstrating syntax features
package com.example.demo

import scala.collection.mutable
import scala.concurrent.{Future, ExecutionContext}
import scala.util.{Try, Success, Failure}

/**
 * ScalaDoc comment
 * @param name the name parameter
 */

// Constants
val MAX_SIZE = 100
val PI: Double = 3.14159

// Case class (immutable data)
case class Person(
  name: String,
  age: Int,
  email: Option[String] = None
)

// Sealed trait for ADT
sealed trait Result[+A]
case class Success[A](value: A) extends Result[A]
case class Error(message: String) extends Result[Nothing]
case object Loading extends Result[Nothing]

// Enum (Scala 3 style comment, but works as sealed trait)
sealed trait Status
object Status {
  case object Pending extends Status
  case object Active extends Status
  case object Completed extends Status
}

// Trait with abstract and concrete members
trait Repository[T] {
  def findAll(): Seq[T]
  def findById(id: Int): Option[T]
  def save(entity: T): Unit

  // Default implementation
  def exists(id: Int): Boolean = findById(id).isDefined
}

// Generic class with variance
class Container[+A](value: A) {
  def get: A = value
  def map[B](f: A => B): Container[B] = new Container(f(value))
}

// Object (singleton)
object Calculator {
  def add(a: Int, b: Int): Int = a + b
  def multiply(a: Int, b: Int): Int = a * b

  // Apply method
  def apply(initial: Int): Calculator = new Calculator(initial)
}

// Class with companion object
class Calculator(private var value: Int) {
  def add(n: Int): Calculator = {
    value += n
    this
  }

  def result: Int = value
}

// Abstract class
abstract class Animal(val name: String) {
  def speak(): String
  def move(): String = "Moving"
}

// Extending class
class Dog(name: String) extends Animal(name) {
  override def speak(): String = "Woof!"
  override def move(): String = "Running"
}

// Higher-kinded types example
trait Functor[F[_]] {
  def map[A, B](fa: F[A])(f: A => B): F[B]
}

// Main object
object Main extends App {
  // Variable declarations
  val immutable: String = "Hello"
  var mutable = "World"
  lazy val computed = expensiveOperation()

  private def expensiveOperation(): Int = {
    Thread.sleep(100)
    42
  }

  // String interpolation
  val greeting = s"Say: $immutable ${mutable.toUpperCase}!"
  val formatted = f"Pi is $PI%.2f"
  val raw = raw"No \n escape"

  // Triple-quoted string
  val multiline = """
    |This is a
    |multiline string
    |with margin
  """.stripMargin

  // Collections
  val numbers = List(1, 2, 3, 4, 5)
  val vector = Vector(1, 2, 3)
  val set = Set("a", "b", "c")
  val map = Map("key" -> "value", "foo" -> "bar")
  val mutableList = mutable.ListBuffer(1, 2, 3)

  // Functional operations
  val doubled = numbers.map(_ * 2)
  val filtered = numbers.filter(_ > 2)
  val sum = numbers.reduce(_ + _)
  val folded = numbers.foldLeft(0)(_ + _)
  val flatMapped = numbers.flatMap(n => List(n, n * 2))

  // For comprehension
  val pairs = for {
    x <- 1 to 3
    y <- 1 to 3
    if x != y
  } yield (x, y)

  // Pattern matching
  val result = numbers.head match {
    case 1 => "one"
    case 2 | 3 => "two or three"
    case n if n > 10 => "big"
    case _ => "other"
  }

  // Partial function
  val partial: PartialFunction[Int, String] = {
    case 1 => "one"
    case 2 => "two"
  }

  // Option handling
  val maybeValue: Option[Int] = Some(42)
  val extracted = maybeValue.getOrElse(0)
  val mapped = maybeValue.map(_ * 2)
  val flatMappedOpt = maybeValue.flatMap(v => Some(v + 1))

  // Try for error handling
  val tried: Try[Int] = Try {
    "42".toInt
  }

  tried match {
    case Success(v) => println(s"Got: $v")
    case Failure(e) => println(s"Error: ${e.getMessage}")
  }

  // Either
  val either: Either[String, Int] = Right(42)
  val leftMapped = either.left.map(_.toUpperCase)

  // Implicit conversions and classes
  implicit class RichInt(val n: Int) extends AnyVal {
    def times(f: => Unit): Unit = (1 to n).foreach(_ => f)
  }

  3.times(println("Hello"))

  // Anonymous function variations
  val add: (Int, Int) => Int = (a, b) => a + b
  val addShort: (Int, Int) => Int = _ + _
  val addBlock = (a: Int, b: Int) => {
    val sum = a + b
    sum
  }

  // Currying
  def curriedAdd(a: Int)(b: Int): Int = a + b
  val add5 = curriedAdd(5) _

  // By-name parameters
  def lazyEval(cond: Boolean)(block: => Unit): Unit = {
    if (cond) block
  }

  // Future (async)
  implicit val ec: ExecutionContext = ExecutionContext.global
  val future: Future[String] = Future {
    Thread.sleep(100)
    "Done"
  }

  future.onComplete {
    case Success(v) => println(v)
    case Failure(e) => println(e.getMessage)
  }

  // Symbols
  val sym = 'mySymbol

  // Numbers
  val integer = 42
  val long = 42L
  val float = 3.14f
  val double = 3.14
  val hex = 0xFF
  val binary = 0b1010
}
