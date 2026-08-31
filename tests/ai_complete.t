#!/usr/bin/env perl
# Tests for Zepto::AIComplete
#
# bugs.md "AI API key passed as a curl command-line argument, visible to
# other local users via ps" (QA-REG-209): AIComplete.pm's
# _child_http_request() used to build the Authorization header directly
# into curl's argv (`-H "Authorization: Bearer $api_key"`), which is
# visible to any local user for the whole lifetime of the curl process via
# `ps`/`/proc/<pid>/cmdline`. The fix writes the header into a short-lived,
# mode-0600 temp file and passes it to curl via `-K`/`--config`, keeping
# the key out of argv.
#
# These tests exercise the REAL fork()+exec() code path in
# _child_http_request() -- including real temp-file creation and cleanup
# -- but substitute a fake `curl` on PATH that records its own argv and
# the referenced config file's mode/content instead of touching the
# network. This lets us assert directly on what the child process would
# actually expose via `ps`, without a live HTTP server.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Spec;
use POSIX ();
use lib 'lib';
use Zepto::AIComplete;

# Build a fake `curl` and put its directory first on PATH, so
# AIComplete's exec('curl', ...) finds it instead of the real binary.
my $bindir = tempdir(CLEANUP => 1);
my $fake_curl = File::Spec->catfile($bindir, 'curl');
{
    open(my $fh, '>', $fake_curl) or die "Cannot write fake curl: $!";
    print $fh <<'FAKE_CURL';
#!/usr/bin/env perl
# Fake `curl` for ai_complete.t -- records its invocation instead of
# hitting the network.
use strict;
use warnings;

my $argv_log = $ENV{FAKE_CURL_ARGV_LOG};
if ($argv_log) {
    open(my $fh, '>', $argv_log) or die "fake curl: cannot write argv log: $!";
    print $fh "$_\n" for @ARGV;
    close $fh;
}

# Find "-K <path>" and dump that file's mode + content, so the test can
# verify the header made it into the config file (not argv) and that the
# file was mode 0600 at the moment curl read it.
for my $i (0 .. $#ARGV) {
    if ($ARGV[$i] eq '-K' && defined $ARGV[$i + 1]) {
        my $cfg = $ARGV[$i + 1];
        my @st = stat($cfg);
        my $mode = @st ? sprintf('%04o', $st[2] & 07777) : 'MISSING';
        my $content = '';
        if (open(my $cf, '<', $cfg)) {
            local $/;
            $content = <$cf>;
            close $cf;
        }
        my $cfg_log = $ENV{FAKE_CURL_CFG_LOG};
        if ($cfg_log) {
            open(my $of, '>', $cfg_log) or die "fake curl: cannot write cfg log: $!";
            print $of "MODE=$mode\n";
            print $of "CONTENT=$content";
            close $of;
        }
    }
}

# Optional artificial delay so a caller can inspect `ps` while this fake
# curl process is still alive (used by the ps-visibility subtest below).
if ($ENV{FAKE_CURL_SLEEP}) {
    sleep($ENV{FAKE_CURL_SLEEP});
}
exit 0;
FAKE_CURL
    close $fh;
}
chmod 0755, $fake_curl or die "Cannot chmod fake curl: $!";

local $ENV{PATH} = "$bindir:$ENV{PATH}";

# ============================================================================
# Helper: run _child_http_request() with a given API key and return
# { argv => [...], cfg_mode => '0NNN', cfg_content => '...', out => '...' }
# ============================================================================
sub run_child_http_request {
    my (%opts) = @_;
    my $api_key = $opts{api_key} // 'sk-TEST-SECRET-VALUE-DO-NOT-LEAK';

    my $ai = Zepto::AIComplete->new(
        api_url => 'https://fake-ai-endpoint.invalid/v1',
        api_key => $api_key,
        model   => 'test-model',
    );

    my $tmpdir = tempdir(CLEANUP => 1);
    my $argv_log = File::Spec->catfile($tmpdir, 'argv.log');
    my $cfg_log  = File::Spec->catfile($tmpdir, 'cfg.log');
    my $out_path = File::Spec->catfile($tmpdir, 'curl-stdout.log');

    local $ENV{FAKE_CURL_ARGV_LOG} = $argv_log;
    local $ENV{FAKE_CURL_CFG_LOG}  = $cfg_log;
    local $ENV{FAKE_CURL_SLEEP}    = $opts{sleep} // 0;

    open(my $write_fh, '>', $out_path) or die "Cannot open $out_path: $!";
    $ai->_child_http_request($write_fh, '{"model":"test"}');
    close $write_fh;

    my @argv;
    if (open(my $fh, '<', $argv_log)) {
        @argv = <$fh>;
        chomp @argv;
        close $fh;
    }

    my ($cfg_mode, $cfg_content) = ('', '');
    if (open(my $fh, '<', $cfg_log)) {
        local $/;
        my $all = <$fh>;
        close $fh;
        if (defined $all && $all =~ /^MODE=(\S*)\n(.*)/s) {
            $cfg_mode = $1;
            my $rest = $2;
            $cfg_content = $rest =~ /^CONTENT=(.*)/s ? $1 : '';
        }
    }

    # Find the -K path from argv so the caller can check it was cleaned up.
    my $cfg_path;
    for my $i (0 .. $#argv) {
        if ($argv[$i] eq '-K' && defined $argv[$i + 1]) {
            $cfg_path = $argv[$i + 1];
            last;
        }
    }

    return {
        argv        => \@argv,
        cfg_mode    => $cfg_mode,
        cfg_content => $cfg_content,
        cfg_path    => $cfg_path,
    };
}

# ============================================================================
# Core fix: API key never appears in curl's argv
# ============================================================================
subtest 'API key is not present in curl argv (ps-visible)' => sub {
    my $api_key = 'sk-TEST-SECRET-VALUE-DO-NOT-LEAK';
    my $result = run_child_http_request(api_key => $api_key);

    ok(@{ $result->{argv} } > 0, 'Fake curl was actually invoked (argv captured)');

    my $argv_str = join(' ', @{ $result->{argv} });
    unlike($argv_str, qr/\Q$api_key\E/, 'Raw API key does not appear anywhere in curl argv');
    unlike($argv_str, qr/Authorization/, '"Authorization" header text does not appear in curl argv');
    unlike($argv_str, qr/Bearer/, '"Bearer" does not appear in curl argv');

    ok((grep { $_ eq '-K' } @{ $result->{argv} }), 'curl is invoked with -K (config file)');
};

# ============================================================================
# The key DOES reach curl -- via the -K config file, not argv
# ============================================================================
subtest 'API key is delivered correctly via the -K config file' => sub {
    my $api_key = 'sk-TEST-SECRET-VALUE-DO-NOT-LEAK';
    my $result = run_child_http_request(api_key => $api_key);

    is($result->{cfg_content}, qq(header = "Authorization: Bearer $api_key"\n),
        'Config file contains the exact curl "header = ..." directive with the real key');
};

# ============================================================================
# Config file permissions: must be 0600, never world/group readable
# ============================================================================
subtest 'Config file is created with mode 0600' => sub {
    my $result = run_child_http_request();
    is($result->{cfg_mode}, '0600', 'Config file mode is 0600 (owner read/write only) when curl reads it');
};

# ============================================================================
# Cleanup: the config file must not survive after the request completes
# ============================================================================
subtest 'Config file is deleted after the request completes' => sub {
    my $result = run_child_http_request();
    ok(defined $result->{cfg_path}, 'Config path was captured from argv');
    ok(!-e $result->{cfg_path}, 'Config file no longer exists on disk after _child_http_request returns');
};

# ============================================================================
# Cleanup on cancellation: SIGTERM (what _kill_child sends on every
# keystroke while a request is in flight) must still clean up the file,
# not just the plain-success path.
# ============================================================================
subtest 'Config file is deleted even if the request is cancelled via SIGTERM' => sub {
    my $api_key = 'sk-TEST-SECRET-VALUE-DO-NOT-LEAK';
    my $ai = Zepto::AIComplete->new(
        api_url => 'https://fake-ai-endpoint.invalid/v1',
        api_key => $api_key,
        model   => 'test-model',
    );

    my $tmpdir = tempdir(CLEANUP => 1);
    my $argv_log = File::Spec->catfile($tmpdir, 'argv.log');
    my $out_path = File::Spec->catfile($tmpdir, 'curl-stdout.log');

    local $ENV{FAKE_CURL_ARGV_LOG} = $argv_log;
    local $ENV{FAKE_CURL_CFG_LOG}  = '';
    local $ENV{FAKE_CURL_SLEEP}    = 3;   # keep fake curl alive so we can kill the wrapper

    open(my $write_fh, '>', $out_path) or die "Cannot open $out_path: $!";

    my $pid = fork();
    die "fork failed" unless defined $pid;

    if ($pid == 0) {
        # Grandchild-of-test: runs _child_http_request(), which itself
        # forks fake curl and blocks in waitpid() -- exactly like the real
        # editor's forked AI-request child.
        $ai->_child_http_request($write_fh, '{"model":"test"}');
        POSIX::_exit(0);
    }

    # Give the wrapper time to create the config file and fork fake curl.
    select(undef, undef, undef, 0.5);

    # Find the config path via the fake curl's argv log (written before it
    # sleeps).
    my $cfg_path;
    for (1 .. 20) {
        if (-s $argv_log) {
            open(my $fh, '<', $argv_log) or last;
            my @argv = <$fh>;
            chomp @argv;
            close $fh;
            for my $i (0 .. $#argv) {
                if ($argv[$i] eq '-K' && defined $argv[$i + 1]) {
                    $cfg_path = $argv[$i + 1];
                    last;
                }
            }
        }
        last if $cfg_path;
        select(undef, undef, undef, 0.1);
    }
    ok(defined $cfg_path, 'Observed the config path before sending SIGTERM')
        or diag("argv log never appeared: $argv_log");
    ok(defined $cfg_path && -e $cfg_path, 'Config file exists while the (fake) curl request is in flight')
        if defined $cfg_path;

    # This mirrors AIComplete::_kill_child(), which sends TERM to the
    # forked request child on every debounce-cancelling keystroke.
    kill('TERM', $pid);
    waitpid($pid, 0);

    ok(defined $cfg_path && !-e $cfg_path,
        'Config file was removed even though the request was cancelled mid-flight')
        if defined $cfg_path;

    close $write_fh;
};

done_testing();
