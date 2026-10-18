# 打印机现场助手 (Printer Field Kit)

连上网络，自动发现并安装网络打印机 —— 为经常跑现场的 IT / 打印机维护工程师准备的小工具。

Windows 10/11 · PowerShell 5.1 · 免安装 · 单 EXE 分发

## 它解决什么问题

外出装机或维修时，每到一个地方都要重复这一套：

> 扫网段找打印机 IP → 查型号 → 找对应驱动 → 手动添加端口和队列

本工具把整套流程自动化：**连上现场网络 → 自动完成上面全部步骤**，静默无感。

## 工作原理

1. 自动识别活动网卡（WiFi / 网线），扫描所在网段
2. 探测打印相关端口：`9100`（RAW）/ `631`（IPP）/ `515`（LPD）
3. 对发现的设备，通过 **SNMP** 与**打印机 Web 界面**双保险读取型号
4. 与本机驱动库匹配：已注册驱动 + Windows 驱动仓库（DriverStore）里全部打印机驱动（按 INF 中 `Class=Printer` 识别）
5. 匹配成功则自动完成：注册驱动 → 创建 TCP/IP 端口（RAW 9100）→ 创建打印机队列
6. 队列命名格式 `型号 (IP)`，例如 `MX-M3551 (192.168.1.100)`
7. 端口上已有队列的自动跳过，**重复运行零副作用**

## 使用方式

### 手动模式

双击 `打印机现场助手.exe` → UAC 点「是」→ 等待 10~40 秒 → 弹出结果：

- **已自动安装** —— 本次装好的打印机
- **已存在跳过** —— 该 IP 上已有队列，不重复装
- **未能处理** —— 没识别出型号 / 本机暂无对应驱动

### 自动模式（推荐常开）

双击 `开启自动模式.bat` 后：

- 每当**连接新网络 / 登录系统**，约 20 秒后自动静默扫描并安装（无任何弹窗）
- 自动模式下只处理 SHARP 机型，已装过的自动跳过
- 双击 `关闭自动模式.bat` 可随时关闭

日志（每次运行都会追加）：`C:\ProgramData\PrinterFieldKit\field-kit.log`

## 环境要求

| 项目 | 要求 |
|---|---|
| 系统 | Windows 10 / 11（64 位） |
| 运行环境 | Windows PowerShell 5.1（系统自带，无需安装） |
| 权限 | 管理员（安装打印机本身就需要；脚本会自动请求 UAC 提权） |

## 构建

```powershell
# 可选：把驱动包放在仓库根目录（文件名 driver.zip，见下节），会自动内置进 EXE
powershell -ExecutionPolicy Bypass -File build\build.ps1

# 产物在 dist\ 目录：
#   打印机现场助手.exe + 自动模式开关脚本（4 个）
```

打包原理：IExpress（Windows 自带）自解压包，脚本编码自动转换（UTF-8 BOM / ASCII + CRLF）。

## 关于驱动包（重要）

本仓库**不包含任何厂商驱动文件**（版权原因）。工具运行时的驱动来源有两层：

1. **本机已有驱动** —— 自动扫出来直接用（装过打印机驱动的电脑通常就够用）；
2. **可选的 `driver.zip`** —— 任意打印机驱动包（INF / CAT / DLL 原样打包）放一份到仓库根目录，构建时会被内置进 EXE；运行时自动释放并加入系统驱动仓库。

`tools\collect-driver-package.ps1` 可以把**本机 DriverStore 里已安装的某个驱动包**整包导出成 `driver.zip`：

```powershell
# 交互式：列出本机所有打印机驱动包，输入编号导出
powershell -ExecutionPolicy Bypass -File tools\collect-driver-package.ps1

# 只看列表 / 按名称直接导出
powershell -ExecutionPolicy Bypass -File tools\collect-driver-package.ps1 -List
powershell -ExecutionPolicy Bypass -File tools\collect-driver-package.ps1 -Export su2emchs.inf
```

> 分发厂商驱动请遵守相应许可协议；本脚本仅用于把本机已有驱动包取出备用。

## 隐私与合规

- 工具**只在本机**安装打印机，不向其他电脑推送任何东西
- 不联网、不上传任何数据；日志仅保存在本机
- 请仅在你**获得授权**的网络环境中使用
- 自动模式默认只处理 SHARP 机型（可在 `src\field-kit.ps1` 顶部修改）
- SHARP 等品牌名称仅为说明兼容性，商标归其所有者

## License

[MIT](LICENSE)
