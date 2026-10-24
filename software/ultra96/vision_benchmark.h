#pragma once
#include "vision_runtime.h"

typedef struct {
    uint64_t front, classifier, total;
    int prediction;
    float logits[10];
} vision_software_run_t;

int vision_software_benchmark(const vision_platform_t *, const uint8_t image[784],
    const vision_front_t *, const vector_classifier_model_t *, vision_software_run_t *);
void vision_print_csv_header(void);
void vision_print_run(const vision_device_t *, unsigned sample, unsigned iteration,
    int warmup, const vision_run_t *);
void vision_print_software(const vision_platform_t *, unsigned sample, unsigned iteration,
    int warmup, const vision_software_run_t *);
