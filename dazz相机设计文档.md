# Dazz CAM（Dazz 相机）2.6.9 逆向设计文档

> 分析对象：`Dazz相机_2.6.9解锁专业版功能.ipa`（76 MB，解压后 .app 约 92 MB）
> 分析方式：解包 + Mach-O 静态逆向（arm64 反汇编、ObjC/Swift 元数据、CoreImage Kernel 源码提取）+ 资源体系全量提取
> 分析日期：2026-09-30
> 配套产物：`Dazz_LUT/`（54 个 .cube 颜色查找表）、`Dazz_资源/`（1081 个静态资源）

---

## 一、产品概览

**Dazz CAM 是一款"复古相机模拟器"**：不是给照片加滤镜的后处理 App，而是让用户"选用一台虚拟胶片机/古董数码机"，在取景时实时渲染年代质感，按下快门即得成品。

| 项目 | 内容 |
|---|---|
| Bundle ID | `dazz.camera.vintagecamera`（App Store id 1422471180） |
| 版本 | 2.6.9 (Build 19)，最低 iOS 10.0，iPhone 专用 |
| 构建 | Xcode 14.3.1 / iphoneos 16.4 SDK（2023-07 构建） |
| 语言 | **Swift 为主体**（DazzCamera 模块 333 个 Swift 类）+ Objective-C 混编（RNCryptor、DXPhotoPicker 等） |
| 本地化 | 15 种语言（en/zh-Hans/zh-Hant/ja/ko/de/fr/es/it/pt-PT/ru/th/vi…） |
| 权限 | 相机、麦克风、照片库读写、使用期间定位（照片地理标记） |
| 官网 | dazz.ltd（隐私/条款页面）；资源 CDN：`d2qjvbbxrax3kk.cloudfront.net` |

### 商业模式
- **内购解锁相机**：多数相机免费试用、付费解锁（`CameraProducts`/`DazzProducts`、`PROMPT_TO_UNLOCK`、`camera_advertise` 界面），支持买断（`ONE_TIME_PURCHASE`）与订阅；产品列表由服务端同步（`SyncProductsToFile`），本地不硬编码产品 ID。
- **广告 + 归因**：AdMob（GADApplicationIdentifier）+ SKAdNetwork 归因 + Adjust SDK。
- **增长**：Instagram/TikTok 引流（`FOLLOW_US_INSTAGRAM`、每周相机挑战 `Camera_Challenge`）。

### ⚠️ 包性质说明
本 IPA 为**破解重分发版**：主二进制 LC_LOAD_DYLIB 被追加注入 `@rpath/iOSGodsCom.dylib`（iOSGods 破解加载器，再加载 cookeddar.dylib 做 IAP 补丁，本包内未附带），并带 CydiaSubstrate 框架。分析时已剥离其影响；文档描述的是原版设计。此类包含来路不明注入代码，仅供离线研究。

---

## 二、总体架构

```
┌─────────────────────────────────────────────────────────┐
│  UI 层  Storyboard×11 + Swift View                      │
│  (CamerasView 相机列表 / CameraFilters / FrameOptions /  │
│   SwipeDownOptions / BuyPro 付费 / Collage / Developer) │
├─────────────────────────────────────────────────────────┤
│  相机域  DCameraMaster ── 33 个 DCamera* 型号类          │
│  (每台相机 = 属性集 + 渲染配方 + 资源前缀)               │
├─────────────────────────────────────────────────────────┤
│  渲染层  CoreImage CIKernel ×4 + Metal(default.metallib) │
│  LTColorLookup / CustomFilter / RGBToneCurve / D3DFilter│
├─────────────────────────────────────────────────────────┤
│  资源层  Assets.car(627图) + 散装资源(400+)              │
│  + RNCryptor 加密 LUT/贴纸 + CloudFront 动态下发         │
├─────────────────────────────────────────────────────────┤
│  基础设施  AVFoundation(拍照/录像) / Photos / Vision /   │
│  OpenCV(定制编译) / CoreLocation / StoreKit / Firebase  │
└─────────────────────────────────────────────────────────┘
```

### 类命名规范（逆向可见的工程纪律）
| 前缀 | 含义 | 示例 |
|---|---|---|
| `DCamera*` | 相机型号 | DCameraCCDR、DCameraS67 |
| `DVideo*` | 视频管线型号 | DVideo16MM、DVideoVHS |
| `DLens*` / `D3D*` | 附加镜头/3D | DLensFisheyeF、D3DFilter |
| `D*` | 领域服务 | DVideoWriter、DLocalAlbum、SYMetadata* |
| `LT*` | 基础组件 | LTColorLookup、LTStoreKit |
| `UI*` | 自研控件 | UICamButton、UIFocusButton |
| `DX*` | 第三方(DXPhotoPicker) | DXAlbumCell |

Swift 并发已采用 Actor（`CacheActor`、`WebNodesActor`、`LTDispatch`）。

---

## 三、相机系统设计（产品核心）

### 3.1 抽象结构
```
DCameraBase (基类)
 ├── DCameraAttributes   每机型的可调参数集
 ├── DCameraMaster       相机注册/切换/生命周期
 └── 33 个型号类（照片线 + 视频线共用型号语义）
```
每个型号类绑定一组**固定命名规范的资源前缀**，渲染时按前缀拼路径加载（前缀 + `.pnx`/`.jpg`/`.png`）。这就是"型号 = 资源配方"的数据驱动设计。

### 3.2 相机型号清单（逆向类名 + 资源映射）

| 型号类 | 对应资源前缀 | 风格定位 |
|---|---|---|
| DCameraCCDR | lookup_ccdr | CCD 数码相机（爆款 C 系列） |
| DCameraClassic / SClassic / UClassic | lookup_classic/classicu、vclassic_lookup、grain_dclassic | 经典胶片三兄弟 |
| DCameraS67 | s67_lookup、grain_s67 | 6×7 画幅胶片 |
| DCameraCPM35 | lookup_cpm35、grain_cpm35 | 35mm 轻便胶片机 |
| DCamera135NE / 135SR | lookup_135sr、grain_135sr、135ne_frame_cut* | 135 胶片（带齿孔边框） |
| DCameraNT16 | lookup_nt16(_2) | NT16 |
| DCameraExp | lookup_dexp/dexp3、grain_dexp | 重曝光 |
| DCameraQS | lookup_dqs | Quick Shot |
| DCameraFuns | lookup_dfuns/vfuns、grain_dfuns | Funs 系列 |
| DCameraGRDR | lookup_grdr | GR 风格街拍 |
| DCameraCT2F | lookup_ct2f | CT2F |
| DCameraBlack | lookup_dblack_1/2 | 黑白（日期戳特殊 NOT_SUPPORT_STAMP_DBLACK） |
| DCameraIR | lookup_IR01/02、grain_IR | 红外摄影 |
| DCameraHoga | lookup_hoga、blend_mask_hoga、vignette_hoga | 半幅/混合蒙版 |
| DCameraHalf | half_black/color/colorf | 半格相机 |
| DCameraCollage | lookup_collage、lookup_mask_collage | 多格拼贴 |
| DCameraInstC / InstCSQ / InstBW | lookup_instc/instsq/instss、vinst_border | 拍立得（C/SQ/黑白） |
| DCameraSlide | dslide_frame01-14、lookup_slidep | 幻灯片（DSlide 播放器界面） |
| DCamera3D | f_red/green/blue/yellow | 三维红蓝立体（镜头滤镜片） |
| DCameraOriginal | original_raw | 无滤镜原片 |
| DCameraGolf(视频) | video_golf01.mp4、golf_* | 高尔夫挥杆分解 |

**附加镜头**（可叠加在相机上）：DLensFisheyeF/FisheyeW（鱼眼广/长）、DLensCategory 管理。

### 3.3 每台相机的可配置维度（来自设置界面 Storyboard × 11）
边框 FRAME / 齿孔 PERFORATIONS / 日期戳（格式 YMD·MDY·DMY、字体 FONT、原片日期 vs 当前日期）/ 漏光 RANDOM_LIGHTLEAKS / 颗粒 / 比例 RATIO / 背景色 / 参数随机化 RANDOMIZE / 倒计时连拍 Burst / 网格 / 色温 / 曝光 / ISO·快门（高端机型）/ RAW·ProRaw / 变焦。

设计要点：**"机型"承载怀旧人格，"参数"承载个性化**，二者正交组合。

---

## 四、渲染管线设计

### 4.1 取到的完整 CIKernel 源码（Core Image Kernel Language，实测从二进制提取）

**① 主 LUT 滤色 kernel**（`LTColorLookup`，参数：原图、512×512 LUT、强度）：
```glsl
kernel vec4 lookup(sampler inputImage, sampler inputLUT, float intensity) {
    vec4 textureColor = sample(inputImage, samplerCoord(inputImage));
    textureColor = clamp(textureColor, vec4(0.0), vec4(1.0));
    float blueColor = textureColor.b * 63.0;
    vec2 quad1;                       // 8×8 平铺：蓝通道决定块
    quad1.y = floor(floor(blueColor) / 8.0);
    quad1.x = floor(blueColor) - (quad1.y * 8.0);
    vec2 quad2;
    quad2.y = floor(ceil(blueColor) / 8.0);
    quad2.x = ceil(blueColor) - (quad2.y * 8.0);
    vec2 texPos1;                     // 块内：R→x, G→y（半像素偏移采样）
    texPos1.x = (quad1.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * textureColor.r);
    texPos1.y = (quad1.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * textureColor.g);
    texPos1.y = 1.0 - texPos1.y;      // CI 坐标系 y 向上翻转
    ... (quad2 同理)
    vec4 newColor = mix(newColor1, newColor2, fract(blueColor));  // 蓝方向线性插值
    return mix(textureColor, vec4(newColor.rgb, textureColor.a), intensity);
}
```

**② 色差/边缘模糊 kernel**（`Aberration`，向径向偏移 RGB 三通道采样叠加）：
```glsl
kernel vec4 Aberration(sampler image, vec2 size, float sampleCount, float start, float blur) {
    ...
    float normalisedValue = length(((dc / size) - 0.5) * 2.0);   // 距中心归一化距离
    float strength = clamp((normalisedValue - start) * (1.0 / (1.0 - start)), 0.0, 1.0);
    vec2 redOffset   = -vector * strength * (blur * 2.0);        // R 偏移最大
    vec2 greenOffset = -vector * strength * (blur * 1.5);
    vec2 blueOffset  = -vector * strength * (blur * 1.0);        // 多次采样求和平均
}
```

**③ RGB 通道合成 kernel**（3D 红蓝相机/滤镜片，对应 f_red/f_green/f_blue/f_yellow 资源）：
```glsl
kernel vec4 rgbChannelCompositing(__sample red, __sample green, __sample blue) { ... }
```

**④ 黑白二值化 kernel**（印章/特殊蒙版用）：
```glsl
kernel vec4 replaceWithBlackOrWhite(__sample s) {
    if (s.r > 0.25 && s.g > 0.25 && s.b > 0.25) return vec4(0,0,0,1);
    return vec4(1,1,1,1);
}
```

另有 `default.metallib`（Metal 高性能路径）、`RGBToneCurve`（曲线）、`CustomFilter`、`LTFadeFilter`（褪色）。

### 4.2 512×512 LUT 平铺规范（逆向确证，与 kernel 一一对应）
```
LUT 图片: 512×512 = 8×8 个 64×64 块
  块序号 b(0..63) = row*8 + col  ← 输入蓝通道
  块内 x(0..63)              ← 输入红
  块内 y(0..63)              ← 输入绿（kernel 里做 y 翻转）
  像素 RGB 值                ← 输出颜色
已用包内恒等 LUT(LookupTableDefault) 验证布局零误差。
```

### 4.3 成片合成管线（静态资源在管线中的位置）
```
取景/导入
  → 基础调节(曝光/色温/曲线)
  → [附加镜头: 鱼眼畸变 / 色差 Aberration / 3D rgbChannelCompositing / 红外]
  → LUT 滤色(lookup kernel, pnx 解密图)
  → 颗粒叠加(grain_*.jpg, 按 ISO/机型混合)
  → 漏光(lightleaks_*.jpg, 概率随机 RANDOM_LIGHTLEAKS)
  → 扫描线/网点(DCR_scanline, patterns, ndfilter)
  → 边框/齿孔/相纸(Frame_* / perforation / half_*)
  → 日期戳(timestamp + 字体, Vision 人脸跟随可选)
  → 暗角/蒙版(vignette, blend_mask)
  → 导出 DPhotoWriter / DFrameWriter(边框合成) / DVideoWriter(AVAssetWriter, 实时逐帧)
  → 元数据 SYMetadata*(EXIF/GPS/PNG/DNG/GIF)
```
视频线（DVideo* 13 个类）与照片线共用型号语义，录像时实时跑同一 CIImage 管线后经 `AVAssetWriter` 落盘；`DVideoPlayerView`/`AVPlayerViewController` 回放。

### 4.4 CV 能力
- **Vision**：`VisionHelper` 人脸检测（日期戳跟随人脸 `DRAG_FACE_TO_MOVE`）。
- **OpenCV（定制编译进主二进制）**：构建路径显示开发者 "lakez" 自编译 opencv3 + opencv_contrib(xfeatures2d SURF)，用于 D3D 深度/对齐等（`D3DAttributes`、`NO_3D_DATA`）。

---

## 五、资源体系设计

### 5.1 资源全景（已全量提取，见 `Dazz_资源/`）
| 类别 | 数量 | 说明 |
|---|---|---|
| 颜色 LUT | 56 个 .pnx | RNCryptor 加密的 512² PNG（54 个已解密转 .cube） |
| Assets.car | 627 张 | 胶片框/扫描线/齿孔/UI 图标 |
| 边框相框 | 96 | 135ne/8mm/vinst/dslide 系列 |
| 颗粒纹理 | 87 | 按机型 grain_* |
| 漏光 | 21 | lightleaks_* |
| 滤镜示例图 | 105 | 界面示例（index230329.json 索引） |
| 蒙版/暗角 | 28 | half_*、mask、vignette |
| 贴纸 | 7 个 .jpx | 加密 JPEG2000 星光贴纸（密码未在包内） |
| 声音/视频/字体 | 5/2/1 | 快门音效、引导视频、日期戳字体 |

命名规范 = `机型语义_资源类型[_序号]`（lookup_ / grain_ / frame / border / lightleaks_ / scanline_ / pattern_），**资源名即胶水**：型号类硬编码前缀字符串（部分用 mov/movk 立即数拼 Swift 内联字符串做轻度混淆），运行时拼接路径加载。

### 5.2 资源保护设计（本次逆向重点）
- **LUT/贴纸全量加密**：`.pnx`/`.jpx` = **RNCryptor v3**（2 字节头 `03 01` + 8B encSalt + 8B hmacSalt + 16B IV + AES-256-CBC 密文 + 32B HMAC-SHA256，PBKDF2-SHA1 1 万轮派生密钥）。
- **密码分层**：54 个颜色 LUT 用 `dazz1422`（可解）；蒙版/贴纸用另一密码，**不在包内**——由 `Developer/ResourceSetting` 开发者界面 + CloudFront CDN 的服务端下发体系分发（`Clear_Storage`、资源下载逻辑佐证）。
- 图片资源用 **CgBI** 苹果优化 PNG（轻度防直接提取）+ Assets.car 打包。
- 工程结论：防护目标是"防顺手拷贝"，非对抗逆向——滤镜视觉资产本身导出后即可复用，是其已知取舍。

### 5.3 动态化
`index230329.json`（实为 zip）等带日期的资源索引 + CDN，支持不发包更新示例图/贴纸/配置；`CacheActor`/`WebNodesActor` 负责缓存与下载。

---

## 六、商业化与数据

| 模块 | 实现 |
|---|---|
| 内购 | `LTStoreKit` 封装 StoreKit，`DazzProducts`/`CameraProducts` 按相机售卖，产品清单服务端同步；`BuyPro` storyboard（dc_pro_controller / dc_promotion_controller） |
| 广告 | AdMob + SKAdNetwork（Info.plist 详列） |
| 归因/统计 | Firebase Analytics + Crashlytics（133 处引用）+ Adjust |
| 图片加载 | SDWebImage（87 处，示例图/广告图下载） |

---

## 七、复刻要点（若要实现同类产品）

1. **领域模型先于滤镜**：把"机型"做成一等公民（属性集 + 渲染配方 + 资源前缀），滤镜只是配方的一个环节；新增机型 ≈ 新增资源包 + 一个子类。
2. **LUT 管线**：直接采用 512×512 平铺 LUT + 文中 `lookup` kernel（或 CIColorCube）；LUT 用标准 .cube 制作后烘焙成平铺 PNG。制作流程：DaVinci/PS 调色 → 导出 .cube → 转平铺 PNG。
3. **颗粒/漏光/边框全部预烘焙 PNG/JPG 素材**，用混合模式（overlay/multiply/screen）叠加，避免实时程序化噪声的算力成本；漏光用概率随机提升"每张都不一样"的胶片感。
4. **性能双路径**：预览用低分辨率 CIImage + Metal，导出用全分辨率重跑同一管线（代码复用、视觉一致）。
5. **日期戳是核心记忆点**：多字体 + 多格式 + Vision 人脸跟随 + 原片日期保留（导入老照片重洗）。
6. **资源保护建议**：若需类似 RNCryptor 方案，务必把密码放服务端下发并绑定安装（Dazz 的教训：主密码 `dazz1422` 被社区提取后全部 LUT 可导出）。

---

## 附录

- **A. 提取产物**
  - `Dazz_LUT/cube/`：54 个标准 .cube（DaVinci/Lightroom/Premiere 可直接用）
  - `Dazz_LUT/png/`：54 个解密 LUT 图 + 恒等默认 LUT
  - `Dazz_资源/`：1081 个分类静态资源 + 4 张预览图 + README
- **B. .pnx 解密**（详见 Dazz_LUT/README.md）：RNCryptor v3，密码 `dazz1422`。
- **C. 未解项**：7 个 star*.jpx 贴纸与 2 个蒙版 pnx（第二密码，服务端下发）；Assets.car 中 AppIcon 与 9 个 deepmap2 打包图集。
- **D. 主要第三方**：OpenCV(定制)、SDWebImage、RNCryptor、DXPhotoPicker、Firebase/Crashlytics、Adjust、Google AdMob、DeviceGuru、ZZCircleProgress。
