package Zepto::Syntax::Diff;
# =============================================================================
# Diff/Patch Syntax Grammar
# =============================================================================
# Highlights unified diff format, git diff, and standard diff output

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $len = length($line);

    return ([], STATE_NORMAL) if $len == 0;

    # File headers: --- a/file and +++ b/file
    if ($line =~ /^(---|\+\+\+)\s/) {
        push @tokens, _token(0, $len, TOKEN_HEADING);
        return (\@tokens, STATE_NORMAL);
    }

    # diff command line
    if ($line =~ /^diff\s/) {
        push @tokens, _token(0, $len, TOKEN_KEYWORD);
        return (\@tokens, STATE_NORMAL);
    }

    # Index line
    if ($line =~ /^index\s/) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Hunk header: @@ -1,3 +1,4 @@
    if ($line =~ /^(\@\@[^@]+\@\@)(.*)$/) {
        push @tokens, _token(0, length($1), TOKEN_ATTRIBUTE);
        if (length($2) > 0) {
            push @tokens, _token(length($1), $len, TOKEN_COMMENT);
        }
        return (\@tokens, STATE_NORMAL);
    }

    # Added line
    if ($line =~ /^\+/) {
        push @tokens, _token(0, $len, TOKEN_STRING);
        return (\@tokens, STATE_NORMAL);
    }

    # Removed line
    if ($line =~ /^-/) {
        push @tokens, _token(0, $len, TOKEN_KEYWORD);
        return (\@tokens, STATE_NORMAL);
    }

    # Git metadata: new file mode, old mode, similarity index, rename, etc.
    if ($line =~ /^(new file mode|old mode|new mode|deleted file mode|similarity index|rename from|rename to|copy from|copy to|Binary files)\b/) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Context line (starts with space) - no highlighting
    return (\@tokens, STATE_NORMAL);
}

1;
