# Librime Evo Android 外置引擎

基于 [梁佬的 Rime 插件模板](https://github.com/fxliang/rime-plugin-template)。
适用于支持外置 Rime 引擎的前端，例如 Foxy。

从 [Releases](https://github.com/amzxyz/rime-plugin-template/releases/latest)
下载并安装 `librime-evo-v<发布版本>-arm64-v8a.apk`，再在前端的引擎设置里选择 **Librime Evo**。
APK 内含 Evo、LuaJIT 和 Evo Octagram。方案、词库及 `.dlm` 模型由前端的 Rime 数据目录提供。

## 发布

进入 [Actions](https://github.com/amzxyz/rime-plugin-template/actions/workflows/build.yml)，
选择 **Run workflow**。工作流按运行创建时的北京时间和运行编号生成版本。
例如标签 `v2026.11.23.4` 对应 `librime-evo-v2026.11.23.4-arm64-v8a.apk`。
工作流编译、签名并验签，通过后把这个 APK 上传到 GitHub Release。

仓库 Actions Secrets 使用 `SIGNING_KEY`（keystore 的 Base64）、`KEY_STORE_PASSWORD`、
`ALIAS` 和 `KEY_PASSWORD`。用同一把密钥签署后续版本可支持覆盖安装。
`KEY_STORE_PASSWORD` 用于打开 keystore，`KEY_PASSWORD` 用于解锁别名对应的私钥。
可在本机用 `keytool -list -keystore release.jks` 校验 keystore 密码并查看别名。

## 本地构建

使用 JDK 21、Android SDK 36、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.31.6，
以及 Bash、GNU Make、curl、rsync 和 tar。

```sh
git clone --recursive https://github.com/amzxyz/rime-plugin-template.git
cd rime-plugin-template
./gradlew :app:assembleRelease
```

本地签名可按 `keystore.properties.example` 配置。
`lib/librime` 和 `lib/evo-octagram` 固定源码版本，LuaJIT 随 Evo 递归获取。
更新组件时在本仓库提交新的子模块指针。运行 `./gradlew :app:rimeClean` 可清理原生编译缓存。
