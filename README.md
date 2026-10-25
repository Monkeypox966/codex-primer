# Codex Primer

在小内存 Debian / Ubuntu 服务器上，每天固定发送四次轻量 Codex 请求。

默认在**北京时间 05:00、10:00、15:00、20:00** 使用 **GPT-6 Luna / low**，只要求回复 `OK`。时间可配置，采用系统定时器，完成后退出。

> 本项目安排普通订阅请求，不能增加额度、重置正在生效的窗口或绕过周额度。固定整点发送不保证每次开启新窗口，也不会根据额度连续重试。

## 一键安装

适用于 **Debian / Ubuntu x86_64、运行 systemd 的主机**，需要 root 或 sudo。已在 Debian 13 实机验证，Ubuntu 24.04 的安装与卸载流程已通过 GitHub Actions。

下载仓库后执行：

```bash
sudo bash install.sh
```

安装器会下载并校验官方原生 Codex CLI、建立独立账号、引导首次登录并启用定时器。默认设备码登录：在浏览器打开终端显示的官方地址并完成授权。

仓库已公开，无需 GitHub 登录。已安装 Git 的机器可以直接克隆：

```bash
git clone https://github.com/Monkeypox966/codex-primer.git
cd codex-primer
sudo bash install.sh
```

服务器没有 Git 时，可直接下载源码包：

```bash
curl -fL https://github.com/Monkeypox966/codex-primer/archive/refs/heads/main.tar.gz -o codex-primer.tar.gz
tar -xzf codex-primer.tar.gz
sudo bash codex-primer-main/install.sh
rm -f codex-primer.tar.gz
```

也可以使用 GitHub 页面上的 **Code → Download ZIP**，解压后上传到服务器。安装器依赖同目录的其他项目文件，不要只下载 `install.sh` 后单独执行。

安装器不自动改动系统软件包。若缺少依赖，可先安装：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl tar coreutils util-linux passwd tzdata
```

重复安装会保留登录数据和未指定的时间设置：只传 `--hours` 会保留原时区，只传 `--timezone` 会保留原小时。首次下载包约 110 MiB，安装后的程序约 294 MiB，均为磁盘占用。

安装、登录、修改时间和卸载使用同一个管理锁，避免同时运行造成文件冲突。更新文件前还会获取发送锁；安装包下载过程中若恰好开始了请求，会停止更新并提示稍后重试。程序和脚本按文件原子替换，不会把写到一半的文件交给定时任务执行。这不等于整个安装过程具备事务回滚。

登录也会检查发送锁，避免请求正在运行时修改登录数据；并发的管理命令会直接给出提示，不排队或反复重试。

## 管理命令

```bash
sudo codex-primer status       # 登录、最后结果与下次触发
sudo codex-primer logs         # 最近 30 条日志
sudo codex-primer logs 100
sudo codex-primer run          # 立即发送一次，消耗真实额度
sudo codex-primer disable      # 暂停后续定时请求
sudo codex-primer enable       # 恢复，并随系统启动
```

每个触发点启动一次 CLI，脚本无重试循环，服务失败不自动重启。CLI 自身可能进行有限网络重连；90 秒超时后终止，最多额外等待 10 秒。停机错过的触发不补发。

发送前确认专用账号使用 ChatGPT 登录，并移除继承的 API Key 和其他 Codex 数据目录设置，避免误用不同的认证来源。请求只有在 CLI 退出码为零且最终回复确实为 `OK` 时才记为成功。最终回复放入权限受限的临时文件，结束后立即清理；检查登录状态本身不发送模型请求。

## 修改时间

```bash
# 安装时指定
sudo bash install.sh --hours 05,10,15,20 --timezone Asia/Shanghai

# 安装后修改
sudo codex-primer schedule 06,11,16,21 Asia/Shanghai

# 只检查环境及参数，不写入系统
bash install.sh --check

# 只安装文件，跳过登录，不启用新的定时器
sudo bash install.sh --login skip --no-enable
```

`--no-enable` 保留已有定时器的启用状态；暂停已安装任务请使用 `disable`。时间按指定 IANA 时区解释，不修改服务器全局时区。状态表格可能显示服务器本地时间；同一输出的 `OnCalendar` 显示实际配置。

## 无头服务器登录

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

## 内存与资源

- 官方原生 CLI，固定版本 **0.164.0**，核对 SHA-256；运行无需 Node.js、Python 或 Docker。
- 请求完成即退出，专用账号下无常驻进程。
- 内存硬上限 **192 MiB**，超过 128 MiB 开始回收；交换空间上限 64 MiB。
- CPU 上限为单核 20%，低 CPU / 磁盘调度优先级。
- 独立账号 `codex-primer`，只读系统目录，仅本任务的数据目录可写。
- 临时会话、精简指令，关闭不需要的工具和后台自动启动。

Debian 13、约 1 GiB 内存主机上的一次测试：服务内存峰值 **30.9 MiB**，输入 5,267 token（缓存输入 4,224），输出 5 token，推理输出 0。输入仍包含 CLI 上下文，并非只消耗一个 `OK` 的 token；实际用量与缓存命中会变化。

当前 CLI 在工具主机关闭时可能记录 `Code Mode is unavailable` 非致命提示；结合最终 `turn.completed`、回复 `OK` 和退出码判断结果。

## 卸载

```bash
sudo codex-primer uninstall           # 移除本项目，保留账号和登录数据
sudo codex-primer uninstall --purge   # 同时清除本项目的专用账号及数据
```

只操作本项目的账号、目录与 systemd 单元，不操作其他代理、防火墙、网络服务或容器。历史日志由系统 journald 按原策略保留。

## 验证

```bash
bash tests/smoke.sh
shellcheck -x install.sh manage.sh send-once.sh lib/common.sh tests/*.sh
```

`tests/integration.sh` 在一次性 systemd 主机上验证首次 / 重复安装、只修改小时或时区时保留另一项、启停、缺少登录和 API Key 登录时拒绝请求，以及两种卸载方式，同时检查另一服务的进程号不变。发送包装脚本用本地假 CLI 验证正确回复、错误回复和原始错误码传递。为避免误操作，必须显式设置 `CODEX_PRIMER_INTEGRATION=1`；已有安装的主机会拒绝运行该测试。不需要真实账号，也不发送模型请求。

## 参考

- [OpenAI Codex](https://github.com/openai/codex) / [非交互模式](https://learn.chatgpt.com/docs/non-interactive-mode) / [认证](https://learn.chatgpt.com/docs/auth)
- [UsageLoop](https://github.com/benthompsondev/usageloop)：完整桌面调度和窗口核验。
- [codex-session-primer](https://github.com/VIEWVIEWVIEW/codex-session-primer)：GitHub Actions 预热方案。

本项目使用官方 CLI，不直接维护内部 HTTP 接口或令牌刷新逻辑。MIT License。
