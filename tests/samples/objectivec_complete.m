// Objective-C sample file demonstrating syntax features
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MyClass.h"

// Preprocessor
#define MAX_SIZE 100
#define SQUARE(x) ((x) * (x))
#define LOG(fmt, ...) NSLog(@"[DEBUG] " fmt, ##__VA_ARGS__)

#pragma mark - Constants

static NSString *const kAppVersion = @"1.0.0";
static const CGFloat kDefaultMargin = 16.0;

typedef NS_ENUM(NSInteger, Status) {
    StatusPending = 0,
    StatusActive = 1,
    StatusCompleted = 2
};

typedef NS_OPTIONS(NSUInteger, Options) {
    OptionNone = 0,
    OptionFirst = 1 << 0,
    OptionSecond = 1 << 1,
    OptionThird = 1 << 2
};

#pragma mark - Protocol Definition

@protocol Greetable <NSObject>

@required
- (NSString *)greet:(NSString *)name;

@optional
- (void)sayGoodbye;

@end

#pragma mark - Forward Declarations

@class Helper;

#pragma mark - Interface

NS_ASSUME_NONNULL_BEGIN

@interface Person : NSObject <Greetable, NSCopying>

// Properties
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger age;
@property (nonatomic, strong, nullable) NSString *email;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, weak) id<Greetable> delegate;

// Class methods
+ (instancetype)personWithName:(NSString *)name age:(NSInteger)age;
+ (NSArray<Person *> *)allPeople;

// Instance methods
- (instancetype)initWithName:(NSString *)name age:(NSInteger)age NS_DESIGNATED_INITIALIZER;
- (void)updateEmail:(nullable NSString *)email;
- (BOOL)isAdult;

@end

NS_ASSUME_NONNULL_END

#pragma mark - Implementation

@implementation Person {
    // Instance variable
    NSMutableArray *_privateArray;
}

@synthesize name = _name;
@dynamic displayName;

#pragma mark Lifecycle

+ (instancetype)personWithName:(NSString *)name age:(NSInteger)age {
    return [[self alloc] initWithName:name age:age];
}

- (instancetype)init {
    return [self initWithName:@"Unknown" age:0];
}

- (instancetype)initWithName:(NSString *)name age:(NSInteger)age {
    self = [super init];
    if (self) {
        _name = [name copy];
        _age = age;
        _privateArray = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    NSLog(@"Person deallocated: %@", _name);
}

#pragma mark Accessors

- (NSString *)displayName {
    return [_name uppercaseString];
}

- (void)setName:(NSString *)name {
    if (![_name isEqualToString:name]) {
        _name = [name copy];
    }
}

#pragma mark Public Methods

- (void)updateEmail:(NSString *)email {
    self.email = email;
}

- (BOOL)isAdult {
    return self.age >= 18;
}

+ (NSArray<Person *> *)allPeople {
    static NSMutableArray *people = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        people = [[NSMutableArray alloc] init];
    });
    return [people copy];
}

#pragma mark Greetable Protocol

- (NSString *)greet:(NSString *)name {
    return [NSString stringWithFormat:@"Hello, %@! I'm %@.", name, self.name];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone {
    Person *copy = [[Person allocWithZone:zone] initWithName:self.name age:self.age];
    copy.email = self.email;
    return copy;
}

#pragma mark NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<Person: %@, age: %ld>", self.name, (long)self.age];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[Person class]]) return NO;
    Person *other = (Person *)object;
    return [self.name isEqualToString:other.name] && self.age == other.age;
}

- (NSUInteger)hash {
    return [self.name hash] ^ self.age;
}

@end

#pragma mark - Category

@interface NSString (Utils)
- (NSString *)reverse;
@end

@implementation NSString (Utils)
- (NSString *)reverse {
    NSMutableString *reversed = [NSMutableString string];
    for (NSInteger i = self.length - 1; i >= 0; i--) {
        [reversed appendFormat:@"%c", [self characterAtIndex:i]];
    }
    return reversed;
}
@end

#pragma mark - Class Extension

@interface Person ()
@property (nonatomic, strong) NSMutableArray *privateItems;
- (void)privateMethod;
@end

@implementation Person (Private)
- (void)privateMethod {
    NSLog(@"Private method called");
}
@end

#pragma mark - Main Function

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Object creation
        Person *person = [[Person alloc] initWithName:@"Alice" age:30];
        Person *person2 = [Person personWithName:@"Bob" age:25];

        // Literal syntax
        NSString *string = @"Hello, World!";
        NSNumber *number = @42;
        NSNumber *floating = @3.14;
        NSNumber *boolean = @YES;
        NSArray *array = @[@"one", @"two", @"three"];
        NSDictionary *dict = @{@"key": @"value", @"foo": @"bar"};

        // Boxing expressions
        NSNumber *boxed = @(MAX_SIZE * 2);
        NSNumber *result = @(1 + 2);

        // Collection subscripting
        NSString *first = array[0];
        NSString *value = dict[@"key"];

        // Method calls
        NSString *greeting = [person greet:@"World"];
        [person updateEmail:@"alice@example.com"];

        // Nested method calls
        NSString *upper = [[person.name uppercaseString] stringByAppendingString:@"!"];

        // Dot notation vs bracket notation
        NSInteger age1 = person.age;
        NSInteger age2 = [person age];

        // Blocks
        void (^simpleBlock)(void) = ^{
            NSLog(@"Simple block");
        };

        NSInteger (^addBlock)(NSInteger, NSInteger) = ^NSInteger(NSInteger a, NSInteger b) {
            return a + b;
        };

        __block NSInteger counter = 0;
        void (^incrementBlock)(void) = ^{
            counter++;
        };

        // GCD
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_async(queue, ^{
            NSLog(@"Background task");
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"Back on main thread");
            });
        });

        // Error handling
        NSError *error = nil;
        NSString *contents = [NSString stringWithContentsOfFile:@"/tmp/test.txt"
                                                       encoding:NSUTF8StringEncoding
                                                          error:&error];
        if (error) {
            NSLog(@"Error: %@", error.localizedDescription);
        }

        // Exception handling
        @try {
            [NSException raise:@"TestException" format:@"Test message"];
        }
        @catch (NSException *exception) {
            NSLog(@"Caught: %@", exception.reason);
        }
        @finally {
            NSLog(@"Cleanup");
        }

        // Fast enumeration
        for (NSString *item in array) {
            NSLog(@"%@", item);
        }

        // Control flow
        if ([person isAdult]) {
            NSLog(@"Adult");
        } else {
            NSLog(@"Minor");
        }

        switch (person.age) {
            case 0 ... 12:
                NSLog(@"Child");
                break;
            case 13 ... 19:
                NSLog(@"Teenager");
                break;
            default:
                NSLog(@"Adult");
                break;
        }

        // Selector
        SEL selector = @selector(greet:);
        if ([person respondsToSelector:selector]) {
            NSLog(@"Person responds to greet:");
        }

        // Type encoding
        const char *encoding = @encode(NSInteger);
        NSLog(@"NSInteger encoding: %s", encoding);

        // Numbers
        int integer = 42;
        long longVal = 42L;
        float floatVal = 3.14f;
        double doubleVal = 3.14;
        CGFloat cgFloat = 10.0;

        return 0;
    }
}
