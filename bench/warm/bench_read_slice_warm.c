#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <math.h>

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
    const int n_slices = (int)mb_getenv_required_long("MEDIOBENCH_N_SLICES", 1, 100000000);
    const size_t slice_bytes = (size_t)mb_getenv_required_long("MEDIOBENCH_SLICE_BYTES", 1, (long)INT_MAX);
    const off_t data_offset = (off_t)mb_getenv_required_long("MEDIOBENCH_DATA_OFFSET", 0, (long)INT_MAX);

    warmup_page_cache(path);

    uint8_t *buf = malloc(slice_bytes);
    if (!buf) { perror("malloc"); return 1; }

    double *times = calloc((size_t)n_runs, sizeof(double));
    if (!times) { perror("calloc"); return 1; }

    for (int r = 0; r < n_runs; r++) {
        int fd = open(path, O_RDONLY);
        if (fd < 0) { perror("open"); return 1; }
        lseek(fd, data_offset, SEEK_SET);

        double t0 = now_seconds();

        uint64_t checksum = 0;
        for (int s = 0; s < n_slices; s++) {
            size_t total = 0;
            while (total < slice_bytes) {
                ssize_t n = read(fd, buf + total, slice_bytes - total);
                if (n <= 0) { perror("read"); return 1; }
                total += n;
            }
            checksum += buf[0];
        }

        double t1 = now_seconds();
        times[r] = t1 - t0;
        close(fd);
    }

    free(buf);

    double avg = 0;
    for (int i = 0; i < n_runs; i++) avg += times[i];
    avg /= n_runs;

    double std = 0;
    for (int i = 0; i < n_runs; i++) std += (times[i] - avg) * (times[i] - avg);
    std = sqrt(std / n_runs);

    free(times);

    double avg_gb = filesize_gb / avg;
    double std_gb = (filesize_gb / (avg * avg)) * std;
    double pct    = (avg_gb / mem_ceiling_gbs) * 100.0;

    printf("Condition:    C + read  |  warm cache  |  slice-by-slice\n");
    printf("Slices:       %d\n", n_slices);
    printf("Runs:         %d\n", n_runs);
    printf("Elapsed:      avg=%.3fs  std=%.3fs\n", avg, std);
    printf("Throughput:   avg=%.3f GB/s  std=%.3f GB/s\n", avg_gb, std_gb);
    printf("%% of ceiling: %.1f%% of STREAM Triad\n", pct);

    return 0;
}
