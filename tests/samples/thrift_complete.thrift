// Thrift sample file demonstrating syntax features
// Apache Thrift IDL for a user service

namespace java com.example.user
namespace py example.user
namespace cpp example.user
namespace go example.user

include "common.thrift"

// Constants
const i32 MAX_USERS = 1000
const string DEFAULT_ROLE = "guest"
const list<string> ADMIN_ROLES = ["admin", "superuser"]
const map<string, i32> ERROR_CODES = {
    "NOT_FOUND": 404,
    "UNAUTHORIZED": 401,
    "INTERNAL_ERROR": 500
}

// Type definitions
typedef i64 UserId
typedef string Email
typedef map<string, string> Metadata

// Enumerations
enum UserStatus {
    UNKNOWN = 0,
    ACTIVE = 1,
    INACTIVE = 2,
    SUSPENDED = 3,
    DELETED = 4
}

enum Role {
    GUEST = 0,
    USER = 1,
    MODERATOR = 2,
    ADMIN = 3
}

// Exception definitions
exception UserNotFoundException {
    1: required UserId userId,
    2: optional string message
}

exception AuthenticationException {
    1: required string reason,
    2: optional i32 errorCode
}

exception ValidationException {
    1: required string field,
    2: required string message,
    3: optional map<string, string> details
}

// Struct definitions
struct Address {
    1: required string street,
    2: required string city,
    3: required string state,
    4: required string country,
    5: optional string postalCode,
    6: optional double latitude,
    7: optional double longitude
}

struct User {
    1: required UserId id,
    2: required string username,
    3: required Email email,
    4: optional string firstName,
    5: optional string lastName,
    6: required UserStatus status = UserStatus.ACTIVE,
    7: required Role role = Role.USER,
    8: optional Address address,
    9: optional list<string> tags,
    10: optional map<string, string> attributes,
    11: required i64 createdAt,
    12: optional i64 updatedAt
}

struct UserList {
    1: required list<User> users,
    2: required i32 total,
    3: optional string nextPageToken
}

struct CreateUserRequest {
    1: required string username,
    2: required Email email,
    3: optional string firstName,
    4: optional string lastName,
    5: optional Address address
}

struct UpdateUserRequest {
    1: required UserId id,
    2: optional string email,
    3: optional string firstName,
    4: optional string lastName,
    5: optional UserStatus status,
    6: optional Address address
}

struct SearchQuery {
    1: optional string query,
    2: optional UserStatus status,
    3: optional Role role,
    4: optional i32 limit = 20,
    5: optional i32 offset = 0
}

// Union type
union UserIdentifier {
    1: UserId id,
    2: string username,
    3: Email email
}

// Service definition
service UserService {
    // Get a user by ID
    User getUser(1: UserId id) throws (
        1: UserNotFoundException notFound,
        2: AuthenticationException authError
    ),

    // Get a user by identifier (id, username, or email)
    User getUserByIdentifier(1: UserIdentifier identifier) throws (
        1: UserNotFoundException notFound
    ),

    // Create a new user
    User createUser(1: CreateUserRequest request) throws (
        1: ValidationException validationError
    ),

    // Update an existing user
    User updateUser(1: UpdateUserRequest request) throws (
        1: UserNotFoundException notFound,
        2: ValidationException validationError
    ),

    // Delete a user
    void deleteUser(1: UserId id) throws (
        1: UserNotFoundException notFound
    ),

    // Search users
    UserList searchUsers(1: SearchQuery query),

    // Batch operations
    list<User> batchGetUsers(1: list<UserId> ids),

    // Async/oneway operation (fire and forget)
    oneway void logUserAction(1: UserId userId, 2: string action),

    // Check if username exists
    bool usernameExists(1: string username),

    // Get user count
    i64 getUserCount()
}

// Extended service
service AdminUserService extends UserService {
    // Admin-only operations
    void suspendUser(1: UserId id, 2: string reason) throws (
        1: UserNotFoundException notFound
    ),

    void restoreUser(1: UserId id) throws (
        1: UserNotFoundException notFound
    ),

    UserList getAllUsers(1: i32 limit, 2: i32 offset),

    void purgeDeletedUsers()
}
