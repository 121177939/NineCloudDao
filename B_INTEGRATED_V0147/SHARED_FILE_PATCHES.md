# 共享文件补丁

| 文件 | 基线SHA256 | 候选SHA256 | 补丁 |
|---|---|---|---|
| `app.js` | `e945f9dc2665934df924298f5777f99ee6175fd98bd28ad9585f0b0051740c6e` | 见 `MODULE_MANIFEST.json` | `patches/app.js.patch` |
| `styles.css` | `09fa1430daf2d9aa01bcaf623cfe74938fc364ec1cb04a8de326548d7c3fe41d` | 见 `MODULE_MANIFEST.json` | `patches/styles.css.patch` |

没有修改：`index.html`、`config.js`、`sw.js`、`update-guard.js`。

正式接入后的版本号、CACHE号、Service Worker缓存名和发布清单由A线统一升级，本模块不越权修改发布元数据。
