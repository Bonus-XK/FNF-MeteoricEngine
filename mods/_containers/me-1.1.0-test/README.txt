把 Psych Engine 0.6.3 的发行包解压到本目录，使结构变成：

  mods/_containers/示例-psych-0.6.3/
    container.json          ← 已就绪（按需改 displayName / app）
    Psych Engine.app/       ← 目标引擎（整个 .app 丢进来）
    resources/              ← 可选：要塞给 0.6.3 的 mod（放 resources/mods/<你的mod>/）

然后回游戏：设置 → 容器 → 重新扫描 → 切换到此容器。
详见仓库根目录 CONTAINERS.md。
