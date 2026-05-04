#!/usr/bin/env bash
# QA-SYN-012: SQL syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-012: SQL syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn012.sql" '-- Users table queries
SELECT u.id, u.name, u.email, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE u.active = TRUE
  AND u.created_at > '\''2024-01-01'\''
GROUP BY u.id, u.name, u.email
HAVING COUNT(o.id) > 5
ORDER BY order_count DESC
LIMIT 100;

/* Insert new records */
INSERT INTO users (name, email, active)
VALUES ('\''Alice'\'', '\''alice@example.com'\'', TRUE);

UPDATE users
SET active = FALSE, updated_at = NOW()
WHERE last_login < '\''2023-06-01'\'';

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10, 2) DEFAULT 0.00,
    stock INTEGER CHECK (stock >= 0)
);

DELETE FROM orders WHERE status = '\''cancelled'\'';')
qa_start "$file"

shot="$QA_TMPDIR/sql_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a SQL file in a terminal text editor with syntax highlighting. Verify ALL of these: (1) SQL keywords like SELECT, FROM, WHERE, JOIN, INSERT, UPDATE, CREATE, DELETE, INTO, VALUES, SET, ORDER BY, GROUP BY, HAVING are highlighted in a distinct color (typically uppercase keywords in blue/purple). (2) String literals in single quotes like '2024-01-01', 'Alice' are in a string color. (3) Comments (-- single line and /* multi-line */) are in a muted/gray color. (4) Numbers like 5, 100, 255, 0.00, 0 are in their own color. (5) SQL types like SERIAL, VARCHAR, DECIMAL, INTEGER are highlighted. (6) Boolean values TRUE and FALSE are highlighted. (7) At least 3 distinct colors are used." \
    "SQL syntax highlighting with keywords, strings, comments, types"

qa_keys "ctrl-q"

qa_summary
