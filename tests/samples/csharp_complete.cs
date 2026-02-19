// C# sample file demonstrating syntax features
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

#region Namespace Declaration
namespace MyApp.Models
{
#endregion

/// <summary>
/// XML documentation comment
/// </summary>
/// <param name="name">The name</param>

// Constants
public const int MAX_VALUE = 100;

// Enum
public enum Status
{
    Pending = 0,
    Active = 1,
    Completed = 2
}

// Interface
public interface IRepository<T> where T : class
{
    Task<IEnumerable<T>> GetAllAsync();
    Task<T?> GetByIdAsync(int id);
    Task SaveAsync(T entity);
}

// Record (C# 9+)
public record Person(string Name, int Age, string? Email = null);

// Struct
public struct Point
{
    public int X { get; init; }
    public int Y { get; init; }

    public Point(int x, int y) => (X, Y) = (x, y);
}

// Class with generics
public class Repository<T> : IRepository<T> where T : class, new()
{
    private readonly List<T> _items = new();

    public async Task<IEnumerable<T>> GetAllAsync()
    {
        await Task.Delay(100);
        return _items.AsReadOnly();
    }

    public async Task<T?> GetByIdAsync(int id)
    {
        await Task.Delay(50);
        return _items.FirstOrDefault();
    }

    public async Task SaveAsync(T entity)
    {
        await Task.Delay(50);
        _items.Add(entity);
    }
}

// Main class
public class Program
{
    // Properties
    public string Name { get; set; } = "Default";
    public int Age { get; private set; }

    // Auto-property with init
    public required string Id { get; init; }

    // Events
    public event EventHandler<string>? OnChange;

    // Constructor
    public Program(int age)
    {
        Age = age;
    }

    // Async method
    public async Task<string> FetchDataAsync(string url)
    {
        await Task.Delay(1000);
        return $"Data from {url}";
    }

    // Static method
    public static void Main(string[] args)
    {
        // Variable declarations
        var message = "Hello, World!";
        string? nullable = null;
        int number = 42;

        // String interpolation
        var greeting = $"Message: {message}, Number: {number}";

        // Verbatim string
        var path = @"C:\Users\test\file.txt";

        // Raw string literal (C# 11)
        var json = """
            {
                "name": "test",
                "value": 123
            }
            """;

        // Collections
        var list = new List<int> { 1, 2, 3, 4, 5 };
        var dict = new Dictionary<string, int>
        {
            ["one"] = 1,
            ["two"] = 2
        };

        // LINQ
        var filtered = list.Where(x => x > 2)
                          .Select(x => x * 2)
                          .ToList();

        var query = from n in list
                    where n > 2
                    orderby n descending
                    select n * 2;

        // Pattern matching
        object obj = "test";
        if (obj is string s && s.Length > 0)
        {
            Console.WriteLine(s);
        }

        // Switch expression
        var result = number switch
        {
            < 0 => "negative",
            0 => "zero",
            > 0 and < 100 => "positive",
            _ => "large"
        };

        // Null handling
        var length = nullable?.Length ?? 0;
        var forced = nullable!.Length;  // Null forgiving

        // Loops
        for (int i = 0; i < 10; i++)
        {
            if (i % 2 == 0) continue;
            Console.WriteLine(i);
        }

        foreach (var item in list)
        {
            Console.WriteLine(item);
        }

        // Try-catch-finally
        try
        {
            var parsed = int.Parse("42");
        }
        catch (FormatException ex) when (ex.Message.Contains("Input"))
        {
            Console.WriteLine($"Error: {ex.Message}");
        }
        catch (Exception)
        {
            throw;
        }
        finally
        {
            Console.WriteLine("Cleanup");
        }

        // Using statement
        using var stream = new System.IO.MemoryStream();

        // Lambda expressions
        Func<int, int, int> add = (a, b) => a + b;
        Action<string> print = msg => Console.WriteLine(msg);

        // Async/await
        _ = Task.Run(async () =>
        {
            await Task.Delay(1000);
            Console.WriteLine("Done");
        });

        // Tuple
        var (name, age) = ("Alice", 30);
        var tuple = (Name: "Bob", Age: 25);

        // Numbers
        var integer = 42;
        var floating = 3.14;
        var hex = 0xFF;
        var binary = 0b1010;
        var underscore = 1_000_000;
    }

    // Attribute
    [Obsolete("Use NewMethod instead")]
    public void OldMethod() { }
}

} // end namespace
