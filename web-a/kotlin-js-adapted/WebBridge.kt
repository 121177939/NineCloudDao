@file:OptIn(ExperimentalJsExport::class)
package com.example.remotea

import kotlin.js.JsExport

@JsExport
object WebParser {
    /** Public scalar JSON entry point: browser never reimplements wire parsing. */
    fun inspect(input: String): String = try {
        val report = MixedParser.inspect(input)
        val batch = report.batch
        val issueJson = report.issues.joinToString(",") { it ->
            """{"start":${it.start},"end":${it.endExclusive},"severity":"${it.severity.name}","message":"${esc(it.message)}"}"""
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
    fun plan(input: String, screenshot: Boolean, convertedOdds: Boolean): String = try {
        val report = MixedParser.inspect(input)
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
