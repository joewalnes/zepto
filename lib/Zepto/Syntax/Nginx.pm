package Zepto::Syntax::Nginx;
# =============================================================================
# Nginx Configuration Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub line_comment_prefix { '#' }

my $BLOCKS = qr/\b(?:
    http | server | location | upstream | events | stream | mail |
    map | geo | split_clients | types | if | limit_except
)\b/x;

my $DIRECTIVES = qr/\b(?:
    listen | server_name | root | index | try_files |
    error_page | return | rewrite | proxy_pass | proxy_set_header |
    proxy_redirect | proxy_buffering | proxy_buffer_size | proxy_buffers |
    proxy_connect_timeout | proxy_read_timeout | proxy_send_timeout |
    proxy_cache | proxy_cache_valid | proxy_cache_path |
    fastcgi_pass | fastcgi_param | fastcgi_index |
    uwsgi_pass | uwsgi_param | scgi_pass |
    ssl | ssl_certificate | ssl_certificate_key | ssl_protocols |
    ssl_ciphers | ssl_session_cache | ssl_session_timeout |
    ssl_prefer_server_ciphers | ssl_stapling | ssl_stapling_verify |
    access_log | error_log | log_format | log_not_found |
    gzip | gzip_types | gzip_min_length | gzip_comp_level | gzip_vary |
    client_max_body_size | client_body_buffer_size | client_body_timeout |
    send_timeout | keepalive_timeout | keepalive_requests |
    sendfile | tcp_nopush | tcp_nodelay |
    worker_processes | worker_connections | multi_accept |
    include | load_module | pid | user | daemon |
    add_header | expires | etag | charset |
    resolver | resolver_timeout |
    allow | deny | auth_basic | auth_basic_user_file |
    autoindex | autoindex_exact_size | autoindex_localtime |
    set | break | default_type | types_hash_max_size |
    server_tokens | limit_req | limit_req_zone | limit_conn | limit_conn_zone |
    proxy_http_version | proxy_cache_bypass | proxy_no_cache |
    stub_status | health_check | zone | state |
    weight | max_fails | fail_timeout | backup | down
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Comment
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Quoted strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Variables $var or ${var}
        if ($rest =~ /^(\$\{?\w+\}?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Regex locations: ~ or ~*
        if ($rest =~ /^(~\*?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Block directives
        if ($rest =~ /^($BLOCKS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Configuration directives
        if ($rest =~ /^($DIRECTIVES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers with units (size, time)
        if ($rest =~ /^(\d+)(k|m|g|s|ms|h|d)\b/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            push @tokens, _token($pos, $pos + length($2), TOKEN_KEYWORD);
            $pos += length($2);
            next;
        }

        # Numbers and IP addresses
        if ($rest =~ /^(\d+\.\d+\.\d+\.\d+(?:\/\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\d+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # HTTP status codes and methods
        if ($rest =~ /^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # on/off keywords
        if ($rest =~ /^(on|off|yes|no|true|false)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Braces and semicolons
        if ($rest =~ /^([{};])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Operators
        if ($rest =~ /^(=|!=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
