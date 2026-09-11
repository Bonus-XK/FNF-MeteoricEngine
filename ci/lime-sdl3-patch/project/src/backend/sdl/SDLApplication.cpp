#include "SDLApplication.h"
#include "SDLGamepad.h"
#include "SDLJoystick.h"
#include <system/System.h>

#ifdef HX_MACOS
#include <CoreFoundation/CoreFoundation.h>
#endif

#ifdef EMSCRIPTEN
#include "emscripten.h"
#endif


namespace lime {

	// High-resolution time in milliseconds from the performance counter (mohong2/lime sdl3).
	static double HiResMs () {

		static double invFreq = -1.0;
		if (invFreq < 0) invFreq = 1000.0 / (double) SDL_GetPerformanceFrequency ();
		return (double) SDL_GetPerformanceCounter () * invFreq;

	}


	AutoGCRoot* Application::callback = 0;
	SDLApplication* SDLApplication::currentApplication = 0;

	const int analogAxisDeadZone = 1000;
	std::map<int, std::map<int, int> > gamepadsAxisMap;
	bool inBackground = false;


	SDLApplication::SDLApplication () {

		Uint32 initFlags = SDL_INIT_VIDEO | SDL_INIT_GAMEPAD | SDL_INIT_JOYSTICK;
		#if defined(LIME_MOJOAL) || defined(LIME_OPENALSOFT)
		initFlags |= SDL_INIT_AUDIO;
		#endif

		#ifdef HX_WINDOWS
		// 【Meteoric 修复】Windows 高清渲染开关：DPI 感知是进程级且必须在 SDL_Init 前设定，
		// 否则视频驱动初始化后无法再改。
		//   开（高清）= permonitorv2 —— 窗口按物理像素渲染（配合 SDLWindow 的缩放折算 → 清晰）；
		//   关（1x 高性能）= unaware —— Windows 把逻辑尺寸拉伸到物理屏幕（画面略糊但帧率高，
		//   与 macOS「高清渲染」关闭的语义一致）。
		// ⚠ SDL3 未公开 SDL_HINT_WINDOWS_DPI_AWARENESS 宏，视频驱动内部以该字符串读取
		//   （见 SDL_windowsvideo.c WIN_InitDPIAwareness），此处用相同字面量。
		bool meteoricUiHighDpi = SDLWindow::MeteoricHighDpiEnabled ();
		if (meteoricUiHighDpi && !SDLWindow::MeteoricScaledWindowFits (1280, 720))
		{
			// 【Meteoric 修复 2026-09-11】虚拟屏/小屏上「高清」会把窗口放大到装不下：
			//   SDLWindow 构造时按 显示器缩放 把 1280×720 逻辑窗口放大成物理像素
			//   （125% → 1600×900），屏幕只有 1280×800 时窗口直接溢出被裁 →
			//   用户看到「画面锁死在一个区域、右侧/下方被切掉」。
			//   这里在 SDL_Init 之前先量一下：**放不下就退回 unaware**，即保持逻辑尺寸的
			//   1280×720 窗口、画面完整（观感等同旧版没带高 DPI 代码的 ndll）。
			//   放得下（大屏/高分辨率）时一切照旧，高清渲染与物理像素管线不受影响。
			meteoricUiHighDpi = false;
		}
		SDL_SetHint ("SDL_WINDOWS_DPI_AWARENESS", meteoricUiHighDpi ? "permonitorv2" : "unaware");
		#endif

		// SDL3: SDL_Init 返回 bool（true=成功）；SDL2 返回 int（0=成功）
		if (!SDL_Init (initFlags)) {

			printf ("Could not initialize SDL: %s.\n", SDL_GetError ());

		}

		SDL_SetLogPriority (SDL_LOG_CATEGORY_APPLICATION, SDL_LOG_PRIORITY_WARN);

		currentApplication = this;

		framePeriod = 1000.0 / 60.0;

		currentUpdate = 0;
		lastUpdate = 0;
		nextUpdate = 0;

		ApplicationEvent applicationEvent;
		ClipboardEvent clipboardEvent;
		DropEvent dropEvent;
		GamepadEvent gamepadEvent;
		JoystickEvent joystickEvent;
		KeyEvent keyEvent;
		MouseEvent mouseEvent;
		RenderEvent renderEvent;
		SensorEvent sensorEvent;
		TextEvent textEvent;
		TouchEvent touchEvent;
		WindowEvent windowEvent;

		SDL_SetEventEnabled (SDL_EVENT_DROP_FILE, true);
		SDLJoystick::Init ();

		#ifdef HX_MACOS
		CFURLRef resourcesURL = CFBundleCopyResourcesDirectoryURL (CFBundleGetMainBundle ());
		char path[PATH_MAX];

		if (CFURLGetFileSystemRepresentation (resourcesURL, TRUE, (UInt8 *)path, PATH_MAX)) {

			chdir (path);

		}

		CFRelease (resourcesURL);
		#endif

	}


	SDLApplication::~SDLApplication () {



	}


	int SDLApplication::Exec () {

		Init ();

		#ifdef EMSCRIPTEN
		emscripten_cancel_main_loop ();
		emscripten_set_main_loop (UpdateFrame, 0, 0);
		emscripten_set_main_loop_timing (EM_TIMING_RAF, 1);
		#endif

		#if defined(IPHONE) || defined(EMSCRIPTEN)

		return 0;

		#else

		while (active) {

			Update ();

		}

		return Quit ();

		#endif

	}


	void SDLApplication::HandleEvent (SDL_Event* event) {

		#if defined(IPHONE) || defined(EMSCRIPTEN)

		int top = 0;
		gc_set_top_of_stack(&top,false);

		#endif

		switch (event->type) {

			case SDL_EVENT_USER:

				if (!inBackground) {

					currentUpdate = SDL_GetTicks ();
					applicationEvent.type = UPDATE;
					applicationEvent.deltaTime = currentUpdate - lastUpdate;
					lastUpdate = currentUpdate;

					nextUpdate += framePeriod;

					while (nextUpdate <= currentUpdate) {

						nextUpdate += framePeriod;

					}

					ApplicationEvent::Dispatch (&applicationEvent);
					RenderEvent::Dispatch (&renderEvent);

				}

				break;

			case SDL_EVENT_WILL_ENTER_BACKGROUND:

				inBackground = true;

				windowEvent.type = WINDOW_DEACTIVATE;
				WindowEvent::Dispatch (&windowEvent);
				break;

			case SDL_EVENT_WILL_ENTER_FOREGROUND:

				break;

			case SDL_EVENT_DID_ENTER_FOREGROUND:

				windowEvent.type = WINDOW_ACTIVATE;
				WindowEvent::Dispatch (&windowEvent);

				inBackground = false;
				break;

			case SDL_EVENT_CLIPBOARD_UPDATE:

				ProcessClipboardEvent (event);
				break;

			case SDL_EVENT_GAMEPAD_AXIS_MOTION:
			case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
			case SDL_EVENT_GAMEPAD_BUTTON_UP:
			case SDL_EVENT_GAMEPAD_ADDED:
			case SDL_EVENT_GAMEPAD_REMOVED:

				ProcessGamepadEvent (event);
				break;

			case SDL_EVENT_DROP_FILE:

				ProcessDropEvent (event);
				break;

			case SDL_EVENT_FINGER_MOTION:
			case SDL_EVENT_FINGER_DOWN:
			case SDL_EVENT_FINGER_UP:

				ProcessTouchEvent (event);
				break;

			case SDL_EVENT_JOYSTICK_AXIS_MOTION:

				if (SDLJoystick::IsAccelerometer (event->jaxis.which)) {

					ProcessSensorEvent (event);

				} else {

					ProcessJoystickEvent (event);

				}

				break;

			case SDL_EVENT_JOYSTICK_BALL_MOTION:
			case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
			case SDL_EVENT_JOYSTICK_BUTTON_UP:
			case SDL_EVENT_JOYSTICK_HAT_MOTION:
			case SDL_EVENT_JOYSTICK_ADDED:
			case SDL_EVENT_JOYSTICK_REMOVED:

				ProcessJoystickEvent (event);
				break;

			case SDL_EVENT_KEY_DOWN:
			case SDL_EVENT_KEY_UP:

				ProcessKeyEvent (event);
				break;

			case SDL_EVENT_MOUSE_MOTION:
			case SDL_EVENT_MOUSE_BUTTON_DOWN:
			case SDL_EVENT_MOUSE_BUTTON_UP:
			case SDL_EVENT_MOUSE_WHEEL:

				ProcessMouseEvent (event);
				break;

			#ifndef EMSCRIPTEN
			case SDL_EVENT_RENDER_DEVICE_RESET:

				renderEvent.type = RENDER_CONTEXT_LOST;
				RenderEvent::Dispatch (&renderEvent);

				renderEvent.type = RENDER_CONTEXT_RESTORED;
				RenderEvent::Dispatch (&renderEvent);

				renderEvent.type = RENDER;
				break;
			#endif

			case SDL_EVENT_TEXT_INPUT:
			case SDL_EVENT_TEXT_EDITING:

				ProcessTextEvent (event);
				break;

			case SDL_EVENT_WINDOW_MOUSE_ENTER:
			case SDL_EVENT_WINDOW_MOUSE_LEAVE:
			case SDL_EVENT_WINDOW_SHOWN:
			case SDL_EVENT_WINDOW_HIDDEN:
			case SDL_EVENT_WINDOW_FOCUS_GAINED:
			case SDL_EVENT_WINDOW_FOCUS_LOST:
			case SDL_EVENT_WINDOW_MAXIMIZED:
			case SDL_EVENT_WINDOW_MINIMIZED:
			case SDL_EVENT_WINDOW_MOVED:
			case SDL_EVENT_WINDOW_RESTORED:

				ProcessWindowEvent (event);
				break;

			case SDL_EVENT_WINDOW_EXPOSED:

				ProcessWindowEvent (event);

				if (!inBackground) {

					RenderEvent::Dispatch (&renderEvent);

				}

				break;

			case SDL_EVENT_WINDOW_RESIZED:

				ProcessWindowEvent (event);

				if (!inBackground) {

					RenderEvent::Dispatch (&renderEvent);

				}

				break;

			case SDL_EVENT_WINDOW_CLOSE_REQUESTED:

				ProcessWindowEvent (event);
				break;

			case SDL_EVENT_QUIT:

				// 【Meteoric 引擎关闭动画】macOS 点击窗口红点 / Cmd+Q 退出时，SDL3 除
				// WINDOW_CLOSE_REQUESTED 外还会发 SDL_EVENT_QUIT，原实现直接 active=false
				// 退出主循环 → Haxe 的 window.onClose 拦不到，关闭动画无法播放。
				// 这里把 QUIT 转成「主窗口的 WINDOW_CLOSE_REQUESTED」交给 Haxe 决策：
				//   - Haxe onClose 若取消（正在播关闭动画）→ 进程继续运行，动画完成后
				//     window.close() → __removeWindow → __checkForAllWindowsClosed → System.exit(0)；
				//   - Haxe 若直接放行（关闭动画关闭）→ 同上收尾；
				//   - 无窗口 / 事件回调未注册时保持原行为（active=false），避免挂死。
				{
					int quitWindowCount = 0;
					SDL_Window **quitWindows = SDL_GetWindows (&quitWindowCount);
					if (WindowEvent::callback && quitWindows != NULL && quitWindowCount > 0) {
						SDL_Event closeEvent;
						memset (&closeEvent, 0, sizeof (closeEvent));
						closeEvent.type = SDL_EVENT_WINDOW_CLOSE_REQUESTED;
						closeEvent.window.windowID = SDL_GetWindowID (quitWindows[0]);
						ProcessWindowEvent (&closeEvent);
					} else {
						active = false;
					}
				}
				break;

		}

	}


	void SDLApplication::Init () {

		active = true;
		lastUpdate = SDL_GetTicks ();
		nextUpdate = lastUpdate;

	}


	void SDLApplication::ProcessClipboardEvent (SDL_Event* event) {

		if (ClipboardEvent::callback) {

			clipboardEvent.type = CLIPBOARD_UPDATE;

			ClipboardEvent::Dispatch (&clipboardEvent);

		}

	}


	void SDLApplication::ProcessDropEvent (SDL_Event* event) {

		if (DropEvent::callback) {

			dropEvent.type = DROP_FILE;
			dropEvent.file = (vbyte*)event->drop.data;

			DropEvent::Dispatch (&dropEvent);
			SDL_free (dropEvent.file);

		}

	}


	void SDLApplication::ProcessGamepadEvent (SDL_Event* event) {

		if (GamepadEvent::callback) {

			switch (event->type) {

				case SDL_EVENT_GAMEPAD_AXIS_MOTION:

					if (gamepadsAxisMap[event->gaxis.which].empty ()) {

						gamepadsAxisMap[event->gaxis.which][event->gaxis.axis] = event->gaxis.value;

					} else if (gamepadsAxisMap[event->gaxis.which][event->gaxis.axis] == event->gaxis.value) {

						break;

					}

					gamepadEvent.type = GAMEPAD_AXIS_MOVE;
					gamepadEvent.axis = event->gaxis.axis;
					gamepadEvent.id = event->gaxis.which;

					if (event->gaxis.value > -analogAxisDeadZone && event->gaxis.value < analogAxisDeadZone) {

						if (gamepadsAxisMap[event->gaxis.which][event->gaxis.axis] != 0) {

							gamepadsAxisMap[event->gaxis.which][event->gaxis.axis] = 0;
							gamepadEvent.axisValue = 0;
							GamepadEvent::Dispatch (&gamepadEvent);

						}

						break;

					}

					gamepadsAxisMap[event->gaxis.which][event->gaxis.axis] = event->gaxis.value;
					gamepadEvent.axisValue = event->gaxis.value / (event->gaxis.value > 0 ? 32767.0 : 32768.0);

					GamepadEvent::Dispatch (&gamepadEvent);
					break;

				case SDL_EVENT_GAMEPAD_BUTTON_DOWN:

					gamepadEvent.type = GAMEPAD_BUTTON_DOWN;
					gamepadEvent.button = event->gbutton.button;
					gamepadEvent.id = event->gbutton.which;

					GamepadEvent::Dispatch (&gamepadEvent);
					break;

				case SDL_EVENT_GAMEPAD_BUTTON_UP:

					gamepadEvent.type = GAMEPAD_BUTTON_UP;
					gamepadEvent.button = event->gbutton.button;
					gamepadEvent.id = event->gbutton.which;

					GamepadEvent::Dispatch (&gamepadEvent);
					break;

				case SDL_EVENT_GAMEPAD_ADDED:

					if (SDLGamepad::Connect (event->gdevice.which)) {

						gamepadEvent.type = GAMEPAD_CONNECT;
						gamepadEvent.id = SDLGamepad::GetInstanceID (event->gdevice.which);

						GamepadEvent::Dispatch (&gamepadEvent);

					}

					break;

				case SDL_EVENT_GAMEPAD_REMOVED: {

					gamepadEvent.type = GAMEPAD_DISCONNECT;
					gamepadEvent.id = event->gdevice.which;

					GamepadEvent::Dispatch (&gamepadEvent);
					SDLGamepad::Disconnect (event->gdevice.which);
					break;

				}

			}

		}

	}


	void SDLApplication::ProcessJoystickEvent (SDL_Event* event) {

		if (JoystickEvent::callback) {

			switch (event->type) {

				case SDL_EVENT_JOYSTICK_AXIS_MOTION:

					if (!SDLJoystick::IsAccelerometer (event->jaxis.which)) {

						joystickEvent.type = JOYSTICK_AXIS_MOVE;
						joystickEvent.index = event->jaxis.axis;
						joystickEvent.x = event->jaxis.value / (event->jaxis.value > 0 ? 32767.0 : 32768.0);
						joystickEvent.id = event->jaxis.which;

						JoystickEvent::Dispatch (&joystickEvent);

					}
					break;


				case SDL_EVENT_JOYSTICK_BUTTON_DOWN:

					if (!SDLJoystick::IsAccelerometer (event->jbutton.which)) {

						joystickEvent.type = JOYSTICK_BUTTON_DOWN;
						joystickEvent.index = event->jbutton.button;
						joystickEvent.id = event->jbutton.which;

						JoystickEvent::Dispatch (&joystickEvent);

					}
					break;

				case SDL_EVENT_JOYSTICK_BUTTON_UP:

					if (!SDLJoystick::IsAccelerometer (event->jbutton.which)) {

						joystickEvent.type = JOYSTICK_BUTTON_UP;
						joystickEvent.index = event->jbutton.button;
						joystickEvent.id = event->jbutton.which;

						JoystickEvent::Dispatch (&joystickEvent);

					}
					break;

				case SDL_EVENT_JOYSTICK_HAT_MOTION:

					if (!SDLJoystick::IsAccelerometer (event->jhat.which)) {

						joystickEvent.type = JOYSTICK_HAT_MOVE;
						joystickEvent.index = event->jhat.hat;
						joystickEvent.eventValue = event->jhat.value;
						joystickEvent.id = event->jhat.which;

						JoystickEvent::Dispatch (&joystickEvent);

					}
					break;

				case SDL_EVENT_JOYSTICK_ADDED:

					if (SDLJoystick::Connect (event->jdevice.which)) {

						joystickEvent.type = JOYSTICK_CONNECT;
						joystickEvent.id = SDLJoystick::GetInstanceID (event->jdevice.which);

						JoystickEvent::Dispatch (&joystickEvent);

					}
					break;

				case SDL_EVENT_JOYSTICK_REMOVED:

					if (!SDLJoystick::IsAccelerometer (event->jdevice.which)) {

						joystickEvent.type = JOYSTICK_DISCONNECT;
						joystickEvent.id = event->jdevice.which;

						JoystickEvent::Dispatch (&joystickEvent);
						SDLJoystick::Disconnect (event->jdevice.which);

					}
					break;

			}

		}

	}


	void SDLApplication::ProcessKeyEvent (SDL_Event* event) {

		if (KeyEvent::callback) {

			switch (event->type) {

				case SDL_EVENT_KEY_DOWN: keyEvent.type = KEY_DOWN; break;
				case SDL_EVENT_KEY_UP: keyEvent.type = KEY_UP; break;

			}

			keyEvent.keyCode = event->key.key;
			keyEvent.modifier = event->key.mod;
			keyEvent.windowID = event->key.windowID;

			if (keyEvent.type == KEY_DOWN) {

				if (keyEvent.keyCode == SDLK_CAPSLOCK) keyEvent.modifier |= SDL_KMOD_CAPS;
				if (keyEvent.keyCode == SDLK_LALT) keyEvent.modifier |= SDL_KMOD_LALT;
				if (keyEvent.keyCode == SDLK_LCTRL) keyEvent.modifier |= SDL_KMOD_LCTRL;
				if (keyEvent.keyCode == SDLK_LGUI) keyEvent.modifier |= SDL_KMOD_LGUI;
				if (keyEvent.keyCode == SDLK_LSHIFT) keyEvent.modifier |= SDL_KMOD_LSHIFT;
				if (keyEvent.keyCode == SDLK_MODE) keyEvent.modifier |= SDL_KMOD_MODE;
				if (keyEvent.keyCode == SDLK_NUMLOCKCLEAR) keyEvent.modifier |= SDL_KMOD_NUM;
				if (keyEvent.keyCode == SDLK_RALT) keyEvent.modifier |= SDL_KMOD_RALT;
				if (keyEvent.keyCode == SDLK_RCTRL) keyEvent.modifier |= SDL_KMOD_RCTRL;
				if (keyEvent.keyCode == SDLK_RGUI) keyEvent.modifier |= SDL_KMOD_RGUI;
				if (keyEvent.keyCode == SDLK_RSHIFT) keyEvent.modifier |= SDL_KMOD_RSHIFT;

			}

			KeyEvent::Dispatch (&keyEvent);

		}

	}


	void SDLApplication::ProcessMouseEvent (SDL_Event* event) {

		if (MouseEvent::callback) {

			#ifdef HX_WINDOWS
			// 【Meteoric 修复】Windows 高清：DPI 感知进程下 SDL 上报物理像素坐标，
			// OpenFL 之后会再乘 window.scale；这里先除以缩放得到逻辑坐标
			// （调用方传入/高清关闭时 scale=1 → 恒等，行为不变）。
			double mouseScale = 1.0;
			SDL_Window* sdlWindow = SDL_GetWindowFromID (event->button.windowID);
			if (sdlWindow != NULL) {

				double scale = SDLWindow::MeteoricScale (sdlWindow);
				if (scale > 1.0) mouseScale = scale;

			}
			#endif

			switch (event->type) {

				case SDL_EVENT_MOUSE_MOTION:

					mouseEvent.type = MOUSE_MOVE;
					#ifdef HX_WINDOWS
					mouseEvent.x = (int)(event->motion.x / mouseScale + 0.5);
					mouseEvent.y = (int)(event->motion.y / mouseScale + 0.5);
					#else
					mouseEvent.x = event->motion.x;
					mouseEvent.y = event->motion.y;
					#endif
					mouseEvent.movementX = event->motion.xrel;
					mouseEvent.movementY = event->motion.yrel;
					break;

				case SDL_EVENT_MOUSE_BUTTON_DOWN:

					SDL_CaptureMouse (true);

					mouseEvent.type = MOUSE_DOWN;
					mouseEvent.button = event->button.button - 1;
					#ifdef HX_WINDOWS
					mouseEvent.x = (int)(event->button.x / mouseScale + 0.5);
					mouseEvent.y = (int)(event->button.y / mouseScale + 0.5);
					#else
					mouseEvent.x = event->button.x;
					mouseEvent.y = event->button.y;
					#endif
					mouseEvent.clickCount = event->button.clicks;
					break;

				case SDL_EVENT_MOUSE_BUTTON_UP:

					SDL_CaptureMouse (false);

					mouseEvent.type = MOUSE_UP;
					mouseEvent.button = event->button.button - 1;
					#ifdef HX_WINDOWS
					mouseEvent.x = (int)(event->button.x / mouseScale + 0.5);
					mouseEvent.y = (int)(event->button.y / mouseScale + 0.5);
					#else
					mouseEvent.x = event->button.x;
					mouseEvent.y = event->button.y;
					#endif
					mouseEvent.clickCount = event->button.clicks;
					break;

				case SDL_EVENT_MOUSE_WHEEL:

					mouseEvent.type = MOUSE_WHEEL;

					if (event->wheel.direction == SDL_MOUSEWHEEL_FLIPPED) {

						mouseEvent.x = -event->wheel.x;
						mouseEvent.y = -event->wheel.y;

					} else {

						mouseEvent.x = event->wheel.x;
						mouseEvent.y = event->wheel.y;

					}
					break;

			}

			mouseEvent.windowID = event->button.windowID;
			MouseEvent::Dispatch (&mouseEvent);

		}

	}


	void SDLApplication::ProcessSensorEvent (SDL_Event* event) {

		if (SensorEvent::callback) {

			double value = event->jaxis.value / 32767.0f;

			switch (event->jaxis.axis) {

				case 0: sensorEvent.x = value; break;
				case 1: sensorEvent.y = value; break;
				case 2: sensorEvent.z = value; break;
				default: break;

			}

			SensorEvent::Dispatch (&sensorEvent);

		}

	}


	void SDLApplication::ProcessTextEvent (SDL_Event* event) {

		if (TextEvent::callback) {

			switch (event->type) {

				case SDL_EVENT_TEXT_INPUT:

					textEvent.type = TEXT_INPUT;
					break;

				case SDL_EVENT_TEXT_EDITING:

					textEvent.type = TEXT_EDIT;
					textEvent.start = event->edit.start;
					textEvent.length = event->edit.length;
					break;

			}

			if (textEvent.text) {

				free (textEvent.text);

			}

			textEvent.text = (vbyte*)malloc (strlen (event->text.text) + 1);
			strcpy ((char*)textEvent.text, event->text.text);

			textEvent.windowID = event->text.windowID;
			TextEvent::Dispatch (&textEvent);

		}

	}


	void SDLApplication::ProcessTouchEvent (SDL_Event* event) {

		if (TouchEvent::callback) {

			switch (event->type) {

				case SDL_EVENT_FINGER_MOTION:

					touchEvent.type = TOUCH_MOVE;
					break;

				case SDL_EVENT_FINGER_DOWN:

					touchEvent.type = TOUCH_START;
					break;

				case SDL_EVENT_FINGER_UP:

					touchEvent.type = TOUCH_END;
					break;

			}

			touchEvent.x = event->tfinger.x;
			touchEvent.y = event->tfinger.y;
			touchEvent.id = event->tfinger.fingerID;
			touchEvent.dx = event->tfinger.dx;
			touchEvent.dy = event->tfinger.dy;
			touchEvent.pressure = event->tfinger.pressure;
			touchEvent.device = event->tfinger.touchID;

			TouchEvent::Dispatch (&touchEvent);

		}

	}


	void SDLApplication::ProcessWindowEvent (SDL_Event* event) {

		if (WindowEvent::callback) {

			switch (event->type) {

				case SDL_EVENT_WINDOW_SHOWN: windowEvent.type = WINDOW_SHOW; break;
				case SDL_EVENT_WINDOW_CLOSE_REQUESTED: windowEvent.type = WINDOW_CLOSE; break;
				case SDL_EVENT_WINDOW_HIDDEN: windowEvent.type = WINDOW_HIDE; break;
				case SDL_EVENT_WINDOW_MOUSE_ENTER: windowEvent.type = WINDOW_ENTER; break;
				case SDL_EVENT_WINDOW_FOCUS_GAINED: windowEvent.type = WINDOW_FOCUS_IN; break;
				case SDL_EVENT_WINDOW_FOCUS_LOST: windowEvent.type = WINDOW_FOCUS_OUT; break;
				case SDL_EVENT_WINDOW_MOUSE_LEAVE: windowEvent.type = WINDOW_LEAVE; break;
				case SDL_EVENT_WINDOW_MAXIMIZED: windowEvent.type = WINDOW_MAXIMIZE; break;
				case SDL_EVENT_WINDOW_MINIMIZED: windowEvent.type = WINDOW_MINIMIZE; break;
				case SDL_EVENT_WINDOW_EXPOSED: windowEvent.type = WINDOW_EXPOSE; break;

				case SDL_EVENT_WINDOW_MOVED:

					windowEvent.type = WINDOW_MOVE;
					windowEvent.x = event->window.data1;
					windowEvent.y = event->window.data2;
					break;

				case SDL_EVENT_WINDOW_RESIZED:

					windowEvent.type = WINDOW_RESIZE;
					windowEvent.width = event->window.data1;
					windowEvent.height = event->window.data2;
					break;

				case SDL_EVENT_WINDOW_RESTORED: windowEvent.type = WINDOW_RESTORE; break;

			}

			windowEvent.windowID = event->window.windowID;
			WindowEvent::Dispatch (&windowEvent);

		}

	}


	int SDLApplication::Quit () {

		applicationEvent.type = EXIT;
		ApplicationEvent::Dispatch (&applicationEvent);

		SDL_Quit ();

		return 0;

	}


	void SDLApplication::RegisterWindow (SDLWindow *window) {

		#ifdef IPHONE
		// SDL3 移除了 SDL_iPhoneSetAnimationCallback（iOS 专用，暂不处理）
		// SDL_iPhoneSetAnimationCallback (window->sdlWindow, 1, UpdateFrame, NULL);
		#endif

	}


	void SDLApplication::SetFrameRate (double frameRate) {

		if (frameRate > 0) {

			framePeriod = 1000.0 / frameRate;

		} else {

			framePeriod = 1000.0;

		}

	}


	static SDL_TimerID timerID = 0;
	bool timerActive = false;
	bool firstTime = true;

	Uint32 OnTimer (void *userdata, SDL_TimerID timerID, Uint32 interval) {

		SDL_Event event;
		SDL_UserEvent userevent;
		userevent.type = SDL_EVENT_USER;
		userevent.code = 0;
		userevent.data1 = NULL;
		userevent.data2 = NULL;
		event.type = SDL_EVENT_USER;
		event.user = userevent;

		timerActive = false;
		timerID = 0;

		SDL_PushEvent (&event);

		return 0;

	}


	bool SDLApplication::Update () {

		SDL_Event event;
		event.type = -1;

		#if (!defined (IPHONE) && !defined (EMSCRIPTEN))

		while (SDL_PollEvent (&event)) {

			if (event.type != SDL_EVENT_USER) {

				HandleEvent (&event);

			}

			event.type = -1;

			if (!active)
				return active;

		}

		currentUpdate = HiResMs ();

		if (!active)
			return active;

		if (currentUpdate >= nextUpdate) {

			// Due frame: advance by wall clock; resync after long stalls to avoid catch-up bursts.
			int catchup = 0;

			do {

				nextUpdate += framePeriod;
				catchup++;

			} while (nextUpdate <= currentUpdate && catchup < 4);

			if (catchup >= 4) {
				nextUpdate = currentUpdate + framePeriod;
			}

			applicationEvent.type = UPDATE;
			applicationEvent.deltaTime = currentUpdate - lastUpdate;
			lastUpdate = currentUpdate;

			ApplicationEvent::Dispatch (&applicationEvent);
			RenderEvent::Dispatch (&renderEvent);

		} else if (!inBackground && nextUpdate > currentUpdate) {

			double remainMs = nextUpdate - currentUpdate;

			if (remainMs > 3.0) {

				// Long wait: timed event wait keeps input responsive.
				int timeout = (int) (remainMs - 2.0);

				if (timeout > 0 && WaitEventTimeout (&event, timeout)) {

					if (event.type != SDL_EVENT_USER) {
						HandleEvent (&event);
					}

				}

			} else {

				// Final <=3ms alignment: NS sleep plus a short spin to remove the 1ms floor.
				while ((remainMs = nextUpdate - HiResMs ()) > 0) {

					if (remainMs > 0.55) {
						SDL_DelayNS ((Uint64) ((remainMs - 0.30) * 1000000.0));
					} else {
						while (nextUpdate - HiResMs () > 0) { }
						break;
					}

				}

			}

		} else {

			// Background: block until a real event rather than burning CPU.
			if (WaitEvent (&event) && event.type != SDL_EVENT_USER) {
				HandleEvent (&event);
			}

		}

		return active;

		#else

		// Original IPHONE / EMSCRIPTEN path.
		if (active && (firstTime || WaitEvent (&event))) {

			firstTime = false;

			HandleEvent (&event);
			event.type = -1;
			if (!active)
				return active;

			while (SDL_PollEvent (&event)) {

				HandleEvent (&event);
				event.type = -1;
				if (!active)
					return active;

			}

			currentUpdate = SDL_GetTicks ();

			if (currentUpdate >= nextUpdate) {

				if (timerActive) SDL_RemoveTimer (timerID);
				OnTimer (NULL, 0, 0);

			} else if (!timerActive) {

				timerActive = true;
				timerID = SDL_AddTimer ((Uint32) (nextUpdate - currentUpdate), OnTimer, 0);

			}

		}

		return active;

		#endif

	}


		// Wait up to timeout ms for an event; returns 1 on event, 0 on timeout.
	int SDLApplication::WaitEventTimeout (SDL_Event *event, int timeout) {

		if (timeout <= 0) return 0;

		#if defined(HX_MACOS) || defined(ANDROID)

		System::GCEnterBlocking ();
		int result = SDL_WaitEventTimeout (event, timeout);
		System::GCExitBlocking ();
		return result;

		#else

		bool isBlocking = false;
		Uint32 deadline = SDL_GetTicks () + (Uint32)timeout;

		for(;;) {

			SDL_PumpEvents ();

			switch (SDL_PeepEvents (event, 1, SDL_GETEVENT, SDL_EVENT_FIRST, SDL_EVENT_LAST)) {

				case -1:

					if (isBlocking) System::GCExitBlocking ();
					return 0;

				case 1:

					if (isBlocking) System::GCExitBlocking ();
					return 1;

				default:

					if (SDL_GetTicks () >= deadline) {

						if (isBlocking) System::GCExitBlocking ();
						return 0;

					}

					if (!isBlocking) System::GCEnterBlocking ();
					isBlocking = true;
					SDL_Delay (1);
					break;

			}

		}

		#endif

	}


	void SDLApplication::UpdateFrame () {

		#ifdef EMSCRIPTEN
		System::GCTryExitBlocking ();
		#endif

		currentApplication->Update ();

		#ifdef EMSCRIPTEN
		System::GCTryEnterBlocking ();
		#endif

	}


	void SDLApplication::UpdateFrame (void*) {

		UpdateFrame ();

	}


	int SDLApplication::WaitEvent (SDL_Event *event) {

		#if defined(HX_MACOS) || defined(ANDROID)

		System::GCEnterBlocking ();
		int result = SDL_WaitEvent (event);
		System::GCExitBlocking ();
		return result;

		#else

		bool isBlocking = false;

		for(;;) {

			SDL_PumpEvents ();

			switch (SDL_PeepEvents (event, 1, SDL_GETEVENT, SDL_EVENT_FIRST, SDL_EVENT_LAST)) {

				case -1:

					if (isBlocking) System::GCExitBlocking ();
					return 0;

				case 1:

					if (isBlocking) System::GCExitBlocking ();
					return 1;

				default:

					if (!isBlocking) System::GCEnterBlocking ();
					isBlocking = true;
					SDL_Delay (1);
					break;

			}

		}

		#endif

	}


	Application* CreateApplication () {

		return new SDLApplication ();

	}


}


#ifdef ANDROID
int SDL_main (int argc, char *argv[]) { return 0; }
#endif
