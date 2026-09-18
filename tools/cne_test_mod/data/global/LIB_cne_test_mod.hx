// Meteoric CNE 编程层冒烟脚本（全局作用域）
// 验证：全局脚本能被加载，并收到 create/beatHit 生命周期。
// 用落盘代替 trace：hxcpp 的 trace 可能被日志系统吞掉，文件证据更可靠。

import sys.io.File;

function create() {
	File.saveContent('cne_smoke_global_create.txt', 'ok');
}

function update(elapsed) {
	// 故意不打日志：避免每帧刷屏
}

function beatHit(beat) {
	if (beat % 8 == 0) File.saveContent('cne_smoke_global_beat.txt', '' + beat);
}

function stepHit(step) {
}

function destroy() {
	File.saveContent('cne_smoke_global_destroy.txt', 'ok');
}
