// Complete C++ example demonstrating syntax highlighting
#include <iostream>
#include <vector>
#include <string>
#include <memory>
#include <algorithm>
#include <functional>

// Namespace
namespace demo {

// Template class
template<typename T>
class Container {
private:
    std::vector<T> items_;

public:
    Container() = default;
    ~Container() = default;

    // Rule of five
    Container(const Container& other) = default;
    Container(Container&& other) noexcept = default;
    Container& operator=(const Container& other) = default;
    Container& operator=(Container&& other) noexcept = default;

    void add(const T& item) {
        items_.push_back(item);
    }

    void add(T&& item) {
        items_.push_back(std::move(item));
    }

    size_t size() const noexcept {
        return items_.size();
    }

    const T& operator[](size_t index) const {
        return items_[index];
    }
};

// Enum class (C++11)
enum class Status {
    Ok,
    Error,
    Pending
};

// Struct with default member initializers
struct Config {
    std::string name = "default";
    int count = 0;
    bool enabled = true;
};

// Abstract base class
class Shape {
public:
    virtual ~Shape() = default;
    virtual double area() const = 0;
    virtual void draw() const = 0;
};

// Derived class
class Circle : public Shape {
private:
    double radius_;

public:
    explicit Circle(double radius) : radius_(radius) {}

    double area() const override {
        return 3.14159265358979 * radius_ * radius_;
    }

    void draw() const override {
        std::cout << "Drawing circle with radius " << radius_ << std::endl;
    }
};

// Function template
template<typename T>
T max_value(T a, T b) {
    return (a > b) ? a : b;
}

// Lambda and auto
auto process = [](int x) -> int {
    return x * 2;
};

} // namespace demo

int main() {
    using namespace demo;

    // Variable declarations
    int count = 42;
    double pi = 3.14159;
    bool flag = true;
    char letter = 'A';
    std::string message = "Hello, World!";

    // Auto and range-based for
    std::vector<int> numbers = {1, 2, 3, 4, 5};
    for (auto& num : numbers) {
        std::cout << num << std::endl;
    }

    // Smart pointers
    auto ptr = std::make_unique<Circle>(5.0);
    std::shared_ptr<Shape> shape = std::make_shared<Circle>(3.0);

    // Lambda with capture
    int multiplier = 10;
    auto lambda = [multiplier](int x) {
        return x * multiplier;
    };

    // STL algorithms
    std::sort(numbers.begin(), numbers.end(), std::greater<int>());

    // Template usage
    Container<std::string> container;
    container.add("hello");
    container.add("world");

    // Structured bindings (C++17)
    auto [name, value, enabled] = Config{};

    // If with initializer (C++17)
    if (auto result = lambda(5); result > 0) {
        std::cout << "Result: " << result << std::endl;
    }

    // Constexpr
    constexpr int MAX_SIZE = 1024;
    constexpr double E = 2.71828;

    // nullptr
    int* null_ptr = nullptr;

    return 0;
}

/*
 * Multi-line comment
 * demonstrating C++ features
 */
