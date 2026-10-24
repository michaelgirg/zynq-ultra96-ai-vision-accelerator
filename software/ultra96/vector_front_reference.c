#include "vector_front_reference.h"
#include <stddef.h>

int vector_front_reference(const uint8_t image[784], const vision_front_t *front,
                           uint32_t packed[784])
{
    if (image == NULL || front == NULL || packed == NULL) return -1;
    for (int f = 0; f < 4; ++f) if (front->shift[f] > 31 || front->relu[f] > 1) return -1;
    for (int row = 0; row < 28; ++row) for (int col = 0; col < 28; ++col) {
        uint32_t word = 0;
        if (row != 0 && row != 27 && col != 0 && col != 27) {
            for (int f = 0; f < 4; ++f) {
                uint32_t acc = (uint32_t)front->bias[f];
                for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
                    int32_t product = (int32_t)image[(row+dy)*28+col+dx] *
                                      front->weights[f][(dy+1)*3+dx+1];
                    acc += (uint32_t)product; /* Defined modulo-2^32 arithmetic. */
                }
                int64_t signed_acc = (acc & 0x80000000u) ? (int64_t)acc - 4294967296LL : acc;
                int64_t divisor = (int64_t)1 << front->shift[f];
                int64_t value = signed_acc >= 0 ? signed_acc / divisor :
                    -((-signed_acc + divisor - 1) / divisor);
                /* RTL saturates negative values even when ReLU is disabled. */
                if (value < 0) value = 0;
                if (value > 255) value = 255;
                word |= (uint32_t)value << (f*8);
            }
        }
        packed[row*28+col] = word;
    }
    return 0;
}
