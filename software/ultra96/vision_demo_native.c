#include "vision_benchmark.h"
#include "vision_sim.h"
#include "vector_classifier_weights.h"
#include "vector_front_config.h"
#include "controller_images.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static vision_sim_t sim;

static int read_words(const char *path, uint32_t words[784])
{
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    for (int i = 0; i < 784; ++i) {
        unsigned word;
        if (fscanf(f, "%x", &word) != 1) { fclose(f); return -1; }
        words[i] = (uint32_t)word;
    }
    unsigned extra;
    int trailing = fscanf(f, "%x", &extra);
    fclose(f);
    return trailing == EOF ? 0 : -1;
}

int main(int argc, char **argv)
{
    uint32_t input[784], golden[784];
    uint8_t pixels[784];
    vision_front_t front;
    vision_device_t d;
    vision_run_t run;
    vision_software_run_t software;
    if (argc != 4 && argc != 5) {
        fprintf(stderr, "usage: vision_demo input.mem expected_features.mem repeats [rtl_capture.mem]\n");
        return 2;
    }
    char *end;
    unsigned long count = strtoul(argv[3], &end, 10);
    if (*end || count == 0 || count > 1000) return 2;
    if (read_words(argv[1], input) || read_words(argv[2], golden)) return 3;
    for (int i = 0; i < 784; ++i) {
        if (input[i] > 255) return 3;
        pixels[i] = (uint8_t)input[i];
    }
    memcpy(front.weights, vector_conv_weights, sizeof(front.weights));
    memcpy(front.bias, vector_conv_bias, sizeof(front.bias));
    memcpy(front.shift, vector_conv_shift, sizeof(front.shift));
    memcpy(front.relu, vector_conv_relu_enable, sizeof(front.relu));
    vision_print_csv_header();
    for (int control = 0; control < 3; ++control) {
        vision_sim_init(&sim);
        uint32_t capture[784];
        if (argc == 5) {
            if (read_words(argv[4], capture) || memcmp(capture, golden, sizeof(capture))) return 4;
            sim.replay = capture;
        }
        vision_platform_t p = vision_sim_platform(&sim);
        if (vision_device_init(&d, &p, vision_sim_input(&sim), vision_sim_output(&sim),
                control == 1 ? VISION_ARM_CONTROL : VISION_RV32_CONTROL, p.ticks_per_second, 100000) ||
            vision_device_boot(&d, rv32_controller_imem_words, RV32_CONTROLLER_IMEM_WORD_COUNT,
                rv32_controller_dmem_words, RV32_CONTROLLER_DMEM_WORD_COUNT, &front)) return 5;
        if (control == 2 && vision_device_set_irq(&d, 1)) return 5;
        for (unsigned iteration = 0; iteration <= count; ++iteration) {
            int result = vision_run_image(&d, pixels, &vector_classifier_model, &run);
            vision_print_run(&d, 0, iteration, iteration == 0, &run);
            if (result || memcmp(sim.output, golden, sizeof(golden))) return 6;
            if (vision_software_benchmark(&p, pixels, &front, &vector_classifier_model, &software) ||
                software.prediction != run.prediction) return 7;
            if (control == 0) vision_print_software(&p, 0, iteration, iteration == 0, &software);
        }
    }
    return 0;
}
