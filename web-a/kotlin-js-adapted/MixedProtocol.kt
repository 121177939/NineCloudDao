package com.example.remotea

/** Screenshot plan is encoded per task; legacy M1 commands keep their ORIGINAL split mode. */
enum class ScreenshotMode(val wireValue: String) {
    LEGACY(""), // old v0.9.15 task: scatter receipt first + suite log evidence
    COMBINED("0"), // v2.0.6 existing task: combine after both stages
    SPLIT("1"), // v2.0.6 existing tasks: optional split mode
    ROUTED("2"), // v2.0.7 queued jobs: scatter photo (if any), then verified suite LOG images
    ROUTED_RECEIPT("3"), // v2.0.8 queued jobs retain their original two-stage capture plan
    UNIFIED_HOME("4") // v2.0.9 unchecked: finish scatter and suites, ONE photo from scatter home page
}
data class SuiteBet(val digits: Map<Char, String>, val amountJiao: Int, val sourceText: String = "") {
    val mode: Int get() = digits.size
    val expectedCount: Int get() = digits.values.fold(1) { acc, value -> acc * value.length }
    val totalJiao: Long get() = expectedCount.toLong() * amountJiao
    val canonicalText: String get() = buildString {
        for ((key, label) in listOf('H' to "头", 'B' to "百", 'T' to "十", 'W' to "尾")) {
            digits[key]?.let { append(it).append(label) }
        }
        append('=').append(ExactAmount.format(amountJiao))
    }
    val previewText: String get() = sourceText.ifBlank { canonicalText }
    fun validate() {
        require(mode in 2..4 && digits.keys.all { it in "HBTW" }) { "只支持二字定/三字定/四字定" }
        require(amountJiao in 1..1_000_000) { "套码金额超出允许范围" }
        for (value in digits.values) {
            require(value.length in 1..10 && value.all { it in '0'..'9' } && value.toSet().size == value.length) {
                "每个位置须有1～10个不重复数字，原样保留前导0"
            }
        }
    }
}

data class MixedBatch(val scatter: BatchOrder, val suites: List<SuiteBet>,
                      val screenshotMode: ScreenshotMode = ScreenshotMode.LEGACY,
                      val convertOdds: Boolean = false,
                      val turnFlags: List<Boolean> = emptyList()) {
    val expectedSuiteCount: Long get() = suites.sumOf { it.expectedCount.toLong() }
    val scatterJiao: Long get() = scatter.items.withIndex().sumOf { (index, it) ->
        if (turnFlags.getOrElse(index) { false }) 0L else it.amountJiao.toLong()
    }
    val turnJiao: Long get() = scatter.items.withIndex().sumOf { (index, it) ->
        if (turnFlags.getOrElse(index) { false }) it.amountJiao.toLong() * FullTurnAmount.multiplier(it.number) else 0L
    }
    val turnCount: Int get() = turnFlags.count { it }
    val suitesJiao: Long get() = suites.sumOf { it.totalJiao }
    val totalJiao: Long get() = scatterJiao + turnJiao + suitesJiao
    val totalLines: Int get() = scatter.items.size + suites.size
    /** Empty mode is legacy; encoding does not introduce unrelated regressions. */
    val command: String get() = if (suites.isEmpty() && !convertOdds && !turnFlags.any { it }) scatter.command else buildString {
        append("M1|S=").append(scatter.command).append("|T=")
        append(suites.joinToString(";") { bet ->
            (listOf(bet.mode.toString()) + "HBTW".map { bet.digits[it] ?: "_" } +
                ExactAmount.format(bet.amountJiao)).joinToString(",")
        })
        // The v2.0.39 decoder reads R before F. When mixed suites and 全转
        // coexist, serialize R first; pure 全转 and historical M1 stay identical.
        if (suites.isNotEmpty() && screenshotMode != ScreenshotMode.LEGACY) append("|R=").append(screenshotMode.wireValue)
        if (turnFlags.any { it }) append("|F=").append(turnFlags.joinToString("") { if (it) "1" else "0" })
        if (convertOdds) append("|O=1")
    }
}

object MixedProtocol {
    const val MAX_SUITES = 50
    const val MAX_COMMAND = 8000
    const val MAX_TOTAL_JIAO = 1_000_000L // 100000 yuan, before per-device limits
    fun displayJiao(value: Long): String = if (value % 10L == 0L) "${value / 10L}"
        else "${value / 10L}.${value % 10L}"
    fun validate(batch: MixedBatch) {
        require(batch.totalLines in 1..100 && batch.suites.size <= MAX_SUITES) { "一批最多50条散码+50条套码" }
        batch.suites.forEach { it.validate() }
        require(batch.turnFlags.isEmpty() || batch.turnFlags.size == batch.scatter.items.size) { "全转标志与执行项数量不符" }
        // v2.0.40: scatter/full-turn FIRST, suites AFTER, with the existing
        // B-stage order; no suite-before-scatter reorder is ever allowed.
        batch.scatter.items.forEachIndexed { index, item ->
            if (batch.turnFlags.getOrElse(index) { false }) {
                require(Regex("[0-9X]{4}").matches(item.number) && item.number.count { it == 'X' } <= 2 &&
                    item.amountJiao in 1..500 &&
                    (item.number.count { it == 'X' } != 2 || item.amountJiao % 10 == 0)) { "全转号码/单笔金额错误" }
            }
        }
        require(batch.suites.isNotEmpty() || batch.screenshotMode == ScreenshotMode.LEGACY) { "纯散码必须保持原始截图方式" }
        require(batch.totalJiao in 1..MAX_TOTAL_JIAO) { "单批预计金额不得超过100000元" }
        require(batch.command.length <= MAX_COMMAND) { "云端指令太长" }
    }
    /** Strictly canonical, no unknown delimiters, duplicate-position tricks or fuzzy decoding. */
    fun decode(value: String): MixedBatch {
        if (!value.startsWith("M1|")) {
            val result = MixedBatch(BatchParser.fromCommand(value), emptyList())
            validate(result)
            return result
        }
        require(value.length <= MAX_COMMAND && value.startsWith("M1|S=")) { "非标准混合指令" }
        val components = value.substring(5).split("|T=")
        require(components.size == 2 && components[1].isNotBlank()) { "M1 必须包含套码或显式转换赔率标记" }
        val scatter = if (components[0].isBlank()) BatchOrder(emptyList()) else BatchParser.fromCommand(components[0])
        val oddsParts = components[1].split("|O=")
        require(oddsParts.size in 1..2 && (oddsParts.size == 1 || oddsParts[1] == "1")) { "赔率模式字段不合法或重复" }
        val convertOdds = oddsParts.size == 2
        val flagParts = oddsParts[0].split("|F=")
        require(flagParts.size in 1..2) { "全转字段重复" }
        val suffix = flagParts[0].split("|R=")
        require(suffix.size in 1..2) { "截图模式字段重复或不合法" }
        val mode = when (suffix.getOrNull(1)) {
            null -> ScreenshotMode.LEGACY // do NOT change execution of existing pending tasks
            "0" -> ScreenshotMode.COMBINED
            "1" -> ScreenshotMode.SPLIT
            "2" -> ScreenshotMode.ROUTED
            "3" -> ScreenshotMode.ROUTED_RECEIPT
            "4" -> ScreenshotMode.UNIFIED_HOME
            else -> error("未知截图模式：拒绝执行")
        }
        val turnFlags = if (flagParts.size == 2) {
            require(flagParts[1].isNotBlank() && flagParts[1].all { it == '0' || it == '1' }) { "全转字段格式错误" }
            require(flagParts[1].length == scatter.items.size && flagParts[1].contains('1')) { "全转位数不符" }
            flagParts[1].map { it == '1' }
        } else emptyList()
        val suiteRows = if (suffix[0].isBlank()) emptyList() else suffix[0].split(';')
        require(suiteRows.size <= MAX_SUITES) { "套码条目数量无效" }
        require(suiteRows.isNotEmpty() || ((convertOdds || turnFlags.any { it }) && scatter.items.isNotEmpty() && mode == ScreenshotMode.LEGACY)) {
            "纯散码 M1 包装仅允许显式转换赔率，禁止空套码或截图模式伪装"
        }
        val suites = suiteRows.map { row ->
            val fields = row.split(',')
            require(fields.size == 6) { "套码传输字段不完整" }
            val map = linkedMapOf<Char, String>()
            "HBTW".forEachIndexed { index, key ->
                val v = fields[index + 1]
                if (v != "_") map[key] = v
            }
            val price = ExactAmount.parse(fields[5]) ?: error("非法套码金额")
            SuiteBet(map, price).also {
                it.validate()
                require(fields[0] == it.mode.toString()) { "套码模式和位置数量不符" }
            }
        }
        return MixedBatch(scatter, suites, mode, convertOdds, turnFlags).also {
            validate(it)
            require(it.command == value) { "指令非标准格式，不允许模糊纠正" }
        }
    }
}
