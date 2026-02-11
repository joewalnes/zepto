// Complete Swift example demonstrating syntax highlighting
import Foundation

// Protocol definition
protocol Drawable {
    func draw()
    var description: String { get }
}

// Protocol with associated type
protocol Container {
    associatedtype Item
    mutating func append(_ item: Item)
    var count: Int { get }
    subscript(i: Int) -> Item { get }
}

// Enum with associated values
enum Result<Success, Failure: Error> {
    case success(Success)
    case failure(Failure)
}

// Enum with raw values
enum Status: Int {
    case pending = 0
    case active = 1
    case completed = 2
}

// Struct
struct Point {
    var x: Double
    var y: Double

    // Computed property
    var magnitude: Double {
        return (x * x + y * y).squareRoot()
    }

    // Mutating method
    mutating func translate(by offset: Point) {
        x += offset.x
        y += offset.y
    }
}

// Class with inheritance
class Shape: Drawable {
    var name: String

    init(name: String) {
        self.name = name
    }

    func draw() {
        print("Drawing \(name)")
    }

    var description: String {
        return "Shape: \(name)"
    }
}

// Subclass
final class Circle: Shape {
    var radius: Double

    init(radius: Double) {
        self.radius = radius
        super.init(name: "Circle")
    }

    override func draw() {
        print("Drawing circle with radius \(radius)")
    }

    func area() -> Double {
        return Double.pi * radius * radius
    }
}

// Actor (Swift concurrency)
actor Counter {
    private var value = 0

    func increment() {
        value += 1
    }

    func getValue() -> Int {
        return value
    }
}

// Generic function
func swap<T>(_ a: inout T, _ b: inout T) {
    let temp = a
    a = b
    b = temp
}

// Function with closures
func performOperation(_ operation: (Int, Int) -> Int, on a: Int, and b: Int) -> Int {
    return operation(a, b)
}

// Extension
extension Int {
    var isEven: Bool {
        return self % 2 == 0
    }

    func times(_ action: () -> Void) {
        for _ in 0..<self {
            action()
        }
    }
}

// Property wrapper
@propertyWrapper
struct Clamped<Value: Comparable> {
    var value: Value
    let range: ClosedRange<Value>

    var wrappedValue: Value {
        get { value }
        set { value = min(max(newValue, range.lowerBound), range.upperBound) }
    }

    init(wrappedValue: Value, range: ClosedRange<Value>) {
        self.range = range
        self.value = min(max(wrappedValue, range.lowerBound), range.upperBound)
    }
}

// Main code
@main
struct App {
    static func main() async {
        // Variable declarations
        let count: Int = 42
        var name = "Swift"
        let pi: Double = 3.14159
        let flag: Bool = true
        let character: Character = "A"
        let message: String = "Hello, World!"

        // Optional binding
        var optional: String? = "value"
        if let value = optional {
            print(value)
        }

        // Guard statement
        guard let unwrapped = optional else {
            return
        }

        // Nil coalescing
        let result = optional ?? "default"

        // Array and dictionary
        var numbers: [Int] = [1, 2, 3, 4, 5]
        var dict: [String: Int] = ["one": 1, "two": 2]

        // Control flow
        if count > 0 {
            print("Positive")
        } else if count < 0 {
            print("Negative")
        } else {
            print("Zero")
        }

        // Switch with pattern matching
        switch count {
        case 0:
            print("Zero")
        case 1...10:
            print("Between 1 and 10")
        case let x where x > 100:
            print("Large: \(x)")
        default:
            print("Other")
        }

        // For loop
        for i in 0..<10 {
            if i == 5 { continue }
            if i == 8 { break }
            print(i)
        }

        // While loop
        var counter = 0
        while counter < 10 {
            counter += 1
        }

        // Closures
        let add: (Int, Int) -> Int = { $0 + $1 }
        let doubled = numbers.map { $0 * 2 }
        let filtered = numbers.filter { $0 > 2 }

        // Async/await
        let asyncCounter = Counter()
        await asyncCounter.increment()
        let value = await asyncCounter.getValue()

        // Try/catch
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: "/path"))
        } catch {
            print("Error: \(error)")
        }

        // Defer
        defer {
            print("Cleanup")
        }
    }
}

/*
 * Multi-line comment
 * demonstrating Swift features
 */
