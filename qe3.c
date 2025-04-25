#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <pthread.h>

#define PAYLOAD_SIZE 8192  // Size of each UDP packet payload
#define NUM_THREADS 8      // Number of threads to use for sending data

struct ThreadArgs {
    int sockfd;
    struct sockaddr_in server_addr;
};

void *send_udp_packets(void *arg) {
    struct ThreadArgs *args = (struct ThreadArgs *)arg;
    int sockfd = args->sockfd;
    struct sockaddr_in server_addr = args->server_addr;
    char payload[PAYLOAD_SIZE];
    socklen_t addr_len = sizeof(server_addr);

    // Initialize payload with some data
    memset(payload, 'A', PAYLOAD_SIZE);

    while (1) {
        if (sendto(sockfd, payload, PAYLOAD_SIZE, 0, (struct sockaddr *)&server_addr, addr_len) < 0) {
            perror("Failed to send data");
            close(sockfd);
            exit(EXIT_FAILURE);
        }
    }

    pthread_exit(NULL);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <hostname> <port>\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    struct hostent *host;
    struct sockaddr_in server_addr;
    int sockfd;
    pthread_t threads[NUM_THREADS];
    struct ThreadArgs args[NUM_THREADS];

    if ((host = gethostbyname(argv[1])) == NULL) {
        fprintf(stderr, "Failed to resolve hostname: %s\n", argv[1]);
        exit(EXIT_FAILURE);
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(atoi(argv[2]));
    memcpy(&server_addr.sin_addr, host->h_addr, host->h_length);

    if ((sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
        perror("Failed to create socket");
        exit(EXIT_FAILURE);
    }

    for (int i = 0; i < NUM_THREADS; i++) {
        args[i].sockfd = sockfd;
        args[i].server_addr = server_addr;
        pthread_create(&threads[i], NULL, send_udp_packets, (void *)&args[i]);
    }

    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    close(sockfd);
    return 0;
}
