// Meteoric CNE 编程层冒烟脚本（TitleState 状态作用域）
// 验证：状态脚本被加载、能拿到 state 变量、收到 create/update/destroy，
// 并在第 120 帧调用一次 CNE.reloadCurrentStateScripts()（原地热重载）。

import sys.io.File;
import sys.FileSystem;

var updates = 0;

function create() {
	File.saveContent('cne_smoke_state_create.txt', Date.now().getTime() + '|' + (state == null ? 'null' : Type.getClassName(Type.getClass(state))));
}

function update(elapsed) {
	updates++;
	if (updates == 1) File.saveContent('cne_smoke_state_update.txt', 'ok');
	if (updates == 120 && !FileSystem.exists('cne_smoke_reloaded.flag')) {
		File.saveContent('cne_smoke_reload_trigger.txt', 'ok');
		File.saveContent('cne_smoke_reloaded.flag', 'ok');
		CNE.reloadCurrentStateScripts();
	}
}

function destroy() {
	File.saveContent('cne_smoke_state_destroy.txt', Date.now().getTime() + '');
}
