#include <system/Mutex.h>
#include <SDL3/SDL.h>


namespace lime {


	Mutex::Mutex () {

		mutex = SDL_CreateMutex ();

	}


	Mutex::~Mutex () {

		if (mutex) {

			SDL_DestroyMutex ((SDL_Mutex *)mutex);

		}

	}


	bool Mutex::Lock () const {

		if (mutex) {

			// SDL3: SDL_LockMutex 返回 void
			SDL_LockMutex ((SDL_Mutex *)mutex);
			return true;

		}

		return false;

	}


	bool Mutex::TryLock () const {

		if (mutex) {

			// SDL3: SDL_TryLockMutex 返回 bool
			return SDL_TryLockMutex ((SDL_Mutex *)mutex);

		}

		return false;

	}


	bool Mutex::Unlock () const {

		if (mutex) {

			// SDL3: SDL_UnlockMutex 返回 void
			SDL_UnlockMutex ((SDL_Mutex *)mutex);
			return true;

		}

		return false;

	}


}