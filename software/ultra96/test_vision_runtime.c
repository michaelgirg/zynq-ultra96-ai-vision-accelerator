#include "vision_runtime.h"
#include "vision_sim.h"
#include "vector_classifier_weights.h"
#include "vector_front_config.h"
#include "job_mailbox.h"
#include "soc_address_map.h"
#include "axi_dma_regs.h"
#include <stdio.h>
#include <string.h>

static vision_sim_t sim;
static int checks;
#define CHECK(c) do { ++checks; if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)
static const uint32_t instructions[] = {0x13u, 0x100073u};
static const uint32_t data[] = {0xdeadbeefu};
static vision_front_t front;
static vision_device_t device;
static uint8_t image[784];
static vision_run_t run;

static int setup(enum vision_control control)
{
    vision_sim_init(&sim);
    vision_platform_t p = vision_sim_platform(&sim);
    int result = vision_device_init(&device, &p, vision_sim_input(&sim), vision_sim_output(&sim),
        control, p.ticks_per_second, 100);
    if (result) return result;
    return vision_device_boot(&device, instructions, 2, data, 1, &front);
}

int main(void)
{
    memcpy(front.weights, vector_conv_weights, sizeof(front.weights));
    memcpy(front.bias, vector_conv_bias, sizeof(front.bias));
    memcpy(front.shift, vector_conv_shift, sizeof(front.shift));
    memcpy(front.relu, vector_conv_relu_enable, sizeof(front.relu));
    vision_front_t edge = {0};
    uint32_t edge_output[784];
    memset(image, 1, sizeof(image));
    edge.bias[0] = INT32_MAX; edge.weights[0][4] = 1;
    edge.bias[1] = INT32_MIN; edge.weights[1][4] = -1;
    edge.bias[2] = -1; edge.shift[2] = 31;
    edge.bias[3] = 512; edge.shift[3] = 1;
    CHECK(vector_front_reference(image, &edge, edge_output) == 0);
    CHECK(edge_output[29] == 0xff00ff00u && edge_output[0] == 0 && edge_output[783] == 0);
    for (int i = 0; i < 784; ++i) image[i] = (uint8_t)(i*31);
    for (int control = 0; control < 2; ++control) {
        CHECK(setup((enum vision_control)control) == 0);
        CHECK(sim.resetn == (control == VISION_RV32_CONTROL));
        CHECK(sim.imem[1] == instructions[1] && sim.dmem[0] == data[0]);
        CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == 0);
        CHECK(run.prediction >= 0 && run.prediction < 10 && sim.invalidates == 1);
        CHECK(run.diagnostics.job_id == 1 && sim.launches == 1);
        uint32_t golden[784];
        CHECK(vector_front_reference(image, &front, golden) == 0);
        CHECK(memcmp(golden, sim.output, sizeof(golden)) == 0);
        for (int fault = SIM_MM2S; fault <= SIM_PACKET; ++fault) {
            sim.fault = (enum vision_sim_fault)fault;
            int invalidates = sim.invalidates;
            int status = vision_run_image(&device, image, &vector_classifier_model, &run);
            if (status != VISION_JOB_FAILED)
                fprintf(stderr, "control=%d fault=%d status=%d firmware=%u stage=%s\n", control,
                    fault, status, run.diagnostics.firmware_error, vision_stage_name(run.diagnostics.stage));
            CHECK(status == VISION_JOB_FAILED);
            CHECK(run.diagnostics.firmware_error == (uint32_t)(fault-SIM_MM2S+3));
            CHECK(run.prediction == -1 && sim.invalidates == invalidates);
            CHECK(!device.quarantined);
            sim.fault = SIM_NONE;
            CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == 0);
        }
        sim.fault = SIM_TIMEOUT;
        sim.clock_stopped = 1; /* Secondary poll cap must bound a broken timer. */
        device.poll_limit = 8;
        CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == VISION_DEADLINE);
        CHECK(run.prediction == -1 && run.diagnostics.polls == 8);
        if (control == VISION_ARM_CONTROL) {
            CHECK(!device.quarantined && sim.resets > 0);
            sim.fault = SIM_NONE; sim.clock_stopped = 0;
            CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == 0);
        } else {
            CHECK(device.quarantined);
            CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == VISION_NEEDS_RESET);
        }
        CHECK(setup((enum vision_control)control) == 0);
        sim.fault = SIM_STUCK_RESET; device.poll_limit = 8;
        CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == VISION_DEADLINE);
        CHECK(device.quarantined && run.prediction == -1);
        CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == VISION_NEEDS_RESET);
    }
    for (int fault = SIM_BAD_ID; fault <= SIM_BAD_READBACK; ++fault) {
        CHECK(setup(VISION_RV32_CONTROL) == 0);
        sim.fault = (enum vision_sim_fault)fault;
        CHECK(vision_device_boot(&device, instructions, 2, data, 1, &front) != 0);
        CHECK(sim.resetn == 0 && !device.ready);
    }
    CHECK(setup(VISION_RV32_CONTROL) == 0);
    sim.tx_status = 0;
    CHECK(vision_device_boot(&device, instructions, 2, data, 1, &front) == VISION_BUSY);
    CHECK(!sim.resetn && !device.ready);
    CHECK(setup(VISION_RV32_CONTROL) == 0);
    sim.rx_status = 0x10;
    CHECK(vision_device_boot(&device, instructions, 2, data, 1, &front) == VISION_NEEDS_RESET);
    CHECK(device.quarantined && !sim.resetn);
    CHECK(setup(VISION_RV32_CONTROL) == 0);
    sim.fault = SIM_TIMEOUT; device.timeout_ticks = 1;
    CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == VISION_DEADLINE);
    CHECK(device.quarantined && run.prediction == -1 && sim.invalidates == 0);
    CHECK(setup(VISION_RV32_CONTROL) == 0);
    CHECK(vision_device_boot(&device, NULL, 0, NULL, 0, &front) == VISION_INVALID);
    CHECK(sim.resetn == 0);
    CHECK(setup(VISION_RV32_CONTROL) == 0);
    sim.fault = SIM_BUS_TIMEOUT;
    CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == VISION_NEEDS_RESET);
    CHECK(device.quarantined && run.prediction == -1 && sim.invalidates == 0);
    CHECK(run.diagnostics.axi_status == 3 && run.diagnostics.first_fault_kind == MAILBOX_FAULT_AXI);
    CHECK(run.diagnostics.first_fault_addr == SOC_AXI_DMA_BASE + DMA_MM2S_DMASR);
    CHECK(run.diagnostics.first_fault_info == MAILBOX_AXI_WAIT_R && run.diagnostics.first_fault_wait == 1000000);
    CHECK(run.diagnostics.axi_fault_addr == run.diagnostics.first_fault_addr &&
        run.diagnostics.axi_fault_info == MAILBOX_AXI_WAIT_R && run.diagnostics.axi_fault_wait == 1000000);
    CHECK(sim.unsafe_fault_reads == 0 && sim.mailbox[1] == 2 && sim.launches == 1);
    CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) == VISION_NEEDS_RESET);
    CHECK(setup(VISION_RV32_CONTROL) == 0);
    sim.fault = SIM_BUS_TIMEOUT;
    CHECK(vision_device_boot(&device, instructions, 2, data, 1, &front) == VISION_NEEDS_RESET);
    CHECK(device.quarantined && !sim.resetn && sim.unsafe_fault_reads == 0);
    for (int fault = SIM_CACHE_ERROR; fault <= SIM_WRONG_JOB; ++fault) {
        CHECK(setup(VISION_RV32_CONTROL) == 0);
        sim.fault = (enum vision_sim_fault)fault;
        CHECK(vision_run_image(&device, image, &vector_classifier_model, &run) != 0);
        CHECK(run.prediction == -1 && device.quarantined && sim.invalidates == 0);
    }
    CHECK(setup(VISION_RV32_CONTROL) == 0);
    vision_platform_t p = vision_sim_platform(&sim);
    vision_dma_buffer_t input = vision_sim_input(&sim), output = vision_sim_output(&sim);
    output.physical = input.physical;
    CHECK(vision_device_init(&device, &p, input, output, VISION_RV32_CONTROL, 10, 10) == VISION_INVALID);
    output = vision_sim_output(&sim); output.cpu++;
    CHECK(vision_device_init(&device, &p, input, output, VISION_RV32_CONTROL, 10, 10) == VISION_INVALID);
    output = vision_sim_output(&sim); output.physical = 0xfffffc00u;
    CHECK(vision_device_init(&device, &p, input, output, VISION_RV32_CONTROL, 10, 10) == VISION_INVALID);
    printf("PASS: vision runtime %d checks; cache ownership, failures, deadlines, recovery and quarantine\n", checks);
    return 0;
}
