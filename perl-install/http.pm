package http; # $Id$

use IO::Socket;
use network::network;


my $sock;

sub getFile {
    local ($^W) = 0;

    my ($url) = @_;
    $sock->close if $sock;
    $url =~ m|/XXX$| and return; #- force closing connection.

    # can be used for ftp urls (with http proxy)
    my ($host, $port, $path) = $url =~ m,^(?:http|ftp)://([^/:]+)(?::(\d+))?(/\S*)?$,;
    $host = resolv($host);

    my $use_http_proxy = $ENV{PROXY} && $ENV{PROXYPORT};

    $sock = IO::Socket::INET->new(PeerAddr => $use_http_proxy ? $ENV{PROXY} : $host,
				  PeerPort => $use_http_proxy ? $ENV{PROXYPORT} : $port || 80,
				  Proto    => 'tcp',
				  Timeout  => 60) or die "can't connect $@";
    $sock->autoflush;
    print $sock join("\015\012" =>
		     "GET " . ($use_http_proxy ? $url : $path) . " HTTP/1.0",
		     "Host: $host" . ($port && ":$port"),
		     "User-Agent: DrakX/vivelinuxabaszindozs",
		     "", "");

    #- skip until empty line
    my ($now, $last, $buf, $tmp) = 0;
    my $read = sub { sysread($sock, $buf, 1) or die ''; $tmp .= $buf };
    do {
	$last = $now;
	&$read; &$read if $buf =~ /\015/;
	$now = $buf =~ /\012/;
    } until $now && $last;

    $tmp =~ /^.*\b200\b/ ? $sock : undef;
}

1;
