package Zepto::Syntax::SSHConfig;
# =============================================================================
# SSH Config Syntax Grammar
# =============================================================================
# Handles ~/.ssh/config, /etc/ssh/ssh_config, /etc/ssh/sshd_config

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub line_comment_prefix { '#' }

my $KEYWORDS = qr/\b(?:
    Host | Match | HostName | User | Port | IdentityFile | IdentitiesOnly |
    ProxyCommand | ProxyJump | ForwardAgent | ForwardX11 | ForwardX11Trusted |
    LocalForward | RemoteForward | DynamicForward |
    ServerAliveInterval | ServerAliveCountMax | ConnectTimeout |
    StrictHostKeyChecking | UserKnownHostsFile | GlobalKnownHostsFile |
    AddKeysToAgent | UseKeychain | BatchMode |
    Compression | Protocol | Ciphers | MACs | KexAlgorithms |
    HostKeyAlgorithms | PubkeyAcceptedAlgorithms | PubkeyAuthentication |
    PasswordAuthentication | ChallengeResponseAuthentication |
    PreferredAuthentications | LogLevel |
    ControlMaster | ControlPath | ControlPersist |
    TCPKeepAlive | PermitLocalCommand | LocalCommand |
    SetEnv | SendEnv | AcceptEnv | RequestTTY | RemoteCommand |
    EscapeChar | ExitOnForwardFailure | HashKnownHosts |
    VisualHostKey | NumberOfPasswordPrompts | RekeyLimit |
    Tunnel | TunnelDevice | PermitRemoteOpen | StreamLocalBindUnlink |
    AddressFamily | BindAddress | BindInterface | CanonicalDomains |
    CanonicalizeHostname | CanonicalizeMaxDots | CanonicalizeFallbackLocal |
    CanonicalizePermittedCNAMEs | CASignatureAlgorithms | CertificateFile |
    CheckHostIP | ConnectionAttempts | EnableSSHKeysign |
    FingerprintHash | GatewayPorts | GSSAPIAuthentication |
    GSSAPIDelegateCredentials | GSSAPIKeyExchange | GSSAPIRenewalForcesRekey |
    GSSAPIServerIdentity | GSSAPITrustDns | HostbasedAuthentication |
    HostbasedAcceptedAlgorithms | HostKeyAlias | Hostname | IPQoS |
    KbdInteractiveAuthentication | KbdInteractiveDevices |
    NoHostAuthenticationForLocalhost | PKCS11Provider | SecurityKeyProvider |
    ProxyUseFdpass | RevokedHostKeys | ServerAliveInterval |
    SmartcardDevice | UpdateHostKeys | VerifyHostKeyDNS | XAuthLocation |
    Include | Tag | IgnoreUnknown |
    ListenAddress | PermitRootLogin | MaxAuthTries | MaxSessions |
    AuthorizedKeysFile | AuthorizedPrincipalsFile | AllowUsers | AllowGroups |
    DenyUsers | DenyGroups | Subsystem | X11Forwarding | X11DisplayOffset |
    PrintMotd | PrintLastLog | Banner | UseDNS | LoginGraceTime |
    MaxStartups | PermitTunnel | PermitTTY | PermitUserEnvironment |
    ClientAliveInterval | ClientAliveCountMax | PidFile | UsePAM
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    return ([], STATE_NORMAL) if $len == 0;

    # Comment
    if ($line =~ /^(\s*#.*)/) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Host/Match directive (special: highlight the pattern)
    if ($line =~ /^(\s*)(Host|Match)(\s+)(.+)$/i) {
        my $indent = length($1);
        my $kw = $2;
        my $space = $3;
        my $pattern_start = $indent + length($kw) + length($space);

        push @tokens, _token($indent, $indent + length($kw), TOKEN_KEYWORD);
        push @tokens, _token($pattern_start, $len, TOKEN_STRING);
        return (\@tokens, STATE_NORMAL);
    }

    # Key value pair
    if ($line =~ /^(\s*)([\w]+)(\s+|=)(.*)$/) {
        my $indent = length($1);
        my $key = $2;
        my $sep = $3;
        my $value_start = $indent + length($key) + length($sep);
        my $value = $4;

        # Key
        push @tokens, _token($indent, $indent + length($key), TOKEN_VARIABLE);

        # Separator (= if present)
        if ($sep =~ /=/) {
            push @tokens, _token($indent + length($key), $indent + length($key) + 1, TOKEN_OPERATOR);
        }

        # Value
        if (length($value) > 0) {
            # Boolean values
            if ($value =~ /^\s*(yes|no|true|false|ask|confirm|accept-new|off|auto|autoask)\s*$/i) {
                push @tokens, _token($value_start, $value_start + length($value), TOKEN_CONSTANT);
            }
            # Numeric values
            elsif ($value =~ /^\s*(\d+)\s*$/) {
                push @tokens, _token($value_start, $value_start + length($value), TOKEN_NUMBER);
            }
            # Paths
            elsif ($value =~ /^\s*(~?\/\S+)/) {
                push @tokens, _token($value_start, $len, TOKEN_STRING);
            }
            # Everything else
            else {
                push @tokens, _token($value_start, $len, TOKEN_STRING);
            }
        }
    }

    return (\@tokens, STATE_NORMAL);
}

1;
