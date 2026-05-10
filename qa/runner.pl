#!/usr/bin/env perl
# ===========================================================================
# runner.pl — Zepto QA test runner
# ===========================================================================
# Discovers and runs QA test scripts in parallel, with live progress display.
#
# Usage:
#   qa/runner.pl                    # run tier 1 only (default)
#   qa/runner.pl --tier 1,2         # run tiers 1 and 2
#   qa/runner.pl --filter edit      # run only scripts matching "edit"
#   qa/runner.pl --list             # list all scripts without running
#   qa/runner.pl --report FILE      # write results to file
#   qa/runner.pl --serial           # disable parallel execution
#   qa/runner.pl --jobs N           # max parallel jobs (default: 4)
#   qa/runner.pl script.sh          # run a single script
# ===========================================================================

use strict;
use warnings;
use File::Basename qw(basename dirname);
use File::Temp     qw(tempdir);
use Getopt::Long   qw(:config no_ignore_case bundling);
use POSIX          qw(strftime);
use Time::HiRes    qw(time sleep);

# ---------------------------------------------------------------------------
# ANSI helpers
# ---------------------------------------------------------------------------

my $IS_TTY = -t STDOUT;

sub c { $IS_TTY ? "\033[$_[0]m" : '' }

my $RED    = c('31');
my $GREEN  = c('32');
my $YELLOW = c('33');
my $BOLD   = c('1');
my $DIM    = c('2');
my $RESET  = c('0');
my $CLR    = $IS_TTY ? "\r\033[K" : '';

my $SYM_PASS    = "${GREEN}\x{2713}${RESET}";
my $SYM_FAIL    = "${RED}\x{2717}${RESET}";
my $SYM_SKIP    = "${YELLOW}\x{2298}${RESET}";
my $SYM_ERROR   = "${RED}!${RESET}";
my $SYM_RUNNING = "${DIM}\x{22EF}${RESET}";

# ---------------------------------------------------------------------------
# CLI arguments
# ---------------------------------------------------------------------------

my $tiers      = '1';
my $filter     = '';
my $list_only  = 0;
my $report     = '';
my $serial     = 0;
my $max_jobs   = 4;
my $help       = 0;
my $single     = '';

GetOptions(
    'tier=s'   => \$tiers,
    'filter=s' => \$filter,
    'list'     => \$list_only,
    'report=s' => \$report,
    'serial'   => \$serial,
    'jobs=i'   => \$max_jobs,
    'help|h'   => \$help,
) or die "Bad options\n";

if ($help) {
    print "Usage: runner.pl [--tier 1,2,3] [--filter PAT] [--list] [--report FILE] [--serial] [--jobs N] [SCRIPT]\n";
    exit 0;
}

$single = shift @ARGV if @ARGV;
$serial = 1 if $single;

# ---------------------------------------------------------------------------
# Discover scripts
# ---------------------------------------------------------------------------

my $qa_dir = dirname(__FILE__);

sub discover_scripts {
    my @scripts;

    if ($single) {
        my $path = -f $single          ? $single
                 : -f "$qa_dir/$single" ? "$qa_dir/$single"
                 : die "${RED}Script not found: $single${RESET}\n";
        return ($path);
    }

    for my $tier (split /,/, $tiers) {
        my $dir = "$qa_dir/scripts/tier${tier}";
        next unless -d $dir;
        opendir my $dh, $dir or next;
        push @scripts, map  { "$dir/$_" }
                       sort
                       grep { /\.sh$/ && -f "$dir/$_" } readdir $dh;
        closedir $dh;
    }

    if ($filter ne '') {
        @scripts = grep { basename($_) =~ /\Q$filter\E/ } @scripts;
    }

    return @scripts;
}

my @scripts = discover_scripts();
my $total   = scalar @scripts;

if ($total == 0) {
    print "${YELLOW}No test scripts found for tier(s) $tiers";
    print " matching '$filter'" if $filter;
    print ".${RESET}\n";
    exit 0;
}

# ---------------------------------------------------------------------------
# --list mode
# ---------------------------------------------------------------------------

if ($list_only) {
    print "${BOLD}QA scripts (tier $tiers):${RESET}\n";
    printf "  %s\n", basename($_, '.sh') for @scripts;
    print "${DIM}$total scripts${RESET}\n";
    exit 0;
}

# ---------------------------------------------------------------------------
# Compute column widths
# ---------------------------------------------------------------------------

my $name_width = 0;
for my $s (@scripts) {
    my $len = length(basename($s, '.sh'));
    $name_width = $len if $len > $name_width;
}
$name_width += 2;

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

binmode STDOUT, ':utf8';
$| = 1;

my $dot = "  ${DIM}\x{00B7}${RESET}  ";
print "\n";
print "${BOLD}Zepto QA${RESET}";
print "${dot}Tier $tiers";
print $serial ? "${dot}Serial" : "${dot}$max_jobs parallel";
print "${dot}$total scripts\n";
print "${DIM}" . strftime('%Y-%m-%d %H:%M:%S', localtime) . "${RESET}\n";
print "\n";

my $run_start = time();

# ---------------------------------------------------------------------------
# Report file
# ---------------------------------------------------------------------------

my $REPORT_FH;
if ($report) {
    open $REPORT_FH, '>:utf8', $report or die "Can't open report: $!\n";
}

sub report_line {
    return unless $REPORT_FH;
    (my $plain = $_[0]) =~ s/\033\[[0-9;]*m//g;
    print $REPORT_FH $plain;
}

# ---------------------------------------------------------------------------
# Parse test output
# ---------------------------------------------------------------------------

sub strip_ansi { (my $t = $_[0]) =~ s/\033\[[0-9;]*m//g; $t }

sub parse_output {
    my ($output) = @_;
    my $plain = strip_ansi($output);
    my $pass = () = $plain =~ /^  PASS /gm;
    my $fail = () = $plain =~ /^  FAIL /gm;
    my $skip = () = $plain =~ /^  SKIP /gm;
    return ($pass, $fail, $skip);
}

# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------

my $done_count = 0;
my %running;
my $status_shown = 0;

sub clear_status {
    return unless $IS_TTY && $status_shown;
    print $CLR;
    $status_shown = 0;
}

sub show_status {
    return unless $IS_TTY && %running;
    my @names = sort values %running;
    my $n     = scalar @names;
    my $remaining = $total - $done_count - $n;
    my $line = " ${SYM_RUNNING}  ";
    $line .= $n <= 3
        ? join(', ', @names)
        : join(', ', @names[0..2]) . " +@{[$n - 3]} more";
    $line .= "  ${DIM}($remaining queued)${RESET}" if $remaining > 0;
    print "${CLR}${line}";
    $status_shown = 1;
}

sub fmt_dur {
    $_[0] < 10 ? sprintf('%.1fs', $_[0]) : sprintf('%ds', int($_[0]));
}

sub print_result {
    my ($name, $status, $duration) = @_;
    $done_count++;
    clear_status();

    my %sym = (pass => $SYM_PASS, fail => $SYM_FAIL,
               skip => $SYM_SKIP, error => $SYM_ERROR);
    my $counter = sprintf('%*d/%d', length($total), $done_count, $total);
    my $line = sprintf(" %s  %-*s  %5s  ${DIM}[%s]${RESET}\n",
        $sym{$status} // '?', $name_width, $name, fmt_dur($duration), $counter);

    print $line;
    report_line($line);
    show_status();
}

# ---------------------------------------------------------------------------
# Quiet hangon helper (suppress stderr noise)
# ---------------------------------------------------------------------------

sub hangon_quiet { system("hangon @_ >/dev/null 2>&1"); }

# ---------------------------------------------------------------------------
# Ensure clean hangon state
# ---------------------------------------------------------------------------

# Reset hangon state — stop all sessions and clean state file
hangon_quiet('stopall');
my $hangon_state = "$ENV{HOME}/.hangon/state.json";
unlink $hangon_state if -e $hangon_state;
sleep 0.5;

# ---------------------------------------------------------------------------
# Run scripts
# ---------------------------------------------------------------------------

my $tmpdir = tempdir('/tmp/zepto_qa_XXXXXX', CLEANUP => 1);

my $total_pass = 0;
my $total_fail = 0;
my $total_skip = 0;
my $total_err  = 0;
my @failures;

sub finish_script {
    my ($name, $out_file, $rc, $duration) = @_;

    my $output = '';
    if (open my $fh, '<', $out_file) {
        local $/; $output = <$fh>; close $fh;
    }

    my ($pass, $fail, $skip) = parse_output($output);
    $total_pass += $pass;
    $total_fail += $fail;
    $total_skip += $skip;

    my $status;
    if ($rc != 0 && $fail == 0) {
        $total_err++;
        $status = 'error';
        push @failures, { name => $name, duration => $duration, output => $output,
                          error => "Script exited with code $rc" };
    } elsif ($fail > 0) {
        $status = 'fail';
        push @failures, { name => $name, duration => $duration, output => $output };
    } elsif ($skip > 0 && $pass == 0) {
        $status = 'skip';
    } else {
        $status = 'pass';
    }

    print_result($name, $status, $duration);
}

if ($serial) {
    for my $i (0 .. $#scripts) {
        my $script = $scripts[$i];
        my $name   = basename($script, '.sh');
        my $out    = "$tmpdir/${i}_${name}.out";

        $running{0} = $name;
        show_status();

        my $t0 = time();
        system("bash \Q$script\E >\Q$out\E 2>&1");
        my $rc = $? >> 8;

        delete $running{0};
        finish_script($name, $out, $rc, time() - $t0);
    }
} else {
    my %children;
    my $next_idx = 0;

    my $launch_next = sub {
        while (keys %children < $max_jobs && $next_idx <= $#scripts) {
            my $i      = $next_idx++;
            my $script = $scripts[$i];
            my $name   = basename($script, '.sh');
            my $out    = "$tmpdir/${i}_${name}.out";

            my $pid = fork();
            die "fork: $!\n" unless defined $pid;

            if ($pid == 0) {
                open STDOUT, '>', $out or exit 127;
                open STDERR, '>&', \*STDOUT;
                exec('bash', $script);
                exit 127;
            }

            $children{$pid} = {
                name  => $name,
                out   => $out,
                start => time(),
            };
            $running{$pid} = $name;

            # Stagger launches to reduce hangon state.json contention
            # Scale stagger with total count to avoid tmux exhaustion
            my $stagger = $total > 400 ? 0.25 : $total > 200 ? 0.2 : 0.15;
            sleep $stagger if $next_idx <= $#scripts;
        }
    };

    $launch_next->();
    show_status();

    while (keys %children) {
        my $pid = waitpid(-1, 0);
        next if $pid <= 0;

        my $rc   = $? >> 8;
        my $info = delete $children{$pid};
        next unless $info;

        delete $running{$pid};
        finish_script($info->{name}, $info->{out}, $rc, time() - $info->{start});
        $launch_next->();
    }
}

hangon_quiet('stopall');
clear_status();

# ---------------------------------------------------------------------------
# Failure details
# ---------------------------------------------------------------------------

if (@failures) {
    print "\n";
    printf " ${RED}${BOLD}FAILURES (%d)${RESET}\n", scalar @failures;

    for my $f (@failures) {
        print "\n";
        printf " ${SYM_FAIL}  %s  ${DIM}(%s)${RESET}\n", $f->{name}, fmt_dur($f->{duration});

        # Extract and display FAIL/ERROR lines with their detail context
        my $plain = strip_ansi($f->{output} // '');
        my @lines = split /\n/, $plain;
        my $printed_any = 0;
        my $in_fail = 0;
        my $detail_count = 0;

        for my $l (@lines) {
            if ($l =~ /^\s+(FAIL|ERROR) /) {
                $in_fail = 1;
                $detail_count = 0;
                $printed_any = 1;
                printf "    ${RED}%s${RESET}\n", $l;
            } elsif ($in_fail && $l =~ /^\s{7}/ && $detail_count < 8) {
                printf "    ${DIM}%s${RESET}\n", $l;
                $detail_count++;
            } elsif ($in_fail && $l !~ /^\s{7}/) {
                $in_fail = 0;
            }
        }

        # For errors with no FAIL lines, show the script output
        if (!$printed_any && $f->{error}) {
            printf "    ${RED}%s${RESET}\n", $f->{error};
            my $shown = 0;
            for my $l (@lines) {
                next if $l =~ /^\s*$/;
                printf "    ${DIM}  %s${RESET}\n", $l;
                last if ++$shown >= 6;
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

my $elapsed          = time() - $run_start;
my $total_assertions = $total_pass + $total_fail + $total_skip;

print "\n";
print "${DIM}" . ("\x{2500}" x 50) . "${RESET}\n";
print "\n";
printf " ${BOLD}%d${RESET} scripts${dot}${BOLD}%d${RESET} assertions${dot}${BOLD}%s${RESET}\n",
    $total, $total_assertions, fmt_dur($elapsed);
print "\n";

my $cw = length($total_assertions) + 1;
printf " ${SYM_PASS}  %*d passed\n", $cw, $total_pass;
if ($total_fail) {
    printf " ${SYM_FAIL}  %*d failed\n", $cw, $total_fail;
} else {
    printf " ${SYM_FAIL}  ${DIM}%*d failed${RESET}\n", $cw, 0;
}
printf " ${SYM_SKIP}  %*d skipped\n", $cw, $total_skip if $total_skip;
printf " ${SYM_ERROR} %*d errors\n",  $cw, $total_err  if $total_err;
print "\n";

print " ${DIM}Report: $report${RESET}\n" if $report;
close $REPORT_FH if $REPORT_FH;

if ($total_fail == 0 && $total_err == 0) {
    print " ${GREEN}${BOLD}ALL PASSED${RESET}\n\n";
    exit 0;
} else {
    print " ${RED}${BOLD}FAILURES DETECTED${RESET}\n\n";
    exit 1;
}
