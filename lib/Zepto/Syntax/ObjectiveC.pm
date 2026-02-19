package Zepto::Syntax::ObjectiveC;
# =============================================================================
# Objective-C Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

# C keywords plus Objective-C additions
my $KEYWORDS = qr/\b(?:
    auto | break | case | const | continue | default | do | else |
    enum | extern | for | goto | if | inline | register | restrict |
    return | sizeof | static | struct | switch | typedef | union |
    volatile | while |
    _Bool | _Complex | _Imaginary | _Alignas | _Alignof | _Atomic |
    _Generic | _Noreturn | _Static_assert | _Thread_local |
    true | false | NULL | nil | Nil | YES | NO | self | super |
    id | Class | SEL | IMP | BOOL |
    in | out | inout | bycopy | byref | oneway |
    getter | setter | readwrite | readonly | assign | retain | copy |
    nonatomic | atomic | strong | weak | unsafe_unretained |
    nonnull | nullable | null_resettable | null_unspecified |
    NS_ASSUME_NONNULL_BEGIN | NS_ASSUME_NONNULL_END |
    __strong | __weak | __unsafe_unretained | __autoreleasing |
    __block | __bridge | __bridge_retained | __bridge_transfer |
    instancetype | typeof | __typeof | __typeof__
)\b/x;

# Objective-C directives
my $DIRECTIVES = qr/@(?:
    interface | implementation | protocol | end | private | protected |
    public | package | required | optional | property | synthesize |
    dynamic | selector | encode | defs | class | throw | try | catch |
    finally | synchronized | autoreleasepool | compatibility_alias |
    import | available
)\b/x;

my $TYPES = qr/\b(?:
    void | char | short | int | long | float | double | signed | unsigned |
    int8_t | int16_t | int32_t | int64_t |
    uint8_t | uint16_t | uint32_t | uint64_t |
    size_t | ssize_t | ptrdiff_t | intptr_t | uintptr_t |
    NSInteger | NSUInteger | CGFloat | NSTimeInterval |
    NSObject | NSString | NSMutableString | NSNumber | NSValue |
    NSArray | NSMutableArray | NSDictionary | NSMutableDictionary |
    NSSet | NSMutableSet | NSOrderedSet | NSMutableOrderedSet |
    NSData | NSMutableData | NSDate | NSURL | NSError |
    NSIndexSet | NSIndexPath | NSRange | NSNotification |
    NSBundle | NSFileManager | NSProcessInfo | NSThread |
    NSLock | NSCondition | NSRecursiveLock | NSOperation | NSOperationQueue |
    NSTimer | NSRunLoop | NSNotificationCenter | NSUserDefaults |
    NSAttributedString | NSMutableAttributedString |
    NSPredicate | NSSortDescriptor | NSExpression |
    NSFormatter | NSNumberFormatter | NSDateFormatter |
    NSException | NSAssertionHandler |
    NSNull | NSProxy | NSInvocation | NSMethodSignature |
    UIView | UIViewController | UIApplication | UIWindow | UIButton |
    UILabel | UIImageView | UITableView | UICollectionView |
    CGRect | CGPoint | CGSize | CGAffineTransform |
    CALayer | CAAnimation | CABasicAnimation |
    dispatch_queue_t | dispatch_block_t | dispatch_semaphore_t |
    FILE | va_list | wchar_t | wint_t
)\b/x;

my $BUILTINS = qr/\b(?:
    NSLog | NSAssert | NSCAssert | NSParameterAssert | NSCParameterAssert |
    NSLocalizedString | NSLocalizedStringFromTable |
    NSMakeRange | NSEqualRanges | NSLocationInRange | NSMaxRange |
    CGRectMake | CGPointMake | CGSizeMake | CGRectZero | CGPointZero |
    CGSizeZero | CGRectGetMinX | CGRectGetMaxX | CGRectGetMinY |
    CGRectGetMaxY | CGRectGetWidth | CGRectGetHeight |
    dispatch_async | dispatch_sync | dispatch_after | dispatch_once |
    dispatch_get_main_queue | dispatch_get_global_queue |
    printf | fprintf | sprintf | snprintf | scanf | fscanf | sscanf |
    malloc | calloc | realloc | free |
    memcpy | memmove | memset | memcmp |
    strcpy | strncpy | strcat | strncat | strcmp | strncmp | strlen
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue block comment
    if ($state == STATE_COMMENT_BLOCK) {
        if ($line =~ /^(.*?)\*\//) {
            push @tokens, _token(0, length($1) + 2, TOKEN_COMMENT);
            $pos = length($1) + 2;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_COMMENT_BLOCK);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Preprocessor directive
        if ($pos == 0 && $rest =~ /^(\s*#\s*\w+)/) {
            push @tokens, _token(0, length($1), TOKEN_KEYWORD);
            $pos = length($1);

            $rest = substr($line, $pos);
            # #import <...> or "..." or #include
            if ($rest =~ /^(\s*)(<[^>]+>|"[^"]+")/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_STRING);
                $pos += length($2);
            }
            next;
        }

        # Line comment
        if ($rest =~ m{^(//.*)} ) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Block comment
        if ($rest =~ m{^(/\*)}) {
            if ($rest =~ m{^(/\*.*?\*/)}) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_COMMENT_BLOCK);
            }
            next;
        }

        # Objective-C directive (@interface, @implementation, etc.)
        if ($rest =~ /^($DIRECTIVES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);

            # Check for class/protocol name after directive
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s+)(\w+)/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_TYPE);
                $pos += length($2);
            }
            next;
        }

        # @"string" NSString literal
        if ($rest =~ /^(@"(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # @selector(...)
        if ($rest =~ /^(\@selector)\s*\(([^)]*)\)/) {
            push @tokens, _token($pos, $pos + 9, TOKEN_KEYWORD);
            $pos += 9;
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s*\()([^)]*)(\))/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_FUNCTION);
                $pos += length($2);
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
            }
            next;
        }

        # @encode(...)
        if ($rest =~ /^(\@encode)\s*\(([^)]*)\)/) {
            push @tokens, _token($pos, $pos + 7, TOKEN_KEYWORD);
            $pos += 7;
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s*\()([^)]*)(\))/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_TYPE);
                $pos += length($2);
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
            }
            next;
        }

        # @[ ] array literal, @{ } dictionary literal, @( ) boxed expression
        if ($rest =~ /^(@[\[\({])/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_OPERATOR);
            $pos += 2;
            next;
        }

        # @YES, @NO, @true, @false, @123 (boxed literals)
        if ($rest =~ /^(@(?:YES|NO|true|false|\d+\.?\d*))/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # C string literal
        if ($rest =~ /^(L?"(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Character literal
        if ($rest =~ /^(L?'(?:[^'\\]|\\.)')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Method declaration - (type) or + (type)
        if ($rest =~ /^([+-])\s*\(/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_KEYWORD);
            $pos += 1;
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Built-in types
        if ($rest =~ /^($TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Built-in functions
        if ($rest =~ /^($BUILTINS)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F]+[uUlL]*|0b[01]+[uUlL]*|\d+\.?\d*(?:e[+-]?\d+)?[fFlLuU]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(->|<<|>>|\+\+|--|&&|\|\||[+\-*\/%&|^<>=!]=?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Message send brackets [ ]
        if ($rest =~ /^([\[\]])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Method selector part (word followed by colon in message)
        if ($rest =~ /^(\w+):(?!\s*\))/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # Function call
        if ($rest =~ /^(\w+)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # CONSTANT_NAME or macro
        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Type name (PascalCase or ending in _t)
        if ($rest =~ /^(NS[A-Z][a-zA-Z0-9]*|UI[A-Z][a-zA-Z0-9]*|CG[A-Z][a-zA-Z0-9]*|CA[A-Z][a-zA-Z0-9]*|[A-Z][a-zA-Z0-9]*|[a-z][a-zA-Z0-9]*_t)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
