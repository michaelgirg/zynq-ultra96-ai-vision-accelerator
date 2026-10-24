#pragma once

#include <stdint.h>

#define VECTOR_CONV_FILTERS 4
#define VECTOR_CONV_TAPS 9

static const int8_t vector_conv_weights[VECTOR_CONV_FILTERS][VECTOR_CONV_TAPS] = {
    { 29, 104, 127, -115, -76, 58, -78, -92, -114 },
    { 13, -13, -116, -49, -79, 15, -127, -26, 11 },
    { 48, -11, -127, -111, -76, -35, 39, 126, 94 },
    { -60, -14, 114, -74, 108, 15, 29, 127, 83 },
};

static const int32_t vector_conv_bias[VECTOR_CONV_FILTERS] = {
    11029, 17936, 257, -131
};

static const uint8_t vector_conv_shift[VECTOR_CONV_FILTERS] = {
    9, 7, 9, 9
};

static const uint8_t vector_conv_relu_enable[VECTOR_CONV_FILTERS] = { 1, 1, 1, 1 };

static const float vector_conv_output_scale[VECTOR_CONV_FILTERS] = {
    0.01005770639f, 0.002520010807f, 0.00889567472f, 0.007636972237f
};
