#ifndef MERENDA_NATIVE_FRAME_INFO_H
#define MERENDA_NATIVE_FRAME_INFO_H
#include <stdint.h>

typedef struct {
  uintptr_t loadBase;
  uintptr_t symbolAddress;
  char imageName[1024];
  char imageId[160];
} MerendaFrameInfo;

int merenda_frame_info(uintptr_t pc, MerendaFrameInfo *info);
#endif
