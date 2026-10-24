#pragma once
#include <stdint.h>

typedef struct {
    int8_t weights[4][9];
    int32_t bias[4];
    uint8_t shift[4];
    uint8_t relu[4];
} vision_front_t;

/* Bit-exact mode-3 software reference, including zero borders and 32-bit wrap. */
int vector_front_reference(const uint8_t image[784], const vision_front_t *front,
                           uint32_t packed[784]);
