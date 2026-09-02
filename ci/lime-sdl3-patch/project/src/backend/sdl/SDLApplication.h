#ifndef LIME_SDL_APPLICATION_H
#define LIME_SDL_APPLICATION_H


#include <SDL3/SDL.h>
#include <app/Application.h>
#include <app/ApplicationEvent.h>
#include <graphics/RenderEvent.h>
#include <system/ClipboardEvent.h>
#include <system/SensorEvent.h>
#include <ui/DropEvent.h>
#include <ui/GamepadEvent.h>
#include <ui/JoystickEvent.h>
#include <ui/KeyEvent.h>
#include <ui/MouseEvent.h>
#include <ui/TextEvent.h>
#include <ui/TouchEvent.h>
#include <ui/WindowEvent.h>
#include "SDLWindow.h"


namespace lime {


	class SDLApplication : public Application {

		public:

			SDLApplication ();
			~SDLApplication ();

			virtual int Exec ();
			virtual void Init ();
			virtual int Quit ();
			virtual void SetFrameRate (double frameRate);
			virtual bool Update ();

			void RegisterWindow (SDLWindow *window);

		private:

			void HandleEvent (SDL_Event* event);
			void ProcessClipboardEvent (SDL_Event* event);
			void ProcessDropEvent (SDL_Event* event);
			void ProcessGamepadEvent (SDL_Event* event);
			void ProcessJoystickEvent (SDL_Event* event);
			void ProcessKeyEvent (SDL_Event* event);
			void ProcessMouseEvent (SDL_Event* event);
			void ProcessSensorEvent (SDL_Event* event);
			void ProcessTextEvent (SDL_Event* event);
			void ProcessTouchEvent (SDL_Event* event);
			void ProcessWindowEvent (SDL_Event* event);
			int WaitEvent (SDL_Event* event);
			int WaitEventTimeout (SDL_Event* event, int timeout);

			static void UpdateFrame ();
			static void UpdateFrame (void*);

			static SDLApplication* currentApplication;

			bool active;
			ApplicationEvent applicationEvent;
			ClipboardEvent clipboardEvent;
			double currentUpdate; // Performance-counter time in ms (HiResMs).
			double framePeriod;
			// 【Meteoric 亚毫秒更新】nextUpdate 必须为浮点：原 Uint32 在 framePeriod < 1.0
			// （frameRate > 1000）时每次 += framePeriod 都被截断成 +0 → catch-up 循环
			// while (nextUpdate <= currentUpdate) 永不前进 → 主线程 100% 死循环（加载卡死）。
			// 亚毫秒目标需要亚毫秒精度的时间账本。
			double nextUpdate;
			DropEvent dropEvent;
			GamepadEvent gamepadEvent;
			JoystickEvent joystickEvent;
			KeyEvent keyEvent;
			double lastUpdate; // Performance-counter time in ms (HiResMs).
			MouseEvent mouseEvent;
			RenderEvent renderEvent;
			SensorEvent sensorEvent;
			TextEvent textEvent;
			TouchEvent touchEvent;
			WindowEvent windowEvent;

	};


}


#endif