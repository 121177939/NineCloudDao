# Pages V2.1.1 R3 build失败修复

V2.1.0的 `deploy-pages.yml` 仍调用 `tools/build_pages_v2_0_12.py`。该构建器硬编码要求：`V2.0.12 CACHE104`、`cacheEpoch:104`、`nextSqlNumber=233`、`sqlRevision=...229-232`。因此V2.1.0源文件本身正确升级后，构建器反而必然失败。

本版不改变已验证的Pages部署链，只做以下修复：
- workflow改调用 `tools/build_pages_v2_1_1.py`；
- 版本门禁改为V2.1.1 CACHE106 / SQL233 / NEXT_SQL234；
- Pages产物加入 `b-equipment-v210.js/css`；
- JS语法检查加入 `b-equipment-v210.js` 和 `b-world-boss01.js`；
- deploy完成后的在线核验改为V2.1.1 CACHE106。

本地已按workflow build阶段等价命令验证通过。
