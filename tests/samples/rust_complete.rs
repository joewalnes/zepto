// Complete Rust example demonstrating syntax highlighting

use std::collections::HashMap;
use std::io::{self, Read, Write};
use std::sync::{Arc, Mutex};

// Constants
const MAX_SIZE: usize = 1024;
const PI: f64 = 3.14159265358979;
static GREETING: &str = "Hello, Rust!";

// Type alias
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

// Struct definition
#[derive(Debug, Clone)]
pub struct Person {
    name: String,
    age: u32,
    email: Option<String>,
}

// Implementation block
impl Person {
    // Associated function (constructor)
    pub fn new(name: &str, age: u32) -> Self {
        Self {
            name: name.to_string(),
            age,
            email: None,
        }
    }

    // Method with &self
    pub fn greet(&self) -> String {
        format!("Hello, I'm {} and I'm {} years old", self.name, self.age)
    }

    // Method with &mut self
    pub fn set_email(&mut self, email: &str) {
        self.email = Some(email.to_string());
    }

    // Method consuming self
    pub fn into_name(self) -> String {
        self.name
    }
}

// Trait definition
pub trait Drawable {
    fn draw(&self);
    fn area(&self) -> f64;
}

// Enum with variants
#[derive(Debug)]
pub enum Shape {
    Circle { radius: f64 },
    Rectangle { width: f64, height: f64 },
    Triangle(f64, f64, f64),  // sides
}

// Trait implementation
impl Drawable for Shape {
    fn draw(&self) {
        match self {
            Shape::Circle { radius } => println!("Drawing circle with radius {}", radius),
            Shape::Rectangle { width, height } => {
                println!("Drawing {}x{} rectangle", width, height)
            }
            Shape::Triangle(a, b, c) => println!("Drawing triangle with sides {}, {}, {}", a, b, c),
        }
    }

    fn area(&self) -> f64 {
        match self {
            Shape::Circle { radius } => PI * radius * radius,
            Shape::Rectangle { width, height } => width * height,
            Shape::Triangle(a, b, c) => {
                // Heron's formula
                let s = (a + b + c) / 2.0;
                (s * (s - a) * (s - b) * (s - c)).sqrt()
            }
        }
    }
}

// Generic function with trait bounds
fn print_area<T: Drawable>(shape: &T) {
    println!("Area: {}", shape.area());
}

// Generic struct
struct Container<T> {
    value: T,
}

impl<T: Clone> Container<T> {
    fn get(&self) -> T {
        self.value.clone()
    }
}

// Lifetime annotations
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}

// Async function
async fn fetch_data(url: &str) -> Result<String> {
    // Simulated async operation
    Ok(format!("Data from {}", url))
}

// Error handling
fn divide(a: f64, b: f64) -> Result<f64> {
    if b == 0.0 {
        Err("Division by zero".into())
    } else {
        Ok(a / b)
    }
}

// Closures and iterators
fn process_numbers(numbers: Vec<i32>) -> Vec<i32> {
    numbers
        .iter()
        .filter(|&&x| x > 0)
        .map(|&x| x * 2)
        .collect()
}

// Pattern matching
fn describe_number(n: i32) -> &'static str {
    match n {
        0 => "zero",
        1..=9 => "single digit",
        10..=99 => "double digit",
        100..=999 => "triple digit",
        _ => "large number",
    }
}

// Macro usage
macro_rules! say_hello {
    () => {
        println!("Hello!");
    };
    ($name:expr) => {
        println!("Hello, {}!", $name);
    };
}

// Main function
fn main() {
    // Variable bindings
    let x = 42;
    let mut y = 10;
    let (a, b) = (1, 2);

    // Type annotations
    let float: f64 = 3.14;
    let array: [i32; 5] = [1, 2, 3, 4, 5];
    let tuple: (i32, &str, bool) = (1, "hello", true);

    // String types
    let string_literal = "Hello, world!";
    let string_owned = String::from("Owned string");
    let raw_string = r#"Raw "string" with quotes"#;
    let byte_string = b"byte string";

    // Numbers
    let decimal = 1_000_000;
    let hex = 0xDEAD_BEEF;
    let octal = 0o755;
    let binary = 0b1010_1010;
    let float_exp = 1.5e-10;

    // Control flow
    if x > 0 {
        println!("positive");
    } else if x < 0 {
        println!("negative");
    } else {
        println!("zero");
    }

    // Loop expressions
    let result = loop {
        y += 1;
        if y > 20 {
            break y * 2;
        }
    };

    // While loop
    while y > 0 {
        y -= 1;
    }

    // For loop with range
    for i in 0..10 {
        print!("{} ", i);
    }

    // For loop with iterator
    for (idx, val) in array.iter().enumerate() {
        println!("array[{}] = {}", idx, val);
    }

    // Match expression
    let message = match x {
        0 => "zero",
        1 | 2 => "one or two",
        3..=10 => "three to ten",
        n if n < 0 => "negative",
        _ => "something else",
    };

    // If let
    let optional: Option<i32> = Some(42);
    if let Some(value) = optional {
        println!("Got value: {}", value);
    }

    // While let
    let mut stack = vec![1, 2, 3];
    while let Some(top) = stack.pop() {
        println!("Popped: {}", top);
    }

    // Struct usage
    let mut person = Person::new("Alice", 30);
    person.set_email("alice@example.com");
    println!("{}", person.greet());

    // Enum usage
    let shapes = vec![
        Shape::Circle { radius: 5.0 },
        Shape::Rectangle { width: 4.0, height: 3.0 },
        Shape::Triangle(3.0, 4.0, 5.0),
    ];

    for shape in &shapes {
        shape.draw();
        print_area(shape);
    }

    // HashMap
    let mut map: HashMap<&str, i32> = HashMap::new();
    map.insert("one", 1);
    map.insert("two", 2);

    if let Some(value) = map.get("one") {
        println!("Found: {}", value);
    }

    // Error handling with ?
    let _ = divide(10.0, 2.0).unwrap_or(0.0);

    // Closures
    let add = |a, b| a + b;
    let multiply = |a: i32, b: i32| -> i32 { a * b };
    let capture = |x| x + y;

    // Using closures
    let numbers = vec![1, -2, 3, -4, 5];
    let positives: Vec<_> = numbers.iter().filter(|&&n| n > 0).collect();

    // Unsafe block
    unsafe {
        let ptr = &x as *const i32;
        println!("Raw pointer value: {}", *ptr);
    }

    // Box and smart pointers
    let boxed: Box<i32> = Box::new(42);
    let arc = Arc::new(Mutex::new(0));

    // Macro invocation
    say_hello!();
    say_hello!("World");

    // Vector macros
    let vec1 = vec![1, 2, 3];
    let formatted = format!("x = {}, y = {}", x, y);
    println!("{}", formatted);

    // Attributes
    #[allow(unused_variables)]
    let unused = 42;

    // Documentation comment
    /// This is a doc comment
    fn documented() {}

    /*
     * Multi-line comment
     * spanning multiple lines
     */
}

// Tests module
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_person() {
        let person = Person::new("Test", 25);
        assert_eq!(person.age, 25);
    }

    #[test]
    #[should_panic]
    fn test_panic() {
        panic!("This test panics!");
    }
}
