// Complete Java example demonstrating syntax highlighting
package com.example.demo;

import java.util.*;
import java.util.stream.Collectors;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

// Constants interface
interface Constants {
    String APP_NAME = "Demo";
    int MAX_SIZE = 1024;
}

// Generic interface
interface Repository<T, ID> {
    T findById(ID id);
    List<T> findAll();
    T save(T entity);
    void delete(T entity);
}

// Abstract class
abstract class BaseEntity {
    protected Long id;
    protected Date createdAt;

    public abstract void validate();
}

// Annotation definition
@interface Autowired {
    boolean required() default true;
}

// Enum with methods
enum Status {
    PENDING("Pending", 0),
    ACTIVE("Active", 1),
    COMPLETED("Completed", 2);

    private final String label;
    private final int code;

    Status(String label, int code) {
        this.label = label;
        this.code = code;
    }

    public String getLabel() { return label; }
    public int getCode() { return code; }
}

// Main class with generics
public class JavaExample<T extends Comparable<T>> extends BaseEntity implements Constants {

    // Static constant
    public static final double PI = 3.14159265358979;

    // Instance fields
    private String name;
    private List<T> items;
    private Map<String, Object> metadata;
    @Autowired
    private Repository<T, Long> repository;

    // Static initializer
    static {
        System.out.println("Class loaded");
    }

    // Constructor
    public JavaExample(String name) {
        this.name = name;
        this.items = new ArrayList<>();
        this.metadata = new HashMap<>();
        this.createdAt = new Date();
    }

    // Overridden method
    @Override
    public void validate() {
        if (name == null || name.isEmpty()) {
            throw new IllegalStateException("Name is required");
        }
    }

    // Generic method
    public <U> Optional<U> transform(T item, java.util.function.Function<T, U> mapper) {
        if (item == null) {
            return Optional.empty();
        }
        return Optional.of(mapper.apply(item));
    }

    // Method with varargs
    public void addItems(T... newItems) {
        for (T item : newItems) {
            items.add(item);
        }
    }

    // Lambda and stream operations
    public List<T> getFilteredItems(java.util.function.Predicate<T> filter) {
        return items.stream()
            .filter(filter)
            .sorted()
            .collect(Collectors.toList());
    }

    // Exception handling
    public String readFile(String path) {
        try {
            return new String(Files.readAllBytes(Path.of(path)));
        } catch (IOException e) {
            System.err.println("Error: " + e.getMessage());
            return null;
        } finally {
            System.out.println("Read attempt completed");
        }
    }

    // Switch expression (Java 14+)
    public String getStatusMessage(Status status) {
        return switch (status) {
            case PENDING -> "Waiting for processing";
            case ACTIVE -> "Currently processing";
            case COMPLETED -> "Processing complete";
        };
    }

    // Record (Java 16+)
    record Point(int x, int y) {
        public double distanceFromOrigin() {
            return Math.sqrt(x * x + y * y);
        }
    }

    // Pattern matching (Java 16+)
    public void processObject(Object obj) {
        if (obj instanceof String s) {
            System.out.println("String length: " + s.length());
        } else if (obj instanceof Integer i) {
            System.out.println("Integer value: " + i);
        } else if (obj instanceof List<?> list) {
            System.out.println("List size: " + list.size());
        }
    }

    // Main method
    public static void main(String[] args) {
        // Variable declarations
        int count = 42;
        long bigNumber = 123_456_789L;
        double pi = 3.14159;
        float ratio = 0.5f;
        boolean flag = true;
        char letter = 'A';

        // String types
        String message = "Hello, World!";
        String multiLine = """
            Multi-line
            text block
            """;

        // Array declarations
        int[] numbers = {1, 2, 3, 4, 5};
        String[] names = new String[]{"Alice", "Bob", "Charlie"};

        // Object creation
        JavaExample<String> example = new JavaExample<>("Test");
        example.addItems("one", "two", "three");

        // Null checks and ternary
        String result = example.name != null ? example.name : "default";

        // Control flow
        if (count > 0) {
            System.out.println("Positive");
        } else if (count < 0) {
            System.out.println("Negative");
        } else {
            System.out.println("Zero");
        }

        // Loops
        for (int i = 0; i < 10; i++) {
            if (i == 5) continue;
            if (i == 8) break;
            System.out.println(i);
        }

        for (String item : example.items) {
            System.out.println(item);
        }

        while (count > 0) {
            count--;
        }

        do {
            count++;
        } while (count < 10);

        // Try-with-resources
        try (var scanner = new java.util.Scanner(System.in)) {
            String input = scanner.nextLine();
            System.out.println("Input: " + input);
        } catch (Exception e) {
            e.printStackTrace();
        }

        // Anonymous class
        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                System.out.println("Running");
            }
        };

        // Lambda expressions
        Runnable lambda = () -> System.out.println("Lambda");
        java.util.function.Consumer<String> consumer = s -> System.out.println(s);
        java.util.function.BiFunction<Integer, Integer, Integer> add = (a, b) -> a + b;

        // Method reference
        List<String> list = Arrays.asList("a", "b", "c");
        list.forEach(System.out::println);

        // Synchronized block
        synchronized (example) {
            example.validate();
        }

        // Assertions
        assert count >= 0 : "Count must be non-negative";
    }
}

/*
 * Multi-line comment
 * demonstrating block comments
 * in Java source code
 */
