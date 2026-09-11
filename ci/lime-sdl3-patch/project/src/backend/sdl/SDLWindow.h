#ifndef LIME_SDL_WINDOW_H
#define LIME_SDL_WINDOW_H


#include <SDL3/SDL.h>
#include <graphics/ImageBuffer.h>
#include <ui/Cursor.h>
#include <ui/Window.h>


namespace lime {


	class SDLWindow : public Window {

		public:

			SDLWindow (Application* application, int width, int height, int flags, const char* title);
			~SDLWindow ();

			virtual void Alert (const char* message, const char* title);
			virtual void Close ();
			virtual void ContextFlip ();
			virtual void* ContextLock (bool useCFFIValue);
			virtual void ContextMakeCurrent ();
			virtual void ContextUnlock ();
			virtual void Focus ();
			virtual void* GetContext ();
			virtual const char* GetContextType ();
			// virtual Cursor GetCursor ();
			virtual int GetDisplay ();
			virtual void GetDisplayMode (DisplayMode* displayMode);
			virtual int GetHeight ();
			virtual uint32_t GetID ();
			virtual bool GetMouseLock ();
			virtual float GetOpacity ();
			virtual double GetScale ();
			virtual bool GetTextInputEnabled ();
			virtual int GetWidth ();
			virtual int GetX ();
			virtual int GetY ();
			virtual void Move (int x, int y);
			virtual void ReadPixels (ImageBuffer *buffer, Rectangle *rect);
			virtual void Resize (int width, int height);
			virtual void SetMinimumSize (int width, int height);
			virtual void SetMaximumSize (int width, int height);
			virtual bool SetBorderless (bool borderless);
			virtual void SetCursor (Cursor cursor);
			virtual void SetDisplayMode (DisplayMode* displayMode);
			virtual bool SetFullscreen (bool fullscreen);
			virtual void SetIcon (ImageBuffer *imageBuffer);
			virtual bool SetMaximized (bool maximized);
			virtual bool SetMinimized (bool minimized);
			virtual void SetMouseLock (bool mouseLock);
			virtual void SetOpacity (float opacity);
			virtual bool SetResizable (bool resizable);
			virtual void SetTextInputEnabled (bool enabled);
			virtual void SetTextInputRect (Rectangle *rect);
			virtual const char* SetTitle (const char* title);
			virtual bool SetVisible (bool visible);
			virtual void WarpMouse (int x, int y);
			// 【Meteoric 高清渲染】Windows 端修复辅助：
			// MeteoricHighDpiEnabled() 读取可执行文件旁 meteoric_dpi_mode.txt（'0'=1x 高性能，其余=高清），
			// MeteoricScale() 返回窗口内容缩放（Windows=显示器 DPI/96；macOS Retina=2.0；高清关闭/未知=1.0）
			static bool MeteoricHighDpiEnabled ();
			static double MeteoricScale (SDL_Window* window);
			// MeteoricScaledWindowFits()：在 SDL_Init 之前（此时还没有窗口，只能用主显示器）
			// 判断「逻辑尺寸 × 显示器缩放」的窗口是否装得进可用桌面区域。装不下就不该开 DPI 感知，
			// 否则窗口会溢出屏幕被裁切（2026-09-11 虚拟屏实测：画面"锁死在一个区域"）。
			static bool MeteoricScaledWindowFits (int logicalWidth, int logicalHeight);
			SDL_Renderer* sdlRenderer;
			SDL_Texture* sdlTexture;
			SDL_Window* sdlWindow;

		private:

			SDL_GLContext context;
			int contextHeight;
			int contextWidth;

	};


}


#endif
