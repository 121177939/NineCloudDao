@file:OptIn(ExperimentalJsExport::class)
package com.example.remotea

import kotlin.js.JsExport

@JsExport
object WebParser {
    private const val RS = "\u001e"
    private const val US = "\u001f"

    /** Browser installs the same authenticated cloud style-rule package used by Android A. */
    fun installRules(version: Double, packed: String): String = try {
        val specs = if (packed.isBlank()) emptyList() else packed.split(RS).filter { it.isNotEmpty() }.mapIndexed { index, row ->
            val f = row.split(US)
            require(f.size == 10) { "规则包第 ${index + 1} 条字段不完整" }
            RecognitionRuleSpec(
                id = f[0], name = f[1], pattern = f[2].removePrefix("(?m)"), replacement = f[3],
                sourceTemplate = f[4], targetTemplate = f[5], enabled = f[6] == "1",
                ruleType = f[7].ifBlank { "style" }, dslVersion = f[8].toIntOrNull() ?: 1,
                minClientCode = f[9].toIntOrNull() ?: 0
            )
        }
        RecognitionRuleRuntime.install(version.toLong(), specs)
        """{"ok":true,"version":${RecognitionRuleRuntime.version},"count":${specs.size}}"""
    } catch (e: Throwable) {
        """{"ok":false,"error":"${esc(e.message ?: "规则安装失败")}"}"""
    }

    fun ruleVersion(): Double = RecognitionRuleRuntime.version.toDouble()

    /** Public scalar JSON ambiguity entry point; same deterministic candidates as Android A. */
    fun ambiguities(input: String): String = try {
        val a = ChineseCodeParser.findAmbiguities(input)
        val rows = a.joinToString(",") { x ->
            val choices = x.choices.joinToString(",") { c ->
                """{"key":"${esc(c.key)}","title":"${esc(c.title)}","normalized":"${esc(c.normalized)}","detail":"${esc(c.detail)}","combinations":${c.combinations},"totalJiao":${c.totalJiao}}"""
            }
            """{"id":"${esc(x.id)}","type":"${esc(x.type)}","source":"${esc(x.source)}","start":${x.start},"end":${x.endExclusive},"occurrence":${x.occurrence},"explanation":"${esc(x.explanation)}","choices":[$choices]}"""
        }
        "[$rows]"
    } catch (e: Throwable) { "[]" }

    /** Public scalar JSON entry point: browser never reimplements wire parsing. */
    fun inspect(input: String): String = encodeReport(input, emptyList())
    fun inspectWithSelections(input: String, packedSelections: String): String = encodeReport(input, parseSelections(packedSelections))

    fun plan(input: String, screenshot: Boolean, convertedOdds: Boolean): String =
        encodePlan(input, screenshot, convertedOdds, emptyList())
    fun planWithSelections(input: String, screenshot: Boolean, convertedOdds: Boolean, packedSelections: String): String =
        encodePlan(input, screenshot, convertedOdds, parseSelections(packedSelections))

    private fun encodeReport(input: String, selections: List<RecognitionAmbiguitySelection>): String = try {
        val report = MixedParser.inspect(input, selections)
        val batch = report.batch
        val issueJson = report.issues.joinToString(",") { it ->
            """{"start":${it.start},"end":${it.endExclusive},"severity":"${it.severity.name}","notice":"${it.notice.name}","message":"${esc(it.message)}"}"""
        }
        val scat = batch?.scatter?.items?.joinToString(",") {
            """{"number":"${esc(it.number)}","amountJiao":${it.amountJiao},"groupId":${it.groupId}}"""
        } ?: ""
        val suite = batch?.suites?.joinToString(",") {
            """{"canonical":"${esc(it.canonicalText)}","source":"${esc(it.previewText)}","amountJiao":${it.amountJiao},"expectedCount":${it.expectedCount}}"""
        } ?: ""
        """{"valid":${report.valid},"command":${if (batch==null) "null" else "\"${esc(batch.command)}\""},"totalJiao":${batch?.totalJiao ?: 0},"totalLines":${batch?.totalLines ?: 0},"issues":[$issueJson],"scatter":[$scat],"suites":[$suite],"turnCount":${batch?.turnCount ?: 0}}"""
    } catch (e: Throwable) {
        """{"valid":false,"command":null,"totalJiao":0,"issues":[{"start":0,"end":${input.length},"severity":"ERROR","message":"${esc(e.message ?: "解析出错")}"}],"scatter":[],"suites":[],"turnCount":0}"""
    }

    private fun encodePlan(input: String, screenshot: Boolean, convertedOdds: Boolean, selections: List<RecognitionAmbiguitySelection>): String = try {
        val report = MixedParser.inspect(input, selections)
        require(report.valid && report.batch != null) { "号码未正确识别" }
        val original = report.batch!!
        val adjusted = original.copy(
            screenshotMode = if (original.suites.isEmpty()) ScreenshotMode.LEGACY
                else if (screenshot) ScreenshotMode.ROUTED else ScreenshotMode.UNIFIED_HOME,
            convertOdds = convertedOdds
        )
        MixedProtocol.validate(adjusted)
        require(MixedProtocol.decode(adjusted.command).command == adjusted.command) {
            "B 端 M1 指令往返不一致，拒绝提交"
        }
        """{"valid":true,"command":"${esc(adjusted.command)}","totalJiao":${adjusted.totalJiao},"totalLines":${adjusted.totalLines},"screenshotMode":"${adjusted.screenshotMode.name}"}"""
    } catch(e: Throwable) {
        """{"valid":false,"error":"${esc(e.message ?: "编制协议失败")}"}"""
    }

    private fun parseSelections(packed: String): List<RecognitionAmbiguitySelection> =
        if (packed.isBlank()) emptyList() else packed.split(RS).filter { it.isNotEmpty() }.mapIndexed { index, row ->
            val f = row.split(US)
            require(f.size == 4) { "歧义选择第 ${index + 1} 条格式错误" }
            RecognitionAmbiguitySelection(f[0], f[1], f[2].toIntOrNull() ?: 0, f[3])
        }

    private fun esc(s: String): String = buildString {
        for (c in s) when(c) {
            '\\' -> append("\\\\")
            '"' -> append("\\\"")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> append(c)
        }
    }
}
