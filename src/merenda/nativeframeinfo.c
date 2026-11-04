/* Image metadata for offline symbolication. No debug files are needed here. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "nativeframeinfo.h"
#include <stdio.h>
#include <string.h>

static void hex_bytes(char *out, const unsigned char *bytes, size_t count) {
  static const char digits[] = "0123456789abcdef";
  size_t i;
  for (i = 0; i < count; ++i) {
    out[2 * i] = digits[bytes[i] >> 4];
    out[2 * i + 1] = digits[bytes[i] & 15];
  }
  out[2 * count] = 0;
}

#if defined(__APPLE__)
#include <dlfcn.h>
#include <mach-o/loader.h>

int merenda_frame_info(uintptr_t pc, MerendaFrameInfo *info) {
  Dl_info image;
  const struct mach_header_64 *header;
  const unsigned char *command, *end;
  uint32_t i;
  memset(info, 0, sizeof(*info));
  if (!dladdr((const void *)pc, &image) || !image.dli_fbase) return 0;
  info->loadBase = (uintptr_t)image.dli_fbase;
  info->symbolAddress = pc - info->loadBase;
  snprintf(info->imageName, sizeof(info->imageName), "%s", image.dli_fname);
  header = (const struct mach_header_64 *)image.dli_fbase;
  if (header->magic != MH_MAGIC_64) return 1;
  command = (const unsigned char *)(header + 1);
  end = command + header->sizeofcmds;
  for (i = 0; i < header->ncmds && command + sizeof(struct load_command) <= end; ++i) {
    const struct load_command *load = (const struct load_command *)command;
    if (load->cmdsize < sizeof(*load) || load->cmdsize > (size_t)(end - command)) break;
    if (load->cmd == LC_UUID && load->cmdsize >= sizeof(struct uuid_command)) {
      strcpy(info->imageId, "uuid:");
      hex_bytes(info->imageId + 5, ((const struct uuid_command *)load)->uuid, 16);
    } else if (load->cmd == LC_SEGMENT_64 && load->cmdsize >= sizeof(struct segment_command_64)) {
      const struct segment_command_64 *segment = (const struct segment_command_64 *)load;
      if (strncmp(segment->segname, "__TEXT", 16) == 0)
        info->symbolAddress = pc - info->loadBase + segment->vmaddr;
    }
    command += load->cmdsize;
  }
  return 1;
}

#elif defined(__linux__) || defined(__FreeBSD__)
#include <link.h>
#include <unistd.h>

struct frame_query { uintptr_t pc; MerendaFrameInfo *info; int found; };

static int find_image(struct dl_phdr_info *image, size_t size, void *data) {
  struct frame_query *query = (struct frame_query *)data;
  MerendaFrameInfo *info = query->info;
  size_t i;
  (void)size;
  for (i = 0; i < image->dlpi_phnum; ++i) {
    const ElfW(Phdr) *segment = &image->dlpi_phdr[i];
    uintptr_t start = image->dlpi_addr + segment->p_vaddr;
    if (segment->p_type == PT_LOAD && query->pc >= start && query->pc - start < segment->p_memsz)
      query->found = 1;
  }
  if (!query->found) return 0;
  info->loadBase = image->dlpi_addr;
  info->symbolAddress = query->pc - image->dlpi_addr;
  snprintf(info->imageName, sizeof(info->imageName), "%s",
           image->dlpi_name[0] ? image->dlpi_name : "<main>");
#if defined(__linux__)
  if (!image->dlpi_name[0]) {
    ssize_t length = readlink("/proc/self/exe", info->imageName, sizeof(info->imageName) - 1);
    if (length >= 0) info->imageName[length] = 0;
  }
#endif
  for (i = 0; i < image->dlpi_phnum; ++i) {
    const ElfW(Phdr) *segment = &image->dlpi_phdr[i];
    const unsigned char *note, *end;
    if (segment->p_type != PT_NOTE) continue;
    note = (const unsigned char *)(image->dlpi_addr + segment->p_vaddr);
    end = note + segment->p_memsz;
    while ((size_t)(end - note) >= sizeof(ElfW(Nhdr))) {
      ElfW(Nhdr) header;
      size_t names, desc;
      memcpy(&header, note, sizeof(header));
      note += sizeof(header);
      names = ((size_t)header.n_namesz + 3) & ~(size_t)3;
      desc = ((size_t)header.n_descsz + 3) & ~(size_t)3;
      if (names < header.n_namesz || desc < header.n_descsz ||
          names > (size_t)(end - note) || desc > (size_t)(end - note) - names) break;
      if (header.n_type == NT_GNU_BUILD_ID && header.n_namesz == 4 &&
          memcmp(note, "GNU", 4) == 0 && header.n_descsz > 0 && header.n_descsz <= 64) {
        strcpy(info->imageId, "build-id:");
        hex_bytes(info->imageId + 9, note + names, header.n_descsz);
      }
      note += names + desc;
    }
  }
  return 1;
}

int merenda_frame_info(uintptr_t pc, MerendaFrameInfo *info) {
  struct frame_query query = {pc, info, 0};
  memset(info, 0, sizeof(*info));
  dl_iterate_phdr(find_image, &query);
  return query.found;
}

#elif defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

int merenda_frame_info(uintptr_t pc, MerendaFrameInfo *info) {
  HMODULE image;
  const unsigned char *base;
  const IMAGE_DOS_HEADER *dos;
  const IMAGE_NT_HEADERS *nt;
  IMAGE_DATA_DIRECTORY directory;
  size_t i;
  memset(info, 0, sizeof(*info));
  if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
      GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)pc, &image)) return 0;
  base = (const unsigned char *)image;
  dos = (const IMAGE_DOS_HEADER *)base;
  nt = (const IMAGE_NT_HEADERS *)(base + dos->e_lfanew);
  info->loadBase = (uintptr_t)base;
  info->symbolAddress = pc - info->loadBase + nt->OptionalHeader.ImageBase;
  GetModuleFileNameA(image, info->imageName, sizeof(info->imageName));
  info->imageName[sizeof(info->imageName) - 1] = 0;
  snprintf(info->imageId, sizeof(info->imageId), "pe:%08lx-%08lx",
           (unsigned long)nt->FileHeader.TimeDateStamp, (unsigned long)nt->OptionalHeader.SizeOfImage);
  directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG];
  if (directory.VirtualAddress > nt->OptionalHeader.SizeOfImage ||
      directory.Size > nt->OptionalHeader.SizeOfImage - directory.VirtualAddress) return 1;
  for (i = 0; i + sizeof(IMAGE_DEBUG_DIRECTORY) <= directory.Size; i += sizeof(IMAGE_DEBUG_DIRECTORY)) {
    const IMAGE_DEBUG_DIRECTORY *debug = (const IMAGE_DEBUG_DIRECTORY *)(base + directory.VirtualAddress + i);
    const unsigned char *cv;
    uint32_t age;
    if (debug->Type != IMAGE_DEBUG_TYPE_CODEVIEW || debug->SizeOfData < 24 ||
        debug->AddressOfRawData > nt->OptionalHeader.SizeOfImage ||
        debug->SizeOfData > nt->OptionalHeader.SizeOfImage - debug->AddressOfRawData) continue;
    cv = base + debug->AddressOfRawData;
    if (memcmp(cv, "RSDS", 4) != 0) continue;
    strcpy(info->imageId, "codeview:");
    hex_bytes(info->imageId + 9, cv + 4, 16);
    memcpy(&age, cv + 20, sizeof(age));
    snprintf(info->imageId + 41, sizeof(info->imageId) - 41, "-%lu", (unsigned long)age);
    break;
  }
  return 1;
}

#else
int merenda_frame_info(uintptr_t pc, MerendaFrameInfo *info) {
  (void)pc;
  memset(info, 0, sizeof(*info));
  return 0;
}
#endif
