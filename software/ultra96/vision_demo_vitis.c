/* Build in a standalone Cortex-A53 64-bit Vitis domain. No board execution
 * is implied by compiling this application. Reserve these arrays in low DDR. */
#include "vision_benchmark.h"
#include "vision_platform_vitis.h"
#include "vector_classifier_weights.h"
#include "vector_front_config.h"
#include "controller_images.h"
#include "sample_000_image_data.h"
#include "sample_001_image_data.h"
#include "sample_002_image_data.h"
#include "sample_003_image_data.h"
#include "sample_004_image_data.h"
#include "sample_005_image_data.h"
#include "sample_006_image_data.h"
#include "sample_007_image_data.h"
#include <stdio.h>
#include <string.h>

static uint32_t input_words[784] __attribute__((aligned(64), section(".vision_dma_input")));
static uint32_t output_words[784] __attribute__((aligned(64), section(".vision_dma_output")));
static const unsigned char *const images[] = {sample_000_input_image, sample_001_input_image,
    sample_002_input_image, sample_003_input_image, sample_004_input_image,
    sample_005_input_image, sample_006_input_image, sample_007_input_image};

int main(void)
{
    vision_front_t front;
    vision_device_t device;
    vision_run_t run;
    vision_software_run_t software;
    uint32_t expected_features[784];
    vision_platform_t platform = vision_vitis_platform();
    memcpy(front.weights, vector_conv_weights, sizeof(front.weights));
    memcpy(front.bias, vector_conv_bias, sizeof(front.bias));
    memcpy(front.shift, vector_conv_shift, sizeof(front.shift));
    memcpy(front.relu, vector_conv_relu_enable, sizeof(front.relu));
    vision_print_csv_header();
    if (vision_vitis_irq_init() != VISION_OK) { puts("# gic_init_failed"); return 1; }
    /* ARM first while RV32 is held reset. Never hot-reset a running MMIO
     * poller between measurements: its outstanding AXI read would quarantine. */
    for (int path = 0; path < 3; ++path) {
        int status = 0;
        if (path != 2) {
            status = vision_device_init(&device, &platform,
                vision_vitis_buffer(input_words, sizeof(input_words)),
                vision_vitis_buffer(output_words, sizeof(output_words)),
                path == 0 ? VISION_ARM_CONTROL : VISION_RV32_CONTROL,
                platform.ticks_per_second, 10000000);
            if (status == 0) status = vision_device_boot(&device, rv32_controller_imem_words,
                RV32_CONTROLLER_IMEM_WORD_COUNT, rv32_controller_dmem_words,
                RV32_CONTROLLER_DMEM_WORD_COUNT, &front);
        } else status = vision_device_set_irq(&device, 1);
        if (status != 0) {
            printf("# boot_failed=%d; verify IP version, generated platform and reserved low-DDR buffers\n", status);
            return 1;
        }
        if (path == 0) {
            memset(input_words, 0, sizeof(input_words));
            memset(output_words, 0, sizeof(output_words));
        }
        for (unsigned sample = 0; sample < 8; ++sample) for (unsigned iteration = 0; iteration < 6; ++iteration) {
            status = vision_run_image(&device, images[sample], &vector_classifier_model, &run);
            if (status != 0) {
                vision_print_run(&device, sample, iteration, iteration == 0, &run); return 2;
            }
            if (vision_software_benchmark(&platform, images[sample], &front,
                    &vector_classifier_model, &software) || software.prediction != run.prediction ||
                vector_front_reference(images[sample], &front, expected_features) ||
                memcmp(expected_features, output_words, sizeof(expected_features))) {
                run.diagnostics.result = VISION_VERIFY_ERROR;
                vision_print_run(&device, sample, iteration, iteration == 0, &run);
                puts("# software_hardware_feature_or_prediction_mismatch"); return 3;
            }
            vision_print_run(&device, sample, iteration, iteration == 0, &run);
            if (path == 0) vision_print_software(&platform, sample, iteration, iteration == 0, &software);
        }
    }
    return 0;
}
