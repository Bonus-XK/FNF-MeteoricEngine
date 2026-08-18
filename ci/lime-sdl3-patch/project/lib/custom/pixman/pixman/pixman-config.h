/* 最小 pixman 配置（SDL3 移植用，关闭 SIMD 保证跨平台编译） */
#ifndef PIXMAN_CONFIG_H
#define PIXMAN_CONFIG_H

#define PACKAGE "pixman"
#define PACKAGE_VERSION "0.46.5"
#define PACKAGE_STRING "pixman 0.46.5"
#define PACKAGE_BUGREPORT "pixman@lists.freedesktop.org"
#define PACKAGE_NAME "pixman"
#define VERSION "0.46.5"

#define PIXMAN_VERSION_MAJOR 0
#define PIXMAN_VERSION_MINOR 42
#define PIXMAN_VERSION_MICRO 2
#define PIXMAN_VERSION_STRING "0.46.5"

#define HAVE_STDINT_H 1
#define HAVE_UNISTD_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_MEMORY_H 1
#define HAVE_STRING_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STDDEF_H 1
#define HAVE_FLOAT_H 1
#define HAVE_PTHREAD_H 1

/* mac/linux 用 pthread TLS；android/windows 由 files.xml 定义 PIXMAN_NO_TLS 优先 */
#define HAVE_PTHREADS 1

#endif
