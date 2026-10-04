# i18n 自检

`check_i18n.py` 是多语言系统的**单一自检入口**（只读，退出码 0 = PASS）。
在提交前 / 改完文案后跑一次：

```bash
python3 tools/i18n/check_i18n.py            # 自检
python3 tools/i18n/check_i18n.py -v         # 附带剩余项明细
python3 tools/i18n/check_i18n.py --update-baseline   # 认可当前剩余项并写回基线
```

## 检查项

| # | 项 | 抓什么 |
|---|---|---|
| 1 | 语言包完整性 | zh/en key 集合不一致；空值（`tOr` 只判 `None`，空串会让界面显示空白） |
| 2 | 字面量 key | 源码里 `Lang.t/tOr/tr/trOr('k')` 的 `k` 不在语言包里 |
| 3a | Option 派生 key | `new Option(...)` 派生的 `option.` / `optionDesc.` / `optionValue.<var>.<i>` |
| 3b | luagraph 派生 key | 积木表派生的 `lg.cat.` / `lg.block.` / `lg.blockDesc.` / `lg.param.` |
| 3c | 主题名派生 key | `theme.<name>` |
| 4 | `Lang.t` 安全性 | `Lang.t` 的 key 缺失 —— 缺 key 时它**返回 key 本身**，界面会显示 `xxx.yyy` |
| 5 | 静态缓存 | `static var/final` 的初始值里含 `Lang.t*` —— 只求值一次，运行时切语言不刷新 |
| 6 | 括号对称 | 拆成前后缀两个 key 时只拆了一半（英文下出现 `(exit 1）`） |
| 7 | CJK 覆盖率 | 相对 `intentional-skip.tsv` 基线新增未翻译项；且每条剩余项都必须有书面理由 |

## 为什么不能用正则找 Haxe 字面量

`hxscan.py` 是字符串感知扫描器（逐字符走，跟踪 in_string / in_comment / quote / escaped / 正则字面量）。
用正则会有四类翻车，其中三类实测踩过：

1. Haxe 允许字符串内含**真实换行** → 正则拦腰截断 → 替换后语法错误
2. 串内 `\"` 转义被当成定界符 → 替换落在转义中间 → 写出非法的 `\L`
3. `~/[.,'"%?!]/` 这类**正则字面量**里的引号被当成字符串定界符 → 后面几百行误判成一个「跨行字符串」
4. 注释里的字面量被误当代码

## `intentional-skip.tsv`

有意不翻译的剩余中文字面量基线，列：`路径 / 字面量 / 处数 / 原因`。
字面量里的 `\t` `\n` `\r` `\\` 已转义（多行字面量直接写 TSV 会错列）。

**新增未翻译项会让 [7] 失败** —— 确认是有意保留后跑 `--update-baseline` 认可。
`原因` 列由 `SKIP_REASONS`（按文件）与内容特征判定（分隔符片段 / 诊断日志 / 存档值比较）生成；
出现 `?未知原因` 会失败，提醒补理由。
