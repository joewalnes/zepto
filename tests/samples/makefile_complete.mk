# =============================================================================
# Complete Makefile Example - Demonstrating various syntax elements
# =============================================================================

# Variables
CC := gcc
CXX := g++
CFLAGS := -Wall -Wextra -O2
CXXFLAGS := $(CFLAGS) -std=c++17
LDFLAGS := -lpthread -lm

# Directories
SRC_DIR := src
BUILD_DIR := build
BIN_DIR := bin
INCLUDE_DIR := include

# File patterns
SOURCES := $(wildcard $(SRC_DIR)/*.c)
OBJECTS := $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)
HEADERS := $(wildcard $(INCLUDE_DIR)/*.h)

# Target executable
TARGET := $(BIN_DIR)/program

# Environment variables
PREFIX ?= /usr/local
DESTDIR ?=
DEBUG ?= 0

# Conditional assignment
ifeq ($(DEBUG),1)
    CFLAGS += -g -DDEBUG
else
    CFLAGS += -DNDEBUG
endif

# Shell commands
VERSION := $(shell git describe --tags 2>/dev/null || echo "unknown")
DATE := $(shell date +%Y-%m-%d)
UNAME := $(shell uname -s)

# OS-specific settings
ifeq ($(UNAME),Linux)
    LDFLAGS += -lrt
else ifeq ($(UNAME),Darwin)
    LDFLAGS += -framework CoreFoundation
endif

# Default target
.DEFAULT_GOAL := all

# Phony targets
.PHONY: all clean install uninstall test check lint format docs help

# Build all targets
all: directories $(TARGET)

# Create build directories
directories:
	@mkdir -p $(BUILD_DIR) $(BIN_DIR)

# Link object files into executable
$(TARGET): $(OBJECTS)
	@echo "Linking $@..."
	$(CC) $(OBJECTS) -o $@ $(LDFLAGS)

# Compile source files
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c $(HEADERS)
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -I$(INCLUDE_DIR) -c $< -o $@

# Pattern rule for C++ files
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp
	$(CXX) $(CXXFLAGS) -I$(INCLUDE_DIR) -c $< -o $@

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -rf $(BUILD_DIR) $(BIN_DIR)
	find . -name "*.o" -delete
	find . -name "*~" -delete

# Install to system
install: $(TARGET)
	@echo "Installing to $(DESTDIR)$(PREFIX)/bin..."
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 $(TARGET) $(DESTDIR)$(PREFIX)/bin/

# Uninstall from system
uninstall:
	@echo "Uninstalling..."
	rm -f $(DESTDIR)$(PREFIX)/bin/$(notdir $(TARGET))

# Run tests
test: $(TARGET)
	@echo "Running tests..."
	./$(TARGET) --test
	@echo "All tests passed!"

# Static analysis
check:
	cppcheck --enable=all $(SRC_DIR)

# Lint source files
lint:
	clang-tidy $(SOURCES) -- $(CFLAGS) -I$(INCLUDE_DIR)

# Format source files
format:
	clang-format -i $(SRC_DIR)/*.c $(INCLUDE_DIR)/*.h

# Generate documentation
docs:
	doxygen Doxyfile

# Function definition
define compile_template
$(BUILD_DIR)/$(1).o: $(SRC_DIR)/$(1).c
	$$(CC) $$(CFLAGS) -c $$< -o $$@
endef

# Generate rules from list
MODULES := main utils parser
$(foreach mod,$(MODULES),$(eval $(call compile_template,$(mod))))

# Multi-line recipe
complex_task:
	@echo "Step 1: Preparing..."
	@sleep 1
	@echo "Step 2: Processing..."
	@for i in 1 2 3; do \
		echo "  Iteration $$i"; \
	done
	@echo "Step 3: Done!"

# Silent prefix and error handling
robust_clean:
	-@rm -f $(BUILD_DIR)/*.o 2>/dev/null || true
	-@rmdir $(BUILD_DIR) 2>/dev/null || true

# Export variables to sub-makes
export CC CXX CFLAGS

# Include generated dependencies
-include $(OBJECTS:.o=.d)

# Generate dependency files
$(BUILD_DIR)/%.d: $(SRC_DIR)/%.c
	@$(CC) -MM -MT $(@:.d=.o) $(CFLAGS) $< > $@

# Print help
help:
	@echo "Available targets:"
	@echo "  all       - Build the project (default)"
	@echo "  clean     - Remove build artifacts"
	@echo "  install   - Install to $(PREFIX)"
	@echo "  uninstall - Remove from $(PREFIX)"
	@echo "  test      - Run tests"
	@echo "  check     - Run static analysis"
	@echo "  lint      - Run linter"
	@echo "  format    - Format source code"
	@echo "  docs      - Generate documentation"
	@echo "  help      - Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  DEBUG=1   - Enable debug build"
	@echo "  PREFIX    - Install prefix (default: /usr/local)"

# Debug target
debug:
	@echo "CC: $(CC)"
	@echo "CFLAGS: $(CFLAGS)"
	@echo "SOURCES: $(SOURCES)"
	@echo "OBJECTS: $(OBJECTS)"
	@echo "VERSION: $(VERSION)"
