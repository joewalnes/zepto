// Complete C example demonstrating syntax highlighting
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// Macro definitions
#define MAX_SIZE 1024
#define MIN(a, b) ((a) < (b) ? (a) : (b))

// Type definitions
typedef unsigned int uint;
typedef struct Node Node;

// Enum declaration
enum Status {
    STATUS_OK = 0,
    STATUS_ERROR = 1,
    STATUS_PENDING = 2
};

// Struct declaration
struct Node {
    int value;
    struct Node *next;
    char name[64];
};

// Union example
union Data {
    int i;
    float f;
    char str[20];
};

// Function prototypes
static int compare(const void *a, const void *b);
int process_data(int *arr, size_t len);
Node* create_node(int value, const char *name);

// Static variable
static int counter = 0;

// Main function
int main(int argc, char *argv[]) {
    // Variable declarations
    int count = 42;
    long big_number = 123456789L;
    double pi = 3.14159265358979;
    float ratio = 0.5f;
    bool flag = true;
    char letter = 'A';
    char *message = "Hello, World!";

    // Array declarations
    int numbers[5] = {1, 2, 3, 4, 5};
    int *dynamic_arr = malloc(10 * sizeof(int));

    // Pointer arithmetic
    int *ptr = numbers;
    ptr++;
    *ptr = 100;

    // Hex, octal, binary literals
    int hex_val = 0xFF;
    int oct_val = 0777;
    unsigned long ulong = 0xDEADBEEFUL;

    // Control flow
    if (count > 0) {
        printf("Positive: %d\n", count);
    } else if (count < 0) {
        printf("Negative\n");
    } else {
        printf("Zero\n");
    }

    // Switch statement
    enum Status status = STATUS_OK;
    switch (status) {
        case STATUS_OK:
            printf("OK\n");
            break;
        case STATUS_ERROR:
            printf("Error\n");
            break;
        default:
            printf("Unknown\n");
    }

    // Loops
    for (int i = 0; i < 10; i++) {
        if (i == 5) continue;
        if (i == 8) break;
        printf("%d\n", i);
    }

    while (count > 0) {
        count--;
    }

    do {
        count++;
    } while (count < 10);

    // Struct usage
    Node *node = create_node(42, "test");
    printf("Node: %s = %d\n", node->name, node->value);

    // Memory management
    free(dynamic_arr);
    free(node);

    return 0;
}

// Function implementation
Node* create_node(int value, const char *name) {
    Node *node = malloc(sizeof(Node));
    if (node == NULL) {
        perror("malloc failed");
        return NULL;
    }
    node->value = value;
    strncpy(node->name, name, sizeof(node->name) - 1);
    node->name[sizeof(node->name) - 1] = '\0';
    node->next = NULL;
    return node;
}

int process_data(int *arr, size_t len) {
    int sum = 0;
    for (size_t i = 0; i < len; i++) {
        sum += arr[i];
    }
    return sum;
}

static int compare(const void *a, const void *b) {
    return (*(int*)a - *(int*)b);
}

/*
 * Multi-line comment
 * explaining the algorithm
 */
