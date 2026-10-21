package com.example.remotea

/** Exact text parser. No OCR, inferred digits, fuzzy character correction or implicit amount defaults. */
/** Store amounts in integer jiao (0.1 yuan), never floating-point. */
object ExactAmount {
    fun format(jiao: Int): String = if (jiao % 10 == 0) (jiao / 10).toString()
        else "${jiao / 10}.${jiao % 10}"

    fun parse(raw: String): Int? {
        // Only 1 fractional digit is accepted. No scientific notation, signs or implicit rounding.
        if (!Regex("(?:0|[1-9][0-9]*)(?:\\.[0-9])?").matches(raw)) return null
        val parts = raw.split('.')
        val whole = parts[0].toLongOrNull() ?: return null
        if (whole > 100_000L) return null
        val jiao = whole * 10 + if (parts.size == 2) (parts[1][0] - '0') else 0
        return jiao.takeIf { it in 1L..1_000_000L }?.toInt()
    }
}

data class BatchItem(val number: String, val amountJiao: Int, val groupId: Int = 0) {
    val amountText: String get() = ExactAmount.format(amountJiao)
    // Only for older integer-based tests/callers: fractional amounts must use amountJiao.
    val amount: Int get() {
        require(amountJiao % 10 == 0) { "存在角金额，请使用 amountJiao" }
        return amountJiao / 10
    }
}

data class BatchOrder(val items: List<BatchItem>) {
    val totalJiao: Long get() = items.sumOf { it.amountJiao.toLong() }
    val totalAmountText: String get() = ExactAmount.format(totalJiao.toInt())
    val totalAmount: Long get() {
        require(totalJiao % 10 == 0L) { "存在角金额，请使用 totalJiao" }
        return totalJiao / 10L
    }
    /** Canonical transport string; integer format remains byte-for-byte v0.9.8 compatible. */
    val command: String get() = items.joinToString(";") { "${it.number}-${it.amountText}" }
    fun summary(): String = buildString {
        append("共 ${items.size} 条，合计 ${totalAmountText} 元（重复号码不合并）\n\n")
        items.forEachIndexed { index, item ->
            append("${index + 1}. ${item.number}-${item.amountText} 元")
            if (item.groupId > 0) append("  [第${item.groupId}组]")
            append('\n')
        }
    }
}

enum class BatchSeverity { ERROR, WARNING }
enum class BatchNotice { DUPLICATE, LOOKALIKE, NOTE, GENERAL }
/** UTF-16 offsets refer to the original user's text (same-length normalization only). */
data class BatchIssue(
    val start: Int,
    val endExclusive: Int,
    val message: String,
    val severity: BatchSeverity = BatchSeverity.ERROR,
    val notice: BatchNotice = BatchNotice.GENERAL
)
data class BatchParseReport(val order: BatchOrder?, val issues: List<BatchIssue>) {
    val valid: Boolean get() = order != null && issues.none { it.severity == BatchSeverity.ERROR }
    val warnings: List<BatchIssue> get() = issues.filter { it.severity == BatchSeverity.WARNING }
    val errors: List<BatchIssue> get() = issues.filter { it.severity == BatchSeverity.ERROR }
}
class BatchParseException(val problems: List<BatchIssue>) : IllegalArgumentException(
    problems.joinToString("；") { it.message }
)

object BatchParser {
    const val MAX_ITEMS = 50
    private const val MAX_TOTAL_JIAO = 1_000_000L
    private const val MAX_SINGLE_JIAO = 1_000_000L
    private val direct = Regex("([0-9X]{4})([-=])([0-9]+(?:\\.[0-9]+)?)(?:元|块)?")
    private val bare = Regex("[0-9X]{4}")
    private val sharedSuffix = Regex("(?:各打|打)[ \t]*([0-9]+(?:\\.[0-9]+)?)[ \t]*(?:元|块)|各[ \t]*([0-9]+(?:\\.[0-9]+)?)[ \t]*(?:元|块)?")
    private val dashSuffix = Regex("-[ \t]*([0-9]+(?:\\.[0-9]+)?)")
    private val separators = " ,，、;；。.\n\r\t"
    private val lookalikeX = "ⅩⅹΧχХхＸｘ"

    private fun separator(ch: Char): Boolean = ch in separators || ch.isWhitespace() || Character.isSpaceChar(ch)
    private fun wordEnd(text: String, next: Int): Boolean = next >= text.length || separator(text[next])
    private fun numberEnd(text: String, next: Int): Boolean = wordEnd(text, next) || (next < text.length && text[next] in "各打")
    private fun at(regex: Regex, text: String, i: Int): MatchResult? = regex.find(text, i)?.takeIf { it.range.first == i }

    private fun normalized(source: String): String = buildString(source.length) {
        for (ch in source) append(when (ch) {
            in '０'..'９' -> ('0'.code + ch.code - '０'.code).toChar()
            '－', '—', '–', '﹣' -> '-'
            '＝' -> '='
            'x', '*', '＊' -> 'X'
            in lookalikeX -> 'X'
            else -> ch
        })
    }

    private data class Pending(val value: String, val from: Int, val to: Int)

    fun inspect(source: String): BatchParseReport {
        val text = normalized(source)
        val errors = mutableListOf<BatchIssue>()
        val warnings = mutableListOf<BatchIssue>()
        val items = mutableListOf<BatchItem>()
        val pending = mutableListOf<Pending>()
        val seen = mutableMapOf<String, Int>()
        var currentGroup = 0
        var previousGroupAmount: Int? = null

        fun error(start: Int, end: Int, message: String) {
            errors += BatchIssue(start.coerceIn(0, source.length), end.coerceIn(0, source.length), message)
        }
        fun warn(start: Int, end: Int, message: String, notice: BatchNotice = BatchNotice.GENERAL) {
            warnings += BatchIssue(start.coerceIn(0, source.length), end.coerceIn(0, source.length),
                message, BatchSeverity.WARNING, notice)
        }
        fun checkNumber(number: String, start: Int, end: Int): Boolean {
            if (number.length != 4 || number.any { it !in "0123456789X" }) {
                error(start, end, "号码必须精确为4位（数字或 X 空位）")
                return false
            }
            if (number.count { it == 'X' } > 2) {
                error(start, end, "三处以上 X 的玩法尚未确认，拒绝猜测")
                return false
            }
            return true
        }
        fun price(raw: String, from: Int, to: Int): Int? {
            val n = ExactAmount.parse(raw)
            if (n == null || n > MAX_SINGLE_JIAO) {
                error(from, to, "金额必须是0.1～100000元，最多一位小数（角），不能使用分或四舍五入")
                return null
            }
            return n
        }
        fun add(number: String, amount: Int, start: Int, end: Int, group: Int) {
            val first = seen[number].also { if (it == null) seen[number] = start }
            if (first != null) warn(start, end, "号码 $number 再次出现：保留为独立记录，不去重不合并", BatchNotice.DUPLICATE)
            items += BatchItem(number, amount, group)
        }
        fun flushPending() {
            pending.forEach { error(it.from, it.to, "${it.value} 没有明确金额；请输入各1元、打1块或 -1 等") }
            pending.clear()
        }
        fun assignPending(amount: Int) {
            currentGroup++
            pending.forEach { add(it.value, amount, it.from, it.to, currentGroup) }
            pending.clear()
            previousGroupAmount = amount
        }
        if (source.isBlank()) return BatchParseReport(null, listOf(BatchIssue(0, source.length, "请先输入号码")))
        for (i in source.indices) {
            if (source[i] in lookalikeX) warn(i, i + 1, "字符 ${source[i]}（U+${source[i].code.toString(16).uppercase().padStart(4,'0')}）按 X 空位解析；请核对原文", BatchNotice.LOOKALIKE)
        }
        var i = 0
        while (i < text.length) {
            if (separator(text[i])) { i++; continue }
            // Notes are recognized only as complete standalone tokens; they never carry amounts.
            if (text[i] == '五' && wordEnd(text, i + 1)) {
                warn(i, i + 1, "“五”视为玩法备注，不作为号码或金额", BatchNotice.NOTE)
                i++
                continue
            }
            val full = at(direct, text, i)
            if (full != null && wordEnd(text, full.range.last + 1)) {
                if (pending.isNotEmpty()) flushPending()
                currentGroup++
                val code = full.groupValues[1]
                val amountStart = i + code.length + 1
                val value = price(full.groupValues[3], amountStart, full.range.last + 1)
                if (checkNumber(code, i, i + 4) && value != null) {
                    add(code, value, i, i + 4, currentGroup)
                }
                previousGroupAmount = null
                i = full.range.last + 1
                continue
            }
            val naked = at(bare, text, i)
            if (naked != null && numberEnd(text, naked.range.last + 1)) {
                val code = naked.value
                if (checkNumber(code, i, i + 4)) pending += Pending(code, i, i + 4)
                previousGroupAmount = null
                i += 4
                continue
            }
            val shared = at(sharedSuffix, text, i)
            if (shared != null) {
                val end = shared.range.last + 1
                // For an omitted 元/块 unit, next must be a separator/end.
                val valueText = shared.groupValues[1].ifEmpty { shared.groupValues[2] }
                val canFollowNumber = shared.value.endsWith('元') || shared.value.endsWith('块')
                if (canFollowNumber || wordEnd(text, end)) {
                    val value = price(valueText, i, end)
                    when {
                        value == null -> pending.clear()
                        pending.isNotEmpty() -> assignPending(value)
                        previousGroupAmount == value -> warn(i, end, "重复金额说明，不会再次生成记录", BatchNotice.NOTE)
                        else -> error(i, end, "金额说明前没有待分配号码")
                    }
                    i = end
                    continue
                }
            }
            val dash = at(dashSuffix, text, i)
            if (dash != null && wordEnd(text, dash.range.last + 1)) {
                val end = dash.range.last + 1
                val value = price(dash.groupValues[1], i, end)
                if (value != null) {
                    if (pending.isNotEmpty()) assignPending(value)
                    else error(i, end, "-金额 前没有连续的待分配号码")
                } else pending.clear()
                i = end
                continue
            }
            // No fuzzy recovery: unknown text is marked and not silently ignored.
            val from = i
            while (i < text.length && !separator(text[i])) i++
            if (i == from) i++
            error(from, i, "无法精确识别“${source.substring(from, i)}”；请检查位数、字符与金额写法")
        }
        if (pending.isNotEmpty()) flushPending()
        if (items.size !in 1..MAX_ITEMS) error(0, source.length, "每批需要1～$MAX_ITEMS 条，当前 ${items.size} 条")
        if (items.sumOf { it.amountJiao.toLong() } > MAX_TOTAL_JIAO) error(0, source.length, "整批金额不能超过100000元")
        val issues = (errors + warnings).sortedWith(compareBy({ it.start }, { it.severity.ordinal }))
        return BatchParseReport(if (errors.isEmpty()) BatchOrder(items) else null, issues)
    }

    fun parse(source: String): BatchOrder {
        val report = inspect(source)
        return report.order ?: throw BatchParseException(report.errors)
    }

    /** Canonical wire input only; never allow a loose text interpretation on B. */
    fun fromCommand(command: String): BatchOrder {
        val parsed = parse(command)
        require(parsed.command == command) { "云端指令并非标准的四位号码-金额格式，已拒绝执行" }
        return parsed
    }
}
