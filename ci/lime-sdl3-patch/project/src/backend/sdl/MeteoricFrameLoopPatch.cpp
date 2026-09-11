#include <system/CFFI.h>

#if defined(__has_include)
	#if __has_include(<SDL3/SDL_version.h>)
		#include <SDL3/SDL_version.h>
	#endif
#endif


// ============================================================================
// Meteoric：原生帧循环「墙钟补丁」能力标记
// ----------------------------------------------------------------------------
// 背景（起因见 2026-09-11 事故）：
//   本项目桌面端用 drawFramerate = 100000 当「无人工限制」哨兵，它把原生帧循环的
//   framePeriod 压到 0.01ms。老版 lime 的 SDL 帧循环里 nextUpdate 是整型、
//   currentUpdate 取 SDL_GetTicks()（1ms 地板）：
//       nextUpdate += framePeriod;              // 整型 → 每次 +0
//       while (nextUpdate <= currentUpdate) {}  // 永不前进 → 主线程 100% 死循环
//   于是启动阶段就卡死（黑屏卡在加载界面）。
//   本仓库 ci/lime-sdl3-patch 的 SDLApplication.cpp 已修好这件事：
//   HiResMs() 高精度时钟 + framePeriod/nextUpdate/currentUpdate/lastUpdate 全 double
//   + SDL_DelayNS 精睡 + WaitEventTimeout 事件等待。但那道补丁**必须先编进 lime.ndll**
//   才生效，引擎侧此前无从判断手上这份 ndll 到底打没打补丁。
//
// 本标记就是那个判据：导出纯 C 函数 lime_meteoric_frame_loop_patch，返回 1 表示
// 本次构建来自带墙钟补丁的 SDL3 源码树，返回 0 表示不是。
//   引擎（source/backend/ClientPrefs.hx）启动时用
//       cpp.Lib._loadPrime(null, "lime_meteoric_frame_loop_patch", "", true)
//   探测：拿到函数指针 → 调用取版本号；拿不到（老 ndll 里没这个符号）→ 返回 null，
//   引擎退回 480 档。宁可跑不出极限帧率，也绝不启动死循环。
//
// ⚠ 实现约束（踩过的坑，别改回去）：
//   这里**不能**用 DEFINE_PRIME0 注册 cffi 原语。hxcpp 的 CFFI.h 规定
//   「一个模块里 DEFINE_PRIME* 只能出现一次、且该模块要定义 IMPLEMENT_API」，
//   而 lime 的 src/ExternalInterface.cpp 已经占用了这个位置：两个模块同时定义
//   IMPLEMENT_API 会让链接期报一大片
//       multiple definition of `hx_register_prim' / `val_ocall2' / ...
//   （这些是 CFFIPrime.h 展开出来的全局桩）。用普通导出符号 + hxcpp 的
//   `__hxcpp_cast_get_proc_address`（cpp.Lib._loadPrime 走的就是它）没有任何副作用，
//   也不需要签名校验，是这里最干净的接法。
// ============================================================================

#if defined(HX_WINDOWS)
	#define METEORIC_PROBE_EXPORT extern "C" __declspec(dllexport)
#else
	#define METEORIC_PROBE_EXPORT extern "C" __attribute__((visibility("default")))
#endif

METEORIC_PROBE_EXPORT int lime_meteoric_frame_loop_patch () {

	#if defined(SDL_MAJOR_VERSION) && SDL_MAJOR_VERSION >= 3
	// SDL3 头可见 = 本次构建来自 ci/lime-sdl3-patch 树
	// （SDLApplication.cpp 的双精度帧循环补丁随之生效）
	return 1;
	#else
	// 非 SDL3 后端：本构建不提供墙钟帧循环，如实返回 0
	return 0;
	#endif

}
