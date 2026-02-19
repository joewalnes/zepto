#!/usr/bin/env Rscript
# R Language syntax highlighting sample

library(ggplot2)
library(dplyr)
library(tidyr)
require(stringr)

# Variables and assignment
x <- 42
y = 3.14
z <<- TRUE
name <- "Hello, World!"
empty_val <- NULL
missing_val <- NA
complex_num <- 3+2i

# Vectors and sequences
numbers <- c(1, 2, 3, 4, 5)
letters_vec <- c("a", "b", "c")
logical_vec <- c(TRUE, FALSE, TRUE)
seq_vec <- seq(1, 100, by = 5)
rep_vec <- rep(0, times = 10)
range_vec <- 1:10

# Data frames
df <- data.frame(
    id = 1:5,
    name = c("Alice", "Bob", "Charlie", "David", "Eve"),
    score = c(85.5, 92.3, 78.1, 95.0, 88.7),
    passed = c(TRUE, TRUE, FALSE, TRUE, TRUE),
    stringsAsFactors = FALSE
)

# Matrix operations
mat <- matrix(1:12, nrow = 3, ncol = 4)
identity_mat <- diag(3)
t_mat <- t(mat)
det_val <- det(identity_mat)

# Functions
calculate_stats <- function(data, na.rm = TRUE) {
    result <- list(
        mean = mean(data, na.rm = na.rm),
        median = median(data, na.rm = na.rm),
        sd = sd(data, na.rm = na.rm),
        min = min(data, na.rm = na.rm),
        max = max(data, na.rm = na.rm),
        n = length(data)
    )
    return(result)
}

# Control flow
classify_score <- function(score) {
    if (score >= 90) {
        grade <- "A"
    } else if (score >= 80) {
        grade <- "B"
    } else if (score >= 70) {
        grade <- "C"
    } else {
        grade <- "F"
    }
    return(grade)
}

# Loops
results <- numeric(100)
for (i in seq_along(results)) {
    results[i] <- sqrt(i) * log(i + 1)
}

counter <- 0
while (counter < 10) {
    counter <- counter + 1
    if (counter == 5) next
    cat(sprintf("Count: %d\n", counter))
}

# Apply family
squared <- sapply(1:10, function(x) x^2)
filtered <- Filter(function(x) x > 50, squared)
total <- Reduce(`+`, filtered, accumulate = FALSE)

# dplyr pipe operations
summary_df <- df %>%
    filter(passed == TRUE) %>%
    mutate(grade = sapply(score, classify_score)) %>%
    arrange(desc(score)) %>%
    select(name, score, grade)

# String operations
greeting <- paste("Hello", "World", sep = ", ")
formatted <- sprintf("Score: %.2f%%", 95.5)
pattern <- grepl("^[A-Z]", df$name)
replaced <- gsub("_", " ", "hello_world_test")

# Error handling
safe_divide <- function(a, b) {
    tryCatch(
        {
            result <- a / b
            if (is.infinite(result)) stop("Division resulted in Inf")
            return(result)
        },
        error = function(e) {
            warning(paste("Error in division:", e$message))
            return(NA)
        },
        finally = {
            message("Division attempted")
        }
    )
}

# File I/O
if (file.exists("data.csv")) {
    data <- read.csv("data.csv", header = TRUE)
    write.csv(data, "output.csv", row.names = FALSE)
}

# List operations
my_list <- list(
    numbers = 1:5,
    text = "hello",
    nested = list(a = 1, b = 2)
)

# Type checking
is.numeric(42)
is.character("hello")
is.list(my_list)
as.integer(3.14)
as.character(42)

# S3 class
my_obj <- structure(
    list(data = df, name = "test"),
    class = "MyClass"
)

# Special operators
x %in% c(1, 2, 3)
result <- df |> head(3)
