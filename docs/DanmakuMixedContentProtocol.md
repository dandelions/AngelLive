# 弹幕图文混排协议

AngelLiveCore 从 2026-08-17 起支持一条弹幕包含有序 `segments`。宿主按数组顺序完成图片加载、单行布局和一次性离屏光栅化，随后仍由 CALayer 负责运动合成。

## 消息格式

```json
{
  "text": "欢迎 [wave] Alice",
  "nickname": "demo",
  "color": 16777215,
  "segments": [
    { "type": "text", "text": "欢迎 " },
    {
      "type": "image",
      "url": "https://example.com/wave.webp",
      "width": 80,
      "height": 40,
      "alt": "[wave]"
    },
    { "type": "text", "text": " Alice" }
  ]
}
```

片段定义：

- 文本：`{ "type": "text", "text": string }`
- 图片：`{ "type": "image", "url": string, "width"?: number, "height"?: number, "alt"?: string }`

`url` 仅接受 HTTP/HTTPS。`width` 和 `height` 是原始像素尺寸，只用于宽高比；图片显示高度由当前弹幕字号决定。`alt` 是单张图片加载失败时的局部降级文案。

## 兼容与降级

- 有至少一个有效 `segments` 片段时，宿主优先使用 `segments`。
- `segments` 缺失或全部无效时，继续读取旧的整条 `image` 字段。
- 旧 `image` 也不存在或不可用时，显示消息级 `text`。
- 未知或畸形片段只丢弃自身，不丢弃同一条消息中的有效片段。
- 多张图片并行下载，但最终绘制顺序始终与数组一致。
- iOS FULLUI 底部聊天列表与飞屏弹幕共用 `segments`、图片缓存和失败降级规则；聊天胶囊会按顺序显示行内图片。

为防止不可信插件制造无界下载或超大离屏位图，宿主每条最多处理前 32 个片段、其中最多 8 张图片；超宽图片的显示宽高比上限为 4:1。

## 渲染约定

纯文本与纯图片仍走原有专用 Cell；只有两个及以上有效片段才使用混排 Cell。混排 Cell 会一次性完成测量和光栅化，轨道碰撞系统只读取最终 `size`，不感知内部片段。这一边界也为未来增加 Metal 渲染后端保留了稳定的上层协议。
