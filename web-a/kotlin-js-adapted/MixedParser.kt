package com.example.remotea

/**
 * Normalize human-readable scatter + 2/3/4-position suites before sending.
 * B continues to receive the verified canonical M1 wire format.
 * A bad or ambiguous segment invalidates the whole batch, never a partial send.
 *
 * v2.0.13: item-level validation errors are mapped back to the exact source span.
 * A single bad item must never paint the entire input red.
 */
data class MixedParseReport(val batch: MixedBatch?, val issues: List<BatchIssue>) {
    val valid: Boolean get() = batch != null && issues.none { it.severity == BatchSeverity.ERROR }
    val errors: List<BatchIssue> get() = issues.filter { it.severity == BatchSeverity.ERROR }
    val warnings: List<BatchIssue> get() = issues.filter { it.severity == BatchSeverity.WARNING }
}

object MixedParser {
    // M1's established execution order is scatter/full-turn first, suites second.
    // Four numeric dot-separated groups are an explicit four-position suite marker.
    private val namedSuiteStart = Regex("(?<![0-9X])(?:[0-9]{1,10}[头百十尾个]|全[头百十尾]|[0-9]{1,10}(?:\\.[0-9]{1,10}){3})")
    // Candidate for a self-contained trailing full-turn-only clause. This is only
    // a boundary finder; FullTurnParser remains the authority and validates the
    // entire suffix before any execution-order normalization is allowed.
    private val trailingFullTurnStart = Regex("(?<![0-9X+])[0-9X+]{4}(?:[ \\t,，、;；。\\r\\n]+[0-9X+]{4})*[ \\t\\r\\n]*全(?:倒|到|转)")

    private fun inspectFullTurnThenSuite(raw: String, suiteAt: Int): MixedParseReport {
        val fullText = raw.substring(0, suiteAt)
        val suiteText = raw.substring(suiteAt)
        val first = FullTurnParser.inspect(fullText)
        if (!first.valid) return first
        // No recursive 全转 parsing in the suite suffix. A subsequent scatter
        // would violate the existing staged execution order, so reject instead.
        if (FullTurnParser.applies(suiteText))
            return MixedParseReport(null, listOf(BatchIssue(suiteAt, raw.length,
                "套码后不支持继续全转；请将套码放在本单最后")))
        val second = inspect(suiteText)
        if (!second.valid) return MixedParseReport(null, second.issues.map { issue ->
            issue.copy(start = issue.start + suiteAt, endExclusive = issue.endExclusive + suiteAt)
        })
        val suiteBatch = second.batch!!
        if (suiteBatch.suites.isEmpty() || suiteBatch.scatter.items.isNotEmpty())
            return MixedParseReport(null, listOf(BatchIssue(suiteAt, raw.length,
                "全转混合订单中的套码必须位于最后，不能包含后续散码")))
        val turnBatch = first.batch!!
        val combined = turnBatch.copy(suites = suiteBatch.suites)
        val issues = first.issues + second.issues.map { issue ->
            issue.copy(start = issue.start + suiteAt, endExclusive = issue.endExclusive + suiteAt)
        }
        return runCatching {
            MixedProtocol.validate(combined)
            check(MixedProtocol.decode(combined.command).command == combined.command) {
                "混合全转/套码传输协议未能无损往返"
            }
            MixedParseReport(combined, issues)
        }.getOrElse { failure -> MixedParseReport(null, issues + BatchIssue(0, raw.length,
            failure.message ?: "混合全转和套码指令校验失败")) }
    }
    /**
     * Explicitly authorized normalization for a suite prefix followed by a final
     * full-turn-only suffix. The suffix is moved into M1's scatter/full-turn stage;
     * suite order, source text and all existing safety gates remain unchanged.
     * Ordinary scatter in the suffix, another earlier full-turn, or any unknown
     * suffix text causes a hard reject rather than a broader reorder.
     */
    private fun inspectSuiteThenTrailingFullTurn(
        raw: String,
        suiteAt: Int,
        turnAt: Int
    ): MixedParseReport {
        fun reject(message: String) = MixedParseReport(null, listOf(BatchIssue(turnAt, raw.length, message)))
        if (turnAt <= suiteAt || turnAt !in 1 until raw.length)
            return reject("全倒尾注位置不明确，整单停止")
        val prefixText = raw.substring(0, turnAt)
        val turnText = raw.substring(turnAt)
        if (FullTurnParser.applies(prefixText))
            return reject("仅允许将单一尾部全倒段提前；混合多个全倒段需人工拆分核对")

        val prefix = inspect(prefixText)
        if (!prefix.valid) return prefix
        val prefixBatch = prefix.batch ?: return reject("套码与全倒无法安全合并，整单停止")
        if (prefixBatch.suites.isEmpty())
            return reject("未找到可供全倒尾注前置的套码，整单停止")

        val tail = FullTurnParser.inspect(turnText)
        if (!tail.valid) return MixedParseReport(null, tail.issues.map { issue ->
            issue.copy(start = issue.start + turnAt, endExclusive = issue.endExclusive + turnAt)
        })
        val tailBatch = tail.batch ?: return reject("全倒尾注解析为空，整单停止")
        if (tailBatch.scatter.items.isEmpty() || tailBatch.turnFlags.size != tailBatch.scatter.items.size ||
            tailBatch.turnFlags.any { !it } || tailBatch.suites.isNotEmpty()) {
            return reject("尾部只能包含明确的全倒/全到/全转指令；普通码或混合内容不自动换序")
        }

        val prefixFlags = prefixBatch.scatter.items.indices.map { index ->
            prefixBatch.turnFlags.getOrElse(index) { false }
        }
        val combined = prefixBatch.copy(
            scatter = BatchOrder(prefixBatch.scatter.items + tailBatch.scatter.items),
            turnFlags = prefixFlags + tailBatch.turnFlags
        )
        val issues = prefix.issues + tail.issues.map { issue ->
            issue.copy(start = issue.start + turnAt, endExclusive = issue.endExclusive + turnAt)
        }
        return runCatching {
            MixedProtocol.validate(combined)
            check(MixedProtocol.decode(combined.command).command == combined.command) {
                "全倒尾注前置后的 M1 指令未能无损往返"
            }
            MixedParseReport(combined, issues)
        }.getOrElse { failure -> MixedParseReport(null, issues + BatchIssue(0, raw.length,
            failure.message ?: "全倒尾注前置后指令校验失败")) }
    }

    // New-task entry ceiling. Only split final FOUR-position scatter entries;
    // old task wire decoding and 2/3-position amounts stay unchanged.
    private fun splitFourPosition(items: List<BatchItem>): List<BatchItem> = buildList {
        items.forEach { item ->
            val isFour = PositionAmountPolicy.positionCount(item.number) == 4
            var remain = item.amountJiao
            if (!isFour || remain <= 500) add(item) else while (remain > 0) {
                val part = minOf(remain, 500)
                add(item.copy(amountJiao = part))
                remain -= part
            }
        }
    }

    private data class Span(val start: Int, val endExclusive: Int)

    /**
     * ChineseCodeParser normalizes with one-character replacements, so offsets remain
     * compatible with the original EditText. Track repeated snippets in source order
     * instead of always highlighting the first occurrence.
     */
    private class SpanLocator(private val raw: String) {
        private val normalized = ChineseCodeParser.normalizeForOffsets(raw)
        private val nextBySnippet = mutableMapOf<String, Int>()

        fun locate(source: String): Span {
            val snippet = ChineseCodeParser.normalizeForOffsets(source.trim())
            if (snippet.isBlank()) return Span(0, 0)
            val from = nextBySnippet[snippet] ?: 0
            var at = normalized.indexOf(snippet, from)
            if (at < 0) at = normalized.indexOf(snippet)
            if (at < 0) return Span(0, 0)
            nextBySnippet[snippet] = at + snippet.length
            return Span(at, (at + snippet.length).coerceAtMost(raw.length))
        }
    }

    fun inspect(raw: String): MixedParseReport {
        if (FullTurnParser.applies(raw)) {
            val suiteStart = namedSuiteStart.find(raw)?.range?.first
            if (suiteStart != null) {
                val trailingTurnAt = trailingFullTurnStart.findAll(raw).lastOrNull()?.range?.first
                if (trailingTurnAt != null && trailingTurnAt > suiteStart)
                    return inspectSuiteThenTrailingFullTurn(raw, suiteStart, trailingTurnAt)
                return inspectFullTurnThenSuite(raw, suiteStart)
            }
            return FullTurnParser.inspect(raw)
        }
        val result = try { ChineseCodeParser.parse(raw) } catch (_: Exception) {
            return MixedParseReport(null, listOf(BatchIssue(0, raw.length, "输入太长或金额超出范围")))
        }
        // Keep the legacy scatter-only grammar as a compatibility path.
        // Prefer the suite-aware parser whenever it finds a suite, even if a legacy
        // scatter expression superficially resembles a dash-separated suite.
        if (result.suites.isEmpty()) {
            val legacy = BatchParser.inspect(raw)
            if (legacy.valid) {
                val legacyIssues = legacy.issues
                    .filter { it.notice != BatchNotice.LOOKALIKE && it.notice != BatchNotice.NOTE }
                    .toMutableList()
                val locator = SpanLocator(raw)
                for (item in legacy.order!!.items) {
                    val positions = PositionAmountPolicy.positionCount(item.number)
                    if (!PositionAmountPolicy.accepts(positions, item.amountJiao)) {
                        val base = locator.locate(item.number)
                        val span = extendAdjacentAmount(raw, base)
                        legacyIssues += BatchIssue(span.start, span.endExclusive,
                            PositionAmountPolicy.error(positions))
                    } else {
                        // Consume this occurrence so repeated identical numbers map correctly.
                        locator.locate(item.number)
                    }
                }
                return MixedParseReport(
                    if (legacyIssues.none { it.severity == BatchSeverity.ERROR })
                        MixedBatch(BatchOrder(splitFourPosition(legacy.order.items)), emptyList()).also {
                            runCatching { MixedProtocol.validate(it) }.getOrElse { problem ->
                                legacyIssues += BatchIssue(0, raw.length, problem.message ?: "拆分后超过任务限制")
                            }
                        }.takeIf { legacyIssues.none { issue -> issue.severity == BatchSeverity.ERROR } }
                        else null,
                    legacyIssues)
            }
        }

        val issues = mutableListOf<BatchIssue>()
        val problemLocator = SpanLocator(raw)
        // Locate parser problems in original input. Unknown/global errors may still span
        // the whole batch, but item-level failures must stay local.
        for (problem in result.problems) {
            val span = problemLocator.locate(problem.source)
            issues += BatchIssue(span.start, span.endExclusive, problem.reason)
        }

        val scattered = mutableListOf<BatchItem>()
        val suites = mutableListOf<SuiteBet>()
        val seenScatter = mutableSetOf<String>()
        val seenSuites = mutableSetOf<String>()
        val entryLocator = SpanLocator(raw)
        for (entry in result.entries) {
            val baseSpan = entryLocator.locate(entry.source)
            val itemSpan = extendAdjacentAmount(raw, baseSpan)
            val amount = entry.amountJiao.takeIf { it in 1L..1_000_000L }?.toInt()
            if (amount == null) {
                issues += BatchIssue(itemSpan.start, itemSpan.endExclusive, "金额超出范围")
                continue
            }
            if (entry.kind == ChineseCodeParser.Kind.SCATTER) {
                val number = entry.canonical.substringBefore('=')
                if (!Regex("[0-9X]{4}").matches(number) || number.count { it == 'X' } > 2) {
                    issues += BatchIssue(itemSpan.start, itemSpan.endExclusive, "号码格式错误")
                    continue
                }
                val positions = PositionAmountPolicy.positionCount(number)
                if (!PositionAmountPolicy.accepts(positions, amount)) {
                    issues += BatchIssue(itemSpan.start, itemSpan.endExclusive,
                        PositionAmountPolicy.error(positions))
                    continue
                }
                if (!seenScatter.add(number)) duplicateIssue(itemSpan, issues)
                scattered += BatchItem(number, amount)
            } else {
                val keys = "HBTW"
                val values = entry.positions.mapKeys { keys[it.key] }
                // WAP preview only: retain the same ChineseCodeParser.Entry.source used to build
                // this suite; wire canonicalText / amount / execution remain unchanged.
                val suite = SuiteBet(values, amount, entry.source)
                if (runCatching { suite.validate() }.isFailure) {
                    issues += BatchIssue(itemSpan.start, itemSpan.endExclusive, "套码格式错误")
                    continue
                }
                if (!PositionAmountPolicy.accepts(suite.mode, amount)) {
                    issues += BatchIssue(itemSpan.start, itemSpan.endExclusive,
                        PositionAmountPolicy.error(suite.mode))
                    continue
                }
                if (!seenSuites.add(suite.canonicalText)) duplicateIssue(itemSpan, issues)
                suites += suite
            }
        }
        val candidate = MixedBatch(BatchOrder(splitFourPosition(scattered)), suites)
        if (issues.none { it.severity == BatchSeverity.ERROR }) {
            runCatching {
                require(candidate.scatter.items.size <= BatchParser.MAX_ITEMS) { "拆分后散码条数超出限制" }
                MixedProtocol.validate(candidate)
                // A must send precisely what B will decode; no fuzzy corrections on B.
                require(MixedProtocol.decode(candidate.command).command == candidate.command)
            }.onFailure { issues += BatchIssue(0, raw.length, it.message ?: "任务超出限制") }
        }
        return MixedParseReport(if (issues.none { it.severity == BatchSeverity.ERROR }) candidate else null, issues)
    }

    /**
     * If the code is immediately followed by its own amount expression, include that
     * expression in the red span. Shared group amounts are not pulled backwards across
     * commas, so a valid neighboring item stays unmarked.
     */
    private fun extendAdjacentAmount(raw: String, base: Span): Span {
        if (base.start !in 0..raw.length || base.endExclusive !in 0..raw.length || base.start >= base.endExclusive) return base
        val tail = raw.substring(base.endExclusive)
        val amount = Regex("^(?:\\s*(?:[-=＝]\\s*\\d+(?:\\.\\d+)?(?:元|块)?|(?:各打|打|各)\\s*\\d*(?:\\.\\d+)?\\s*(?:角钱|毛钱|元|块|组|角|毛)?))")
            .find(tail)?.value ?: return base
        if (amount.isBlank()) return base
        return Span(base.start, (base.endExclusive + amount.length).coerceAtMost(raw.length))
    }

    private fun duplicateIssue(span: Span, issues: MutableList<BatchIssue>) {
        issues += BatchIssue(span.start, span.endExclusive,
            "重复条目已保留", BatchSeverity.WARNING, BatchNotice.DUPLICATE)
    }
}
