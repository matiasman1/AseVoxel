/* stb_image_write - v1.16 - public domain image writer
   Minimal subset: only stbi_write_png used in this project.
   (This is a trimmed version for brevity; for production, use official header.)
*/
#ifndef STB_IMAGE_WRITE_H
#define STB_IMAGE_WRITE_H

#include <stdio.h>
#include <stdlib.h>

int stbi_write_png(const char *filename, int w, int h, int comp, const void *data, int stride_in_bytes);

#endif // STB_IMAGE_WRITE_H
