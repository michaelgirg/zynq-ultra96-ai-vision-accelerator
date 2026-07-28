#pragma once

#define VISION_REG_CTRL                0x000u
#define VISION_REG_STATUS              0x004u
#define VISION_REG_THRESHOLD           0x008u
#define VISION_REG_IMAGE_PIXELS        0x00Cu
#define VISION_REG_PIXELS_PER_CYCLE    0x010u
#define VISION_REG_PROCESSING_CYCLES   0x014u
#define VISION_REG_MODE                0x02Cu
#define VISION_REG_VECTOR_CFG_COMMIT   0x068u
#define VISION_REG_VECTOR_CFG_VERSION  0x06Cu
#define VISION_REG_IP_ID               0x070u
#define VISION_REG_IP_VERSION          0x074u
#define VISION_REG_CAPABILITIES        0x078u
#define VISION_REG_FRAME_COUNT         0x07Cu
#define VISION_REG_ERROR_COUNT         0x080u
#define VISION_REG_ERROR_STATUS        0x08Cu
#define VISION_REG_INT_STATUS          0x090u
#define VISION_REG_INT_ENABLE          0x094u
#define VISION_REG_PERF_CONTROL        0x098u

#define VISION_CTRL_START              0x00000001u
#define VISION_CTRL_CLEAR_DONE         0x00000002u
#define VISION_STATUS_BUSY             0x00000001u
#define VISION_STATUS_DONE             0x00000002u
#define VISION_STATUS_PACKET_ERROR     0x00000004u
#define VISION_STATUS_ARMED            0x00000008u

#define VISION_MODE_THRESHOLD          0u
#define VISION_MODE_SOBEL              1u
#define VISION_MODE_CONV3X3            2u
#define VISION_MODE_VECTOR4            3u

#define VISION_IP_ID_VALUE             0x5A424156u
