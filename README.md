# Codex Primer

在 Debian / Ubuntu 服务器上，按固定时间自动发送轻量 Codex 请求。完成后退出，无常驻请求进程。

<br>

## 第一步：准备服务器

需要 **x86_64 架构、使用 systemd 的 Debian / Ubuntu**，并具有 root 或 sudo 权限。
通过 SSH 登录服务器后，先安装依赖：

```bash
sudo apt-get update
sudo apt-get install -y git ca-certificates curl tar coreutils util-linux passwd tzdata
```

运行时使用官方原生 Codex CLI，无需额外安装 Node.js、Python 或 Docker。
需要一个可登录 Codex 的 ChatGPT 订阅账号；请求会消耗真实订阅额度。

<br>

## 第二步：下载完整项目

```bash
git clone https://github.com/Monkeypox966/codex-primer.git
cd codex-primer
```

没有 Git 时，也可以下载并解压完整源码包：

```bash
curl -fL https://github.com/Monkeypox966/codex-primer/archive/refs/heads/main.tar.gz -o codex-primer.tar.gz
tar -xzf codex-primer.tar.gz
cd codex-primer-main
```

安装器依赖同目录的其他文件，请保留完整项目目录。

<br>

## 第三步：安装并按提示登录

在项目目录执行：

```bash
sudo bash install.sh
```

安装器会下载并校验 Codex CLI、建立专用账号，并启动设备码登录。
在自己电脑的浏览器打开终端显示的官方地址，按提示输入设备码、登录 ChatGPT 账号并完成授权。

首次安装成功后会启用定时器。默认按**北京时间 05:00、10:01、15:02、20:03**，
使用 **GPT-6 Luna / low** 发送一次只要求回复 `OK` 的请求。

如果设备码登录不可用，按下方“登录遇到问题”中的浏览器登录步骤操作。

<br>

## 第四步：确认安装结果

```bash
sudo codex-primer status
```

检查输出中的登录状态和下次触发时间。首次实际运行后，还会显示最近一次请求的结果。
需要马上验证一次真实请求时，执行：

```bash
sudo codex-primer run
sudo codex-primer status
```

`run` 会消耗真实额度；查看 `status` 不发送模型请求。
本项目安排普通订阅请求，时间安排不保证开启新的用量窗口，也不能增加或重置额度。

<br>

## 日常操作

| 想做什么 | 命令 |
| --- | --- |
| 查看登录、最近结果和下次触发 | `sudo codex-primer status` |
| 查看最近 30 条日志 | `sudo codex-primer logs` |
| 查看最近 100 条日志 | `sudo codex-primer logs 100` |
| 立即发送一次请求 | `sudo codex-primer run` |
| 暂停后续定时请求 | `sudo codex-primer disable` |
| 恢复定时请求，并随系统启动 | `sudo codex-primer enable` |
| 重新登录 | `sudo codex-primer login device` |

登录失效、额度不足或模型不可用时会记录失败，等待下个固定触发点。
每个触发点只启动一次 CLI，不会循环补发；停机错过的请求也不会补发。

<br>

## 修改运行时间

安装后执行：

```bash
sudo codex-primer schedule 05:00,10:01,15:02,20:03 Asia/Shanghai
sudo codex-primer status
```

把时间改成自己需要的逗号分隔 `HH:MM` 列表；最后一项是 IANA 时区。
省略时区会保留当前设置，不修改服务器全局时区。
状态表格可能显示服务器本地时间，以同一输出中的 `OnCalendar` 配置为准。

也可以在首次安装时指定时间：

```bash
sudo bash install.sh --times 05:00,10:01,15:02,20:03 --timezone Asia/Shanghai
```

<br>

## 更新与卸载

更新时在项目目录执行：

```bash
git pull --ff-only
sudo bash install.sh
```

重复安装会保留登录数据、未显式修改的时间设置和定时器启停状态。
已暂停的任务更新后仍然暂停，需要恢复时执行 `sudo codex-primer enable`。
旧版本升级也会保留原运行时间；要采用新的默认时间，请手动运行上面的 `schedule` 命令。

卸载时选择是否保留登录数据：

```bash
sudo codex-primer uninstall           # 移除程序，保留专用账号和登录数据
sudo codex-primer uninstall --purge   # 同时删除本项目的专用账号和数据
```

只操作本项目的账号、目录与 systemd 单元；历史日志由系统 journald 按原策略保留。

<br>

## 登录遇到问题

使用希望预热的 **ChatGPT 订阅账号**。普通 API Key 的计费与订阅额度分开。

```bash
sudo codex-primer login device
```

如果账号尚未启用设备码登录，可用普通浏览器登录和临时 SSH 回调：

1. 在自己电脑上连接服务器并建立本地转发：

   ```bash
   ssh -L 127.0.0.1:1455:127.0.0.1:1455 USER@YOUR_SERVER
   ```

2. 在这个 SSH 会话中执行：

   ```bash
   sudo codex-primer login browser
   ```

3. 在自己电脑的浏览器打开命令打印的完整官方登录地址，完成授权，等待终端显示成功，再关闭临时 SSH 会话。
4. 运行 `sudo codex-primer enable` 和 `sudo codex-primer status`。

首次安装也可用 `sudo bash install.sh --login browser`，前提是回调转发已建立。自定义 SSH 端口、密钥时自行加入 `-p` 和 `-i` 参数。

凭据保存在服务器 `/var/lib/codex-primer/.codex/auth.json`，不会进入源码仓库。登录失效、额度不足或模型不可用时记录失败，等待下个固定触发点，不自动切换到昂贵模型。

<br>

## 可选安装方式

```bash
bash install.sh --check                       # 只检查环境和参数
sudo bash install.sh --login skip --no-enable # 首次安装时跳过登录且不启用定时器
sudo bash install.sh --enable                 # 更新时显式恢复定时器
```

`--no-enable` 只控制首次安装时不启用新的定时器；暂停已有任务使用 `disable`。
安装或登录遇到“正在运行/锁被占用”的提示时，等待当前操作结束后再试。

<br>

## 实现与验证（可选）

<details>
<summary>资源限制、测试与运行细节</summary>

- 官方原生 CLI，固定版本 **0.164.0**，核对 SHA-256；运行无需 Node.js、Python 或 Docker。
- 请求完成即退出，专用账号下无常驻进程。
- 内存硬上限 **192 MiB**，超过 128 MiB 开始回收；交换空间上限 64 MiB。
- CPU 上限为单核 20%，低 CPU / 磁盘调度优先级。
- 独立账号 `codex-primer`，只读系统目录，仅本任务的数据目录可写。
- 临时会话、精简指令，关闭不需要的工具和后台自动启动。

Debian 13、约 1 GiB 内存主机上的一次测试：服务内存峰值 **30.9 MiB**，输入 5,267 token（缓存输入 4,224），输出 5 token，推理输出 0。输入仍包含 CLI 上下文，并非只消耗一个 `OK` 的 token；实际用量与缓存命中会变化。

2026-10-25 的优化版实机测试：约 **4 秒**返回 `OK`，服务内存峰值约 **29.0 MiB**，退出后无常驻进程；验证了更新保留暂停状态、原时区与原登录数据。两次内存数据受缓存及运行条件影响，不能据此保证固定比例的性能提升。

当前 CLI 在工具主机关闭时可能记录 `Code Mode is unavailable` 非致命提示；结合最终 `turn.completed`、回复 `OK` 和退出码判断结果。

<br>

### 开发验证

```bash
bash tests/smoke.sh
shellcheck -x install.sh manage.sh send-once.sh lib/common.sh tests/*.sh
```

`tests/integration.sh` 在一次性 systemd 主机上验证首次 / 重复安装、只修改小时或时区时保留另一项、启停、缺少登录和 API Key 登录时拒绝请求，以及两种卸载方式，同时检查另一服务的进程号不变。发送包装脚本用本地假 CLI 验证正确回复、错误回复和原始错误码传递。为避免误操作，必须显式设置 `CODEX_PRIMER_INTEGRATION=1`；已有安装的主机会拒绝运行该测试。不需要真实账号，也不发送模型请求。

回归检查还覆盖：更新不恢复已暂停的任务；只改小时保留管理命令中的时区；登录检查超时后不发送请求；运行摘要的结果与退出码正确，且文件权限为 `0600`。

安装、登录、修改时间和卸载使用管理锁；更新前另行获取发送锁，避免请求运行时替换程序。
文件按原子方式替换，但整个安装过程不具备事务回滚。

</details>

<br>

## 参考

- [OpenAI Codex](https://github.com/openai/codex) / [非交互模式](https://learn.chatgpt.com/docs/non-interactive-mode) / [认证](https://learn.chatgpt.com/docs/auth)
- [UsageLoop](https://github.com/benthompsondev/usageloop)：完整桌面调度和窗口核验。
- [codex-session-primer](https://github.com/VIEWVIEWVIEW/codex-session-primer)：GitHub Actions 预热方案。

本项目使用官方 CLI，不直接维护内部 HTTP 接口或令牌刷新逻辑。MIT License。
