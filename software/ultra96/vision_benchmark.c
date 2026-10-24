#include "vision_benchmark.h"
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#ifndef VISION_MODEL_SHA256
#define VISION_MODEL_SHA256 unbound
#endif
#define VISION_STRING_INNER(x) #x
#define VISION_STRING(x) VISION_STRING_INNER(x)

int vision_software_benchmark(const vision_platform_t *p, const uint8_t image[784],
    const vision_front_t *front, const vector_classifier_model_t *model, vision_software_run_t *s)
{
    uint32_t packed[784];
    uint64_t start, head;
    if (!p || !p->ticks || !image || !front || !model || !model->fc1_weights ||
        !model->fc1_bias || !model->fc2_weights || !model->fc2_bias || !s) return VISION_INVALID;
    memset(s, 0, sizeof(*s)); s->prediction = -1;
    start = p->ticks(p->context);
    if (vector_front_reference(image, front, packed)) return VISION_INVALID;
    head = p->ticks(p->context); s->front = head-start;
    s->prediction = vector_classifier_predict(packed, model, s->logits);
    s->classifier = p->ticks(p->context)-head;
    s->total = p->ticks(p->context)-start;
    return VISION_OK;
}

void vision_print_csv_header(void)
{
    puts("backend,measurement_domain,path,sample,iteration,warmup,tick_hz,prepare_ticks,cache_clean_ticks,submit_wait_ticks,invalidate_ticks,classifier_ticks,total_ticks,prediction,result,job_id,stage,firmware_error,mm2s_status,s2mm_status,accel_status,accel_errors,accel_cycles,recovery_result,software_front_ticks,model_sha256");
}
void vision_print_run(const vision_device_t *d, unsigned sample, unsigned iteration,
    int warmup, const vision_run_t *r)
{
    const vision_diagnostics_t *s = &r->diagnostics;
    printf("%s,%s,%s,%u,%u,%d,%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64
           ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%d,%d,%u,%s,%u,%u,%u,%u,%u,%u,%d,0,%s\n",
        d->platform.backend_name, d->platform.physical_hardware ? "board" : "host-functional-model",
        d->control == VISION_RV32_CONTROL ? "rv32-control" : "arm-control",
        sample, iteration, warmup, d->platform.ticks_per_second, r->prepare, r->cache_clean,
        r->submit_wait, r->cache_invalidate, r->classifier, r->total, r->prediction,
        s->result, s->job_id, vision_stage_name(s->stage), s->firmware_error,
        s->mm2s_status, s->s2mm_status, s->accelerator_status, s->accelerator_errors,
        s->accelerator_cycles, s->recovery_result, VISION_STRING(VISION_MODEL_SHA256));
}
void vision_print_software(const vision_platform_t *p, unsigned sample, unsigned iteration,
    int warmup, const vision_software_run_t *s)
{
    printf("%s,%s,software,%u,%u,%d,%" PRIu64 ",0,0,0,0,%" PRIu64
           ",%" PRIu64 ",%d,0,0,idle,0,0,0,0,0,0,0,%" PRIu64 ",%s\n", p->backend_name,
        p->physical_hardware ? "board" : "host-functional-model", sample, iteration,
        warmup, p->ticks_per_second, s->classifier, s->total, s->prediction, s->front,
        VISION_STRING(VISION_MODEL_SHA256));
}
