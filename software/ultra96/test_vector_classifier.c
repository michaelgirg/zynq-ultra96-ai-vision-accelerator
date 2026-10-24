#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include "vector_classifier.h"
#include "vector_classifier_weights.h"

static void print_prediction(const uint32_t packed[VECTOR_CLASSIFIER_PIXELS])
{
    float logits[VECTOR_CLASSIFIER_CLASSES];
    int prediction = vector_classifier_predict(packed, &vector_classifier_model, logits);
    printf("%d", prediction);
    for (int index = 0; index < VECTOR_CLASSIFIER_CLASSES; ++index) {
        printf(" %.9g", (double)logits[index]);
    }
    printf("\n");
}

int main(int argc, char **argv)
{
    uint32_t packed[VECTOR_CLASSIFIER_PIXELS];
    if (argc == 3 && strcmp(argv[1], "--batch") == 0) {
        /* Explicit little-endian wire format, independent of host byte order. */
        unsigned char bytes[VECTOR_CLASSIFIER_PIXELS * 4];
        FILE *input = fopen(argv[2], "rb");
        if (input == NULL) return 3;
        size_t count;
        int frames = 0;
        while ((count = fread(bytes, 1, sizeof(bytes), input)) != 0) {
            if (count != sizeof(bytes)) { fclose(input); return 4; }
            for (int pixel = 0; pixel < VECTOR_CLASSIFIER_PIXELS; ++pixel) {
                int offset = pixel * 4;
                packed[pixel] = (uint32_t)bytes[offset] |
                    ((uint32_t)bytes[offset + 1] << 8) |
                    ((uint32_t)bytes[offset + 2] << 16) |
                    ((uint32_t)bytes[offset + 3] << 24);
            }
            print_prediction(packed);
            ++frames;
        }
        int failed = ferror(input) || frames == 0;
        fclose(input);
        return failed ? 4 : 0;
    }
    if (argc != 2) return 2;
    FILE *input = fopen(argv[1], "r");
    if (input == NULL) return 3;
    for (int pixel = 0; pixel < VECTOR_CLASSIFIER_PIXELS; ++pixel) {
        if (fscanf(input, "%" SCNx32, &packed[pixel]) != 1) {
            fclose(input);
            return 4;
        }
    }
    uint32_t extra;
    int trailing = fscanf(input, "%" SCNx32, &extra);
    fclose(input);
    if (trailing != EOF) return 5;
    print_prediction(packed);
    return 0;
}
