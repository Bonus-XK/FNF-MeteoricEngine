-- class 系统可运行示例（界面脚本）
-- 使用方法：把这个文件重命名为 menus/main_menu.lua 后进主菜单即可看到效果
-- 游玩脚本（data/xxx.lua）里用法完全相同

function onCreate()
	-- ===== 定义类 =====
	Class.new('Enemy')

	function Enemy:new(x, y)
		self.x = x or 0
		self.y = y or 0
		self.hp = 10
	end

	function Enemy:update()
		self.x = self.x + 1
	end

	-- ===== 继承 =====
	Class.new('Boss', Enemy)

	function Boss:new(x, y, hp)
		Enemy.new(self, x, y) -- 调用父类构造函数
		self.hp = hp or 999
	end

	function Boss:update()
		Enemy.update(self) -- 调用父类方法
		self.hp = self.hp - 1
	end

	-- ===== 创建实例并测试 =====
	local e = Enemy.new(5, 6)
	local b = Boss(1, 2, 100)

	e:update()
	b:update()

	local ok = true
	ok = ok and e.x == 6 and e.hp == 10
	ok = ok and b.x == 2 and b.hp == 99
	ok = ok and Enemy.isInstanceOf(e)
	ok = ok and Enemy.isInstanceOf(b)
	ok = ok and Class.isSubclassOf(Boss, Enemy)
	ok = ok and e.__name == 'Enemy' and b.__class == Boss

	if ok then
		addText('classDemo', 'class 系统测试：全部通过', 88, 600, 20, 0xFF7CFC00, 'vcr.ttf')
	else
		addText('classDemo', 'class 系统测试：失败！', 88, 600, 20, 0xFFFF5555, 'vcr.ttf')
	end
end
