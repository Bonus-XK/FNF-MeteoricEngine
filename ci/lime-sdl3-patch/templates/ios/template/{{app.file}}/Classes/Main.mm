#include <stdio.h>

// SDL3 移植（2026-11）：SDL2 时代 iOS 应用入口由 SDL 自带的 SDL_uikit_main.c 提供
// （编进静态 SDL），SDL3 删除了该文件，改为新契约 —— 应用提供 SDL_main，
// 由 SDL_RunApp 创建 UIApplicationMain 并以 SDL_main 为回调
// （include/SDL3/SDL_main.h 的 iOS 段 + SDL_main_impl.h）。
// 这里手动声明 SDL_RunApp 而 #include <SDL3/SDL_main.h>：Main.mm 由 Xcode 工程
// 编译，不保证有 hxcpp 侧的 SDL3 头搜索路径，手动 extern 声明零依赖。
extern "C" int SDL_RunApp (int argc, char *argv[], int (*mainFunction) (int argc, char *argv[]), void *reserved);

extern "C" const char *hxRunLibrary ();
extern "C" void hxcpp_set_top_of_stack ();

extern "C" int zlib_register_prims ();
extern "C" int lime_register_prims ();
::foreach ndlls::::if (registerStatics)::
extern "C" int ::nameSafe::_register_prims ();::end::::end::


extern "C" int SDL_main (int argc, char *argv[]) {

	hxcpp_set_top_of_stack ();

	zlib_register_prims ();
	lime_register_prims ();
	::foreach ndlls::::if (registerStatics)::
	::nameSafe::_register_prims ();::end::::end::

	const char *err = NULL;
	err = hxRunLibrary ();

	if (err) {

		printf ("Error %s\n", err);
		return -1;

	}

	return 0;

}

// SDL3 契约入口：SDL_RunApp 拉起 UIKit 事件循环后回调 SDL_main（上面）。
int main (int argc, char *argv[]) {

	return SDL_RunApp (argc, argv, SDL_main, NULL);

}
