// Package main demonstrates various Go syntax elements
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

// Constants
const (
	MaxValue    = 100
	Pi          = 3.14159
	Greeting    = "Hello, World!"
	DefaultPort = 8080
)

// Iota enumeration
const (
	StatusPending = iota
	StatusActive
	StatusCompleted
	StatusFailed
)

// Type definitions
type Status int

type Config struct {
	Host    string `json:"host"`
	Port    int    `json:"port,omitempty"`
	Timeout time.Duration
	Debug   bool
}

// Interface definition
type Reader interface {
	Read(p []byte) (n int, err error)
}

type Writer interface {
	Write(p []byte) (n int, err error)
}

// Embedded interface
type ReadWriter interface {
	Reader
	Writer
}

// Generic type (Go 1.18+)
type Stack[T any] struct {
	items []T
	mu    sync.Mutex
}

// Method on generic type
func (s *Stack[T]) Push(item T) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items = append(s.items, item)
}

func (s *Stack[T]) Pop() (T, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var zero T
	if len(s.items) == 0 {
		return zero, false
	}
	item := s.items[len(s.items)-1]
	s.items = s.items[:len(s.items)-1]
	return item, true
}

// Function with multiple return values
func divide(a, b float64) (float64, error) {
	if b == 0 {
		return 0, errors.New("division by zero")
	}
	return a / b, nil
}

// Named return values
func minMax(numbers []int) (min, max int) {
	if len(numbers) == 0 {
		return
	}
	min, max = numbers[0], numbers[0]
	for _, n := range numbers {
		if n < min {
			min = n
		}
		if n > max {
			max = n
		}
	}
	return
}

// Variadic function
func sum(numbers ...int) int {
	total := 0
	for _, n := range numbers {
		total += n
	}
	return total
}

// Generic function
func Map[T, U any](slice []T, fn func(T) U) []U {
	result := make([]U, len(slice))
	for i, v := range slice {
		result[i] = fn(v)
	}
	return result
}

// Struct with methods
type Person struct {
	Name string
	Age  int
}

func NewPerson(name string, age int) *Person {
	return &Person{Name: name, Age: age}
}

func (p *Person) Greet() string {
	return fmt.Sprintf("Hello, I'm %s, %d years old", p.Name, p.Age)
}

func (p Person) String() string {
	return fmt.Sprintf("%s (%d)", p.Name, p.Age)
}

// HTTP handler
func handleRequest(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	select {
	case <-ctx.Done():
		http.Error(w, "Request cancelled", http.StatusRequestTimeout)
		return
	default:
	}

	data := map[string]interface{}{
		"status":  "ok",
		"message": "Hello, World!",
		"count":   42,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

// Goroutine and channel example
func worker(id int, jobs <-chan int, results chan<- int, wg *sync.WaitGroup) {
	defer wg.Done()
	for job := range jobs {
		fmt.Printf("Worker %d processing job %d\n", id, job)
		time.Sleep(100 * time.Millisecond)
		results <- job * 2
	}
}

// Context with timeout
func fetchWithTimeout(ctx context.Context, url string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	return io.ReadAll(resp.Body)
}

func main() {
	// Variable declarations
	var name string = "World"
	count := 42
	var items = []int{1, 2, 3, 4, 5}
	numbers := []int{10, 20, 30}

	// Map literal
	config := map[string]interface{}{
		"host": "localhost",
		"port": 8080,
		"debug": true,
	}

	// Slice operations
	slice := make([]int, 0, 10)
	slice = append(slice, 1, 2, 3)
	copied := make([]int, len(slice))
	copy(copied, slice)

	// Control structures
	if count > 0 {
		fmt.Println("Positive")
	} else if count == 0 {
		fmt.Println("Zero")
	} else {
		fmt.Println("Negative")
	}

	// If with initialization
	if n := len(items); n > 0 {
		fmt.Printf("Items: %d\n", n)
	}

	// Switch statement
	switch status := StatusActive; status {
	case StatusPending:
		fmt.Println("Pending")
	case StatusActive, StatusCompleted:
		fmt.Println("Active or Completed")
	default:
		fmt.Println("Unknown")
	}

	// Type switch
	var val interface{} = 42
	switch v := val.(type) {
	case int:
		fmt.Printf("Integer: %d\n", v)
	case string:
		fmt.Printf("String: %s\n", v)
	default:
		fmt.Printf("Unknown type: %T\n", v)
	}

	// For loops
	for i := 0; i < 10; i++ {
		if i%2 == 0 {
			continue
		}
		if i > 5 {
			break
		}
		fmt.Println(i)
	}

	// Range loop
	for index, value := range items {
		fmt.Printf("%d: %d\n", index, value)
	}

	// Infinite loop
	go func() {
		for {
			select {
			case <-time.After(1 * time.Second):
				return
			}
		}
	}()

	// Defer, panic, recover
	defer func() {
		if r := recover(); r != nil {
			fmt.Println("Recovered:", r)
		}
	}()

	// Channel operations
	ch := make(chan int, 10)
	go func() {
		for _, n := range numbers {
			ch <- n
		}
		close(ch)
	}()

	for n := range ch {
		fmt.Println(n)
	}

	// Anonymous struct
	point := struct {
		X, Y int
	}{10, 20}
	fmt.Printf("Point: %+v\n", point)

	// Type assertion
	var reader io.Reader
	if closer, ok := reader.(io.Closer); ok {
		defer closer.Close()
	}

	// Raw string literal
	query := `
		SELECT *
		FROM users
		WHERE name = 'John'
	`

	// Numeric literals
	integer := 42
	hex := 0xFF
	octal := 0o755
	binary := 0b1010
	float := 3.14
	scientific := 1.5e10

	fmt.Println(name, count, config, query, integer, hex, octal, binary, float, scientific, point)
}
