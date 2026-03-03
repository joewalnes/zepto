package Zepto::Syntax::SQL;
# =============================================================================
# SQL Syntax Grammar
# =============================================================================
# Supports common SQL dialects: MySQL, PostgreSQL, SQLite, DuckDB, Trino/Presto

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '--' }

# Standard SQL keywords (all dialects combined)
my $KEYWORDS = qr/\b(?:
    ADD | ALL | ALTER | AND | ANY | AS | ASC | AUTHORIZATION |
    BACKUP | BEGIN | BETWEEN | BREAK | BROWSE | BULK | BY |
    CASCADE | CASE | CHECK | CHECKPOINT | CLOSE | CLUSTERED | COALESCE |
    COLLATE | COLUMN | COMMIT | COMPUTE | CONSTRAINT | CONTAINS |
    CONTAINSTABLE | CONTINUE | CONVERT | CREATE | CROSS | CURRENT |
    CURRENT_DATE | CURRENT_TIME | CURRENT_TIMESTAMP | CURRENT_USER | CURSOR |
    DATABASE | DBCC | DEALLOCATE | DECLARE | DEFAULT | DELETE | DENY | DESC |
    DISK | DISTINCT | DISTRIBUTED | DO | DROP | DUMP | ELSE | END | ERRLVL |
    ESCAPE | EXCEPT | EXEC | EXECUTE | EXISTS | EXIT | EXTERNAL | FETCH |
    FILE | FILLFACTOR | FOR | FOREIGN | FREETEXT | FREETEXTTABLE | FROM |
    FULL | FUNCTION | GOTO | GRANT | GROUP | HAVING | HOLDLOCK | IDENTITY |
    IDENTITY_INSERT | IDENTITYCOL | IF | IGNORE | IN | INDEX | INNER | INSERT |
    INTERSECT | INTO | IS | JOIN | KEY | KILL | LEFT | LIKE | LIMIT | LINENO |
    LOAD | LOCK | MERGE | NATIONAL | NOCHECK | NONCLUSTERED | NOT | NULL |
    NULLIF | OF | OFF | OFFSETS | ON | OPEN | OPENDATASOURCE | OPENQUERY |
    OPENROWSET | OPENXML | OPTION | OR | ORDER | OUTER | OVER | PARTITION |
    PERCENT | PIVOT | PLAN | PRECISION | PRIMARY | PRINT | PROC | PROCEDURE |
    PUBLIC | RAISERROR | READ | READTEXT | RECONFIGURE | REFERENCES |
    REPLICATION | RESTORE | RESTRICT | RETURN | REVOKE | RIGHT | ROLLBACK |
    ROWCOUNT | ROWGUIDCOL | RULE | SAVE | SCHEMA | SELECT | SESSION_USER |
    SET | SETUSER | SHUTDOWN | SOME | STATISTICS | SYSTEM_USER | TABLE |
    TABLESAMPLE | TEXTSIZE | THEN | TO | TOP | TRAN | TRANSACTION | TRIGGER |
    TRUNCATE | TRY_CONVERT | TSEQUAL | UNION | UNIQUE | UNPIVOT | UPDATE |
    UPDATETEXT | USE | USER | VALUES | VARYING | VIEW | WAITFOR | WHEN |
    WHERE | WHILE | WITH | WITHIN | WRITETEXT |
    ANALYZE | ANALYSE | ARRAY | CONCURRENTLY | CONFLICT | EXCLUSION |
    EXPLAIN | ILIKE | ISNULL | LATERAL | MATERIALIZED | NOTNULL |
    ONLY | OWNED | OWNER | POLICY | RECURSIVE | REINDEX | REPLICA | RETURNING |
    SERIAL | SEQUENCES | SHARE | SIMILAR | TABLES | TEMP | TEMPORARY | VACUUM |
    WINDOW | XMLPARSE | XMLROOT | XMLSERIALIZE |
    AUTO_INCREMENT | BINARY | BLOB | CHANGE | CHARACTER | CHARSET | COLLATION |
    DATA | DATABASES | DAY_HOUR | DAY_MICROSECOND | DAY_MINUTE | DAY_SECOND |
    DELAYED | DESCRIBE | DETERMINISTIC | DISTINCTROW | DIV | DUAL | ENCLOSED |
    ENGINE | ENGINES | ENUM | ESCAPED | EXPANSION | FIELDS | FLOAT4 | FLOAT8 |
    FORCE | FULLTEXT | GEOMETRY | GEOMETRYCOLLECTION | HIGH_PRIORITY |
    HOUR_MICROSECOND | HOUR_MINUTE | HOUR_SECOND | INFILE | INOUT | INT1 |
    INT2 | INT3 | INT4 | INT8 | KEYS | LEADING | LINES | LINESTRING |
    LONGBLOB | LONGTEXT | LOW_PRIORITY | MASTER | MATCH | MEDIUMBLOB |
    MEDIUMINT | MEDIUMTEXT | MIDDLEINT | MINUTE_MICROSECOND | MINUTE_SECOND |
    MOD | MODIFY | MULTILINESTRING | MULTIPOINT | MULTIPOLYGON | OPTIMIZE |
    OPTIONALLY | OUTFILE | POINT | POLYGON | PROCESSLIST | PURGE | QUICK |
    REGEXP | RENAME | REPEAT | REPLACE | REQUIRE | RLIKE | SCHEMAS |
    SECOND_MICROSECOND | SEPARATOR | SHOW | SPATIAL | SQL_BIG_RESULT |
    SQL_BUFFER_RESULT | SQL_CACHE | SQL_CALC_FOUND_ROWS | SQL_NO_CACHE |
    SQL_SMALL_RESULT | SSL | STARTING | STATUS | STRAIGHT_JOIN |
    TERMINATED | TINYBLOB | TINYINT | TINYTEXT | TRAILING | TYPES | UNLOCK |
    UNSIGNED | USAGE | UTC_DATE | UTC_TIME | UTC_TIMESTAMP | VARIABLES |
    VARCHARACTER | WARNINGS | XOR | YEAR_MONTH | ZEROFILL |
    ABORT | ACTION | AFTER | ATTACH | AUTOINCREMENT | BEFORE |
    DETACH | GLOB | INDEXED | INSTEAD | OFFSET | PRAGMA |
    QUERY | RAISE | RELEASE | ROW | SAVEPOINT | VIRTUAL |
    ANTI | ASOF | COPY | CREDENTIAL | EXPORT | INSTALL | MACRO |
    PIVOT_LONGER | PIVOT_WIDER | POSITIONAL | QUALIFY | SAMPLE | SECRETS |
    SEMI | SEQUENCE | SUMMARIZE |
    BERNOULLI | CATALOG | COLUMNS | COMMENT | COST | DEFINER | FORMAT |
    GRAPHVIZ | INPUT | IO | INVOKER | ISOLATION | JSON | LEVEL | LOGICAL |
    NFC | NFD | NFKC | NFKD | NONE | ORDINALITY | OUTPUT | PARAMETRIC |
    PRIVILEGES | PROPERTIES | RANGE | REPEATABLE | RESET | SECURITY | SETS |
    STATS | SYSTEM | TEXT | TIME | TRY_CAST | UESCAPE |
    UNNEST | VERBOSE | WORK | ZONE
)\b/xi;

# Data types
my $TYPES = qr/\b(?:
    BIGINT | BIGSERIAL | BIT | BOOL | BOOLEAN | BOX | BYTEA | CHAR | CHARACTER |
    CIDR | CIRCLE | CLOB | DATE | DATETIME | DATETIME2 | DATETIMEOFFSET | DEC |
    DECIMAL | DOUBLE | FIXED | FLOAT | HUGEINT | IMAGE | INET | INT |
    INTEGER | INTERVAL | JSONB | LINE | LSEG |
    MACADDR | MACADDR8 | MONEY | NCHAR | NTEXT | NUMERIC | NVARCHAR |
    OID | PATH | PG_LSN | PRECISION | REAL | REGCLASS |
    ROWID | SERIAL2 | SERIAL4 | SERIAL8 | SMALLDATETIME | SMALLINT |
    SMALLMONEY | SMALLSERIAL | SQL_VARIANT | STRUCT | TIMESTAMP |
    TIMESTAMPTZ | TIMETZ | TSQUERY | TSVECTOR | TXID_SNAPSHOT |
    UBIGINT | UHUGEINT | UNIQUEIDENTIFIER | UINTEGER | USMALLINT | UTINYINT |
    UUID | VARBINARY | VARCHAR | VARYING | XML | YEAR
)\b/xi;

# Functions (commonly used across dialects)
my $FUNCTIONS = qr/\b(?:
    ABS | ACOS | ASIN | ATAN | ATAN2 | AVG | CEIL | CEILING | CHAR_LENGTH |
    CHARACTER_LENGTH | CONCAT | CONCAT_WS | COS | COT | COUNT |
    CURDATE | CURTIME |
    DATE_ADD | DATE_FORMAT | DATE_PART | DATE_SUB | DATE_TRUNC |
    DATEDIFF | DATEPART | DAY | DAYNAME | DAYOFMONTH | DAYOFWEEK | DAYOFYEAR |
    DECODE | DEGREES | EXP | EXTRACT | FLOOR | GETDATE | GETUTCDATE |
    GREATEST | GROUP_CONCAT | HEX | HOUR | IFNULL | INITCAP | INSTR |
    JSON_ARRAY | JSON_ARRAYAGG | JSON_BUILD_ARRAY | JSON_BUILD_OBJECT |
    JSON_EXTRACT | JSON_OBJECT | JSON_OBJECTAGG | LAG | LAST_DAY | LCASE |
    LEAD | LEAST | LENGTH | LEN | LIST | LISTAGG | LN | LOCALTIME |
    LOCALTIMESTAMP | LOG | LOG10 | LOG2 | LOWER | LPAD | LTRIM | MAX | MD5 |
    MEDIAN | MIN | MINUTE | MONTH | MONTHNAME | NOW | NTH_VALUE | NTILE |
    NVL | NVL2 | OCTET_LENGTH | OVERLAY | PERCENTILE_CONT |
    PERCENTILE_DISC | PI | POSITION | POW | POWER | QUARTER | RADIANS | RAND |
    RANDOM | RANK | REGEXP_EXTRACT | REGEXP_LIKE | REGEXP_MATCHES |
    REGEXP_REPLACE | REGEXP_SPLIT_TO_ARRAY | REVERSE |
    ROUND | ROW_NUMBER | RPAD | RTRIM | SECOND | SHA1 | SHA2 | SHA256 |
    SIGN | SIN | SOUNDEX | SPACE | SPLIT_PART | SQRT | STDDEV | STDDEV_POP |
    STDDEV_SAMP | STRING_AGG | STRING_SPLIT | STRPOS | STUFF | SUBSTR |
    SUBSTRING | SUM | SYSDATE | SYSDATETIME | TAN | TIMESTAMPADD |
    TIMESTAMPDIFF | TO_CHAR | TO_DATE | TO_NUMBER | TO_TIMESTAMP | TRANSLATE |
    TRIM | TRUNC | TRUNCATE | TYPEOF | UCASE | UNHEX | UPPER |
    VAR_POP | VAR_SAMP | VARIANCE | WEEK | WEEKDAY | WEEKOFYEAR |
    WIDTH_BUCKET
)\b/xi;

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

        # Line comment (-- or #)
        if ($rest =~ /^(--.*|#.*)/) {
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

        # Strings (single or double quoted)
        if ($rest =~ /^("(?:[^"\\]|\\.|"")*"|'(?:[^'\\]|\\.|'')*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Dollar-quoted strings (PostgreSQL) $$...$$
        if ($rest =~ /^(\$\w*\$)/) {
            my $delim = $1;
            my $quoted_delim = quotemeta($delim);
            if ($rest =~ /^($quoted_delim.*?$quoted_delim)/s) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $pos + length($delim), TOKEN_STRING);
                $pos += length($delim);
            }
            next;
        }

        # Backtick quoted identifiers (MySQL)
        if ($rest =~ /^(`[^`]+`)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Bracket quoted identifiers (SQL Server)
        if ($rest =~ /^(\[[^\]]+\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Variables and parameters (@var, :var, $1, ?)
        if ($rest =~ /^([\@:]\w+|\$\d+|\?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Functions (must come before keywords to catch function calls)
        if ($rest =~ /^($FUNCTIONS)(?=\s*\()/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Data types
        if ($rest =~ /^($TYPES)/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(\d+\.?\d*(?:e[+-]?\d+)?)/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(!=|<>|>=|<=|::|->|->>|\|\||&&|[+\-*\/%&|^<>=!])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Generic function call
        if ($rest =~ /^(\w+)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
