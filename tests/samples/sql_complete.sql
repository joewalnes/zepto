-- SQL sample file demonstrating various dialects
-- MySQL, PostgreSQL, SQLite, DuckDB, Trino/Presto

/* Multi-line comment
   for documentation */

-- Create database and schema
CREATE DATABASE IF NOT EXISTS myapp;
USE myapp;

-- Create table with various types
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255),
    age INTEGER DEFAULT 0,
    salary DECIMAL(10, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB,
    tags TEXT[]
);

-- Create index
CREATE INDEX idx_users_email ON users(email);
CREATE UNIQUE INDEX idx_username ON users(username);

-- Insert data
INSERT INTO users (username, email, age, salary)
VALUES ('john_doe', 'john@example.com', 30, 50000.00);

INSERT INTO users (username, email, age)
VALUES
    ('jane_doe', 'jane@example.com', 25),
    ('bob_smith', 'bob@example.com', 35);

-- Select with various clauses
SELECT
    u.id,
    u.username,
    UPPER(u.email) AS email_upper,
    COALESCE(u.age, 0) AS age,
    COUNT(*) OVER (PARTITION BY u.is_active) AS active_count
FROM users u
WHERE u.age >= 18
    AND u.is_active = TRUE
    AND u.email LIKE '%@example.com'
ORDER BY u.created_at DESC
LIMIT 10 OFFSET 0;

-- Join example
SELECT
    u.username,
    o.order_id,
    o.total
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
INNER JOIN products p ON o.product_id = p.id
WHERE o.status IN ('pending', 'completed')
GROUP BY u.username, o.order_id, o.total
HAVING SUM(o.total) > 100;

-- Subquery
SELECT * FROM users
WHERE id IN (
    SELECT user_id FROM orders WHERE total > 1000
);

-- CTE (Common Table Expression)
WITH active_users AS (
    SELECT * FROM users WHERE is_active = TRUE
),
recent_orders AS (
    SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days'
)
SELECT au.username, COUNT(ro.order_id) AS order_count
FROM active_users au
JOIN recent_orders ro ON au.id = ro.user_id
GROUP BY au.username;

-- Window functions
SELECT
    username,
    salary,
    ROW_NUMBER() OVER (ORDER BY salary DESC) AS rank,
    LAG(salary) OVER (ORDER BY salary) AS prev_salary,
    LEAD(salary) OVER (ORDER BY salary) AS next_salary,
    AVG(salary) OVER () AS avg_salary
FROM users;

-- Update statement
UPDATE users
SET age = age + 1,
    updated_at = NOW()
WHERE username = 'john_doe';

-- Delete statement
DELETE FROM users WHERE is_active = FALSE;

-- PostgreSQL specific: Dollar-quoted string
CREATE OR REPLACE FUNCTION greet(name TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN 'Hello, ' || name || '!';
END;
$$ LANGUAGE plpgsql;

-- MySQL specific: Variables
SET @user_count = (SELECT COUNT(*) FROM users);
SELECT @user_count;

-- Transaction
BEGIN TRANSACTION;
INSERT INTO users (username) VALUES ('temp_user');
ROLLBACK;

-- View
CREATE VIEW active_user_view AS
SELECT id, username, email
FROM users
WHERE is_active = TRUE;

-- Numeric literals
SELECT 42, 3.14, 1e10, 0xFF, -99.99;
