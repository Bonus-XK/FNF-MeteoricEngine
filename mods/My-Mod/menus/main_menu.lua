-- 主菜单自定义示例：修改标题文字、新增一条说明文字
-- 放置于 mods/<你的mod>/menus/main_menu.lua

function onCreate()
	-- 修改界面上已有的文字（对象名 = 界面代码里的字段名）
	setText('titleText', '自定义主菜单')
	setText('subtitleText', '选项说明（已修改）')
	setText('itemNameText', 'Meteoric 自定义主菜单')
	setText('descText', '这个文字来自 mod 的 menus/main_menu.lua 脚本！')

	-- 新增一条文字（名字自定义，之后可用 setText/removeObject 操作）
	addText('modCredits', '由 Lua 界面脚本注入', 88, 640, 18, 0xFF9CE8FF, 'vcr.ttf')
end

function onUpdate(elapsed)
	-- 每帧回调，可在这里做动态效果
end

function onChangeSelection(selected, itemId)
	-- 选中项变化时触发（selected = 序号，itemId = 菜单项 ID）
end

function onConfirm(itemId)
	-- 玩家按下确认时触发
end

function onDestroy()
	-- 界面销毁前触发（离开主菜单时）
end
