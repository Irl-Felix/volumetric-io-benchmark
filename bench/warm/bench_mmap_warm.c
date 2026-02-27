#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/mman.h>

#define WARMUP_BLOCK (4 * 1024 * 1024)

#include "bench_config.h"

double now_seconds() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void warmup_page_cache(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return;

    uint8_t *buf = malloc(WARMUP_BLOCK);
    if (!buf) { close(fd); return; }

    volatile uint64_t sink = 0;
    ssize_t n;
    while ((n = read(fd, buf, WARMUP_BLOCK)) > 0) {
        for (ssize_t p = 0; p < n; p += 4096)
            sink += buf[p];
    }

    free(buf);
    close(fd);
    (void)sink;
}

int main() {
    const char *path = mb_getenv_required_str("MEDIOBENCH_TIFF_PATH");
    const double filesize_gb = mb_getenv_required_double("MEDIOBENCH_FILESIZE_GB", 0.0, 1e9);
    const double mem_ceiling_gbs = mb_getenv_required_double("MEDIOBENCH_MEM_CEILING_GBS", 0.0, 1e6);
    const int n_runs = (int)mb_getenv_required_long("MEDIOBENCH_N_RUNS", 1, 1000);

    warmup_page_cache(path);

    int fd = open(path, O_RDONLY);
    if (fd < 0) { perror("open"); return 1; }

    struct stat st;
    fstat(fd, &st);
    size_t filesize = st.st_size;

    double *times = calloc((size_t)n_runs, sizeof(double));
    if (!times) { perror("calloc"); return 1; }

    for (int i = 0; i < n_runs; i++) {
        void *map = mmap(NULL, filesize, PROT_READ, MAP_SHARED, fd, 0);
        if (map == MAP_FAILED) { perror("mmap"); return 1; }

        double t0 = now_seconds();

        volatile uint8_t *ptr = (volatile uint8_t *)map;
        volatile uint64_t sink = 0;
        for (size_t j = 0; j < filesize; j += 4096)
            sink += ptr[j];

        double t1 = now_seconds();
        times[i] = t1 - t0;

        munmap(map, filesize);
    }

    close(fd);

    double avg = 0;
    for (int i = 0; i < n_runs; i++) avg += times[i];
    avg /= n_runs;

    double std = 0;
    for (int i = 0; i < n_runs; i++) std += (times[i] - avg) * (times[i] - avg);
    std = __builtin_sqrt(std / n_runs);

    free(times);

    double avg_gb = filesize_gb / avg;
    double std_gb = (filesize_gb / (avg * avg)) * std;
    double pct    = (avg_gb / mem_ceiling_gbs) * 100.0;

    printf("Condition:    C + mmap  |  warm cache\n");
    printf("Runs:         %d\n", n_runs);
    printf("Elapsed:      avg=%.3fs  std=%.3fs\n", avg, std);
    printf("Throughput:   avg=%.3f GB/s  std=%.3f GB/s\n", avg_gb, std_gb);
    printf("%% of ceiling: %.1f%% of STREAM Triad\n", pct);

    return 0;
}
