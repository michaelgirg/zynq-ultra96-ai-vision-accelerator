#include <inttypes.h>
#include <stdio.h>
#include "vector_classifier.h"
#include "vector_classifier_weights.h"

int main(int argc, char **argv)
{
    uint32_t packed[VECTOR_CLASSIFIER_PIXELS];
    float logits[VECTOR_CLASSIFIER_CLASSES];
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
    int prediction = vector_classifier_predict(packed, &vector_classifier_model, logits);
    printf("%d", prediction);
    for (int index = 0; index < VECTOR_CLASSIFIER_CLASSES; ++index) {
        printf(" %.9g", (double)logits[index]);
    }
    printf("\n");
    return 0;
}
