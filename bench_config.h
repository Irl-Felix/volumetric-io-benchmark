#ifndef MEDIOBENCH_CONFIG_H
#define MEDIOBENCH_CONFIG_H

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static inline const char *mb_getenv_str(const char *name, const char *default_value) {
    const char *v = getenv(name);
    return (v && *v) ? v : default_value;
}

static inline const char *mb_getenv_required_str(const char *name) {
    const char *v = getenv(name);
    if (v && *v) return v;
    fprintf(stderr, "Missing required environment variable %s\n", name);
    exit(2);
}

static inline long mb_getenv_long(const char *name, long default_value, long min_value, long max_value) {
    const char *s = getenv(name);
    if (!s || !*s) return default_value;

    errno = 0;
    char *end = NULL;
    long v = strtol(s, &end, 10);
    if (errno != 0 || end == s || (end && *end != '\0')) {
        fprintf(stderr, "Invalid %s='%s' (expected integer)\n", name, s);
        exit(2);
    }
    if (v < min_value || v > max_value) {
        fprintf(stderr, "Out of range %s=%ld (expected %ld..%ld)\n", name, v, min_value, max_value);
        exit(2);
    }
    return v;
}

static inline long mb_getenv_required_long(const char *name, long min_value, long max_value) {
    const char *s = getenv(name);
    if (!s || !*s) {
        fprintf(stderr, "Missing required environment variable %s\n", name);
        exit(2);
    }
    return mb_getenv_long(name, 0L, min_value, max_value);
}

static inline double mb_getenv_double(const char *name, double default_value, double min_value, double max_value) {
    const char *s = getenv(name);
    if (!s || !*s) return default_value;

    errno = 0;
    char *end = NULL;
    double v = strtod(s, &end);
    if (errno != 0 || end == s || (end && *end != '\0')) {
        fprintf(stderr, "Invalid %s='%s' (expected float)\n", name, s);
        exit(2);
    }
    if (v < min_value || v > max_value) {
        fprintf(stderr, "Out of range %s=%f (expected %f..%f)\n", name, v, min_value, max_value);
        exit(2);
    }
    return v;
}

static inline double mb_getenv_required_double(const char *name, double min_value, double max_value) {
    const char *s = getenv(name);
    if (!s || !*s) {
        fprintf(stderr, "Missing required environment variable %s\n", name);
        exit(2);
    }
    return mb_getenv_double(name, 0.0, min_value, max_value);
}

#endif