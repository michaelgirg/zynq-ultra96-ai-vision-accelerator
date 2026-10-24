#pragma once

#include <stdint.h>

#define VECTOR_CONV_FILTERS 4
#define VECTOR_CONV_TAPS 9

static const int8_t vector_conv_weights[VECTOR_CONV_FILTERS][VECTOR_CONV_TAPS] = {
    { 10, 90, 104, -86, -21, 13, -105, -86, -127 },
    { -27, -108, -120, -80, -48, 60, -127, 22, 62 },
    { 9, -59, -125, -63, -52, -22, 42, 127, 108 },
    { -91, -2, 124, -97, 110, 62, 29, 127, 75 },
};

static const int32_t vector_conv_bias[VECTOR_CONV_FILTERS] = {
    2592, 14250, 122, 20
};

static const uint8_t vector_conv_shift[VECTOR_CONV_FILTERS] = {
    8, 8, 9, 10
};

static const uint8_t vector_conv_relu_enable[VECTOR_CONV_FILTERS] = { 1, 1, 1, 1 };

static const float vector_conv_output_scale[VECTOR_CONV_FILTERS] = {
    0.008826675825f, 0.006982025225f, 0.010635579f, 0.02229058556f
};
