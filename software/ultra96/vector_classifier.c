#include "vector_classifier.h"

int vector_classifier_predict(
    const uint32_t packed[VECTOR_CLASSIFIER_PIXELS],
    const vector_classifier_model_t *model,
    float logits[VECTOR_CLASSIFIER_CLASSES]
)
{
    uint8_t pooled[VECTOR_CLASSIFIER_INPUTS];
    float hidden[VECTOR_CLASSIFIER_HIDDEN];

    for (int channel = 0; channel < VECTOR_CLASSIFIER_FILTERS; ++channel) {
        for (int row = 0; row < 14; ++row) {
            for (int col = 0; col < 14; ++col) {
                uint8_t maximum = 0;
                for (int dy = 0; dy < 2; ++dy) {
                    for (int dx = 0; dx < 2; ++dx) {
                        uint32_t word = packed[(row * 2 + dy) * 28 + col * 2 + dx];
                        uint8_t value = (uint8_t)(word >> (channel * 8));
                        if (value > maximum) maximum = value;
                    }
                }
                pooled[channel * 196 + row * 14 + col] = maximum;
            }
        }
    }
    for (int neuron = 0; neuron < VECTOR_CLASSIFIER_HIDDEN; ++neuron) {
        float accumulator = model->fc1_bias[neuron];
        for (int input = 0; input < VECTOR_CLASSIFIER_INPUTS; ++input) {
            accumulator += (float)pooled[input] *
                model->fc1_weights[neuron * VECTOR_CLASSIFIER_INPUTS + input];
        }
        hidden[neuron] = accumulator > 0.0f ? accumulator : 0.0f;
    }
    int prediction = 0;
    for (int output = 0; output < VECTOR_CLASSIFIER_CLASSES; ++output) {
        float accumulator = model->fc2_bias[output];
        for (int neuron = 0; neuron < VECTOR_CLASSIFIER_HIDDEN; ++neuron) {
            accumulator += hidden[neuron] *
                model->fc2_weights[output * VECTOR_CLASSIFIER_HIDDEN + neuron];
        }
        logits[output] = accumulator;
        if (logits[output] > logits[prediction]) prediction = output;
    }
    return prediction;
}
