package com.example.remotea

/**
 * v2.0.38 strict per-paragraph four-position / 全倒 (全到、全转) parser.
 * One operation remains one separate submission; no permutation is expanded here.
 * Only self-contained four-slot-number groups with explicit amounts are accepted.
 * Unrecognized text rejects the WHOLE order. Existing suite grammar remains separate.
 */
object FullTurnParser {
    private val four = Regex("[0-9X]{4}")
    private val amount = Regex("(?:各打|各|打)\\s*([0-9]+(?:\\.[0-9])?)\\s*(?:组|元|块)?|([0-9]+(?:\\.[0-9])?)\\s*(?:组|元|块)")
    private fun moneyText(match: MatchResult): String = match.groupValues[1].ifBlank { match.groupValues[2] }
    private val turnWord = Regex("全(?:倒|到|转)")
    // Keep the established plain numeric scatter shorthand within mixed full-turn input.
    // Do not enable dash shorthand for masked numbers: XX38-05 is suite syntax.
    private val numericDashAmount = Regex("[-=＝]\\s*([0-9]+(?:\\.[0-9])?)\\s*(?:元|块|组)?")
    private val separator = " ,，、;；。\r\n\t"
    const val MAX_SINGLE_JIAO = 500

    private val largeFour = Regex("(?:^|[\\s,，、;；。])([0-9X]{4})\\s*(?:各打|各|打)\\s*([0-9]+(?:\\.[0-9])?)\\s*(?:组|元|块)")
    fun applies(raw: String): Boolean = turnWord.containsMatchIn(raw) || largeFour.findAll(raw).any { match ->
        (ExactAmount.parse(match.groupValues[2]) ?: 0) > MAX_SINGLE_JIAO
    }

    fun inspect(raw: String): MixedParseReport {
        // Match the existing explicit title-noise whitelist. Preserve original
        // UTF-16 source offsets by blanking characters rather than removing them.
        val ignoredTitles = listOf("七星彩", "排列五", "七星", "排列", "七五", "七子", "七仔", "五子", "五仔", "排五")
        val titlePattern = Regex(ignoredTitles.sortedByDescending { it.length }.joinToString("|") { Regex.escape(it) })
        val source = titlePattern.replace(raw) { " ".repeat(it.value.length) }
        val issues = mutableListOf<BatchIssue>()
        val items = mutableListOf<BatchItem>()
        val flags = mutableListOf<Boolean>()
        var pos = 0
        fun skip(): Int { while (pos < source.length && source[pos] in separator) pos++; return pos }
        fun fail(at: Int, why: String) {
            issues += BatchIssue(at.coerceIn(0,source.length), (at + 1).coerceIn(0,source.length), why)
        }
        fun split(code: String, price: Int, turn: Boolean) {
            var remain = price
            while (remain > 0) {
                val current = minOf(remain, MAX_SINGLE_JIAO)
                items += BatchItem(code, current)
                flags += turn
                remain -= current
            }
        }
        while (skip() < source.length && issues.isEmpty()) {
            val begin = pos
            val codes = mutableListOf<String>()
            while (true) {
                val match = four.find(source, pos)?.takeIf { it.range.first == pos }
                if (match == null) break
                val code = match.value
                if (code.count { it == 'X' } > 2) { fail(pos,"只支持二字/三字/四字定位"); break }
                codes += code
                pos = match.range.last + 1
                while (pos < source.length && source[pos] in " 、,，\t") pos++
                if (four.find(source, pos)?.range?.first != pos) break
            }
            if (issues.isNotEmpty()) break
            if (codes.isEmpty()) { fail(begin,"全转格式应从四位号码开始；未知文字禁止忽略"); break }
            while (pos < source.length && source[pos] in " \t") pos++
            // v2.0.39: Full-turn alone is a complete, valid instruction. It must
            // NOT invent a normal bet. A paragraph may also contain plain
            // numeric shorthand such as 1235-1 after a full-turn instruction.
            val standaloneTurn = turnWord.find(source, pos)?.takeIf { it.range.first == pos }
            val initial = if (standaloneTurn == null) amount.find(source, pos)?.takeIf { it.range.first == pos } else null
            val dash = if (standaloneTurn == null && initial == null && codes.size == 1 && codes[0].all(Char::isDigit))
                numericDashAmount.find(source, pos)?.takeIf { it.range.first == pos }
            else null
            val normalMatch = initial ?: dash
            if (standaloneTurn == null && normalMatch == null) { fail(pos,"缺少普通码金额或全转金额（例：各1组 / 全转各1组）"); break }
            val normalJiao: Int? = normalMatch?.let { ExactAmount.parse(moneyText(it)) }
            if (normalMatch != null && normalJiao == null) { fail(pos,"普通码金额必须大于0且最多一位小数"); break }
            if (normalJiao != null && codes.any { code -> !PositionAmountPolicy.accepts(PositionAmountPolicy.positionCount(code), normalJiao) }) {
                fail(begin, "本段含不支持小数金额的二字定位号码")
                break
            }
            if (normalMatch != null) pos = normalMatch.range.last + 1
            val afterNormal = pos
            if (normalMatch != null) skip()
            val turn = standaloneTurn ?: turnWord.find(source,pos)?.takeIf { it.range.first == pos }
            var turnJiao: Int? = null
            if (turn != null) {
                pos = turn.range.last + 1
                while (pos < source.length && source[pos] in " \t") pos++
                val turnAmount = amount.find(source,pos)?.takeIf { it.range.first == pos }
                if (turnAmount == null) { fail(pos,"全倒/全到/全转必须提供明确金额"); break }
                turnJiao = ExactAmount.parse(moneyText(turnAmount))
                if (turnJiao == null) { fail(pos,"全转金额格式错误"); break }
                if (codes.any { code -> !PositionAmountPolicy.accepts(PositionAmountPolicy.positionCount(code), turnJiao) }) {
                    fail(begin, "本段全转含不支持小数金额的二字定位号码")
                    break
                }
                pos = turnAmount.range.last + 1
            } else pos = afterNormal
            // Finish all ordinary codes in this segment, then each full-turn code.
            if (normalJiao != null) codes.forEach { split(it, normalJiao, false) }
            if (turnJiao != null) codes.forEach { split(it, turnJiao, true) }
            if (items.size > BatchParser.MAX_ITEMS) { fail(begin,"执行项超过50条（拆分后计数）"); break }
        }
        if (issues.isEmpty() && items.isEmpty()) fail(0,"没有可识别的四字定位内容")
        val batch = if (issues.isEmpty()) MixedBatch(BatchOrder(items), emptyList(), turnFlags = flags) else null
        if (batch != null) runCatching {
            MixedProtocol.validate(batch)
            check(MixedProtocol.decode(batch.command).command == batch.command) { "发送协议校验不一致" }
        }.onFailure { fail(0,it.message ?: "总金额或指令超限") }
        return MixedParseReport(if (issues.isEmpty()) batch else null, issues)
    }
}
