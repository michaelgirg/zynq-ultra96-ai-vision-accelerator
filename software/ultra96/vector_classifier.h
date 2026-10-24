#pragma once

#include <stdint.h>

#define VECTOR_CLASSIFIER_PIXELS 784
#define VECTOR_CLASSIFIER_FILTERS 4
#define VECTOR_CLASSIFIER_INPUTS 784
#define VECTOR_CLASSIFIER_HIDDEN 64
#define VECTOR_CLASSIFIER_CLASSES 10

typedef struct {
    const float *fc1_weights;
    const float *fc1_bias;
    const float *fc2_weights;
    const float *fc2_bias;
} vector_classifier_model_t;

/* Input is 28x28 row-major DMA words; channel zero occupies bits [7:0].
 * Per-channel dequantization scales are folded into exported fc1 weights.
 * The caller invalidates DMA buffer cache lines before calling this routine.
 */
int vector_classifier_predict(
    const uint32_t packed[VECTOR_CLASSIFIER_PIXELS],
    const vector_classifier_model_t *model,
    float logits[VECTOR_CLASSIFIER_CLASSES]
);
