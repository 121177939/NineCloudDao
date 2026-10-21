package com.example.remotea

/**
 * v0.9.18: Convert exactly one previewed suite into independent scatter entries.
 * This is intentionally a local A-side edit, not a new B/cloud wire format.
 * The normal per-batch count and money guards apply before changing input.
 */
object SuiteToScatter {
    /** Position order is fixed: 头(H), 百(B), 十(T), 尾(W). Missing positions are X. */
    fun expand(suite: SuiteBet): List<BatchItem> {
        suite.validate()
        require(suite.expectedCount <= BatchParser.MAX_ITEMS) {
            "此条套码展开为 ${suite.expectedCount} 条，超过散码每批最多 ${BatchParser.MAX_ITEMS} 条的上限"
        }
        val code = CharArray(4) { 'X' }
        val result = ArrayList<BatchItem>(suite.expectedCount)
        fun generate(position: Int) {
            if (position == 4) {
                result += BatchItem(code.concatToString(), suite.amountJiao)
                return
            }
            val digits = suite.digits["HBTW"[position]]
            if (digits == null) {
                code[position] = 'X'
                generate(position + 1)
            } else {
                for (digit in digits) {
                    code[position] = digit
                    generate(position + 1)
                }
            }
        }
        generate(0)
        check(result.size == suite.expectedCount)
        return result
    }

    fun convert(batch: MixedBatch, suiteIndex: Int): MixedBatch {
        require(suiteIndex in batch.suites.indices) { "该条套码已变化，请重新识别" }
        val selected = batch.suites[suiteIndex]
        val newScatterCount = batch.scatter.items.size.toLong() + selected.expectedCount.toLong()
        require(newScatterCount <= BatchParser.MAX_ITEMS) {
            "转换后散码共 $newScatterCount 条，超过每批 ${BatchParser.MAX_ITEMS} 条上限；请分批处理"
        }
        val converted = expand(selected)
        val updated = batch.copy(
            scatter = BatchOrder(batch.scatter.items + converted),
            suites = batch.suites.filterIndexed { index, _ -> index != suiteIndex }
        )
        MixedProtocol.validate(updated)
        check(updated.totalJiao == batch.totalJiao) { "转换后金额变化，已阻止" }
        check(updated.scatterJiao == batch.scatterJiao + selected.totalJiao) { "散码金额不一致" }
        check(updated.expectedSuiteCount == batch.expectedSuiteCount - selected.expectedCount) { "套码笔数不一致" }
        check(MixedProtocol.decode(updated.command).command == updated.command)
        return updated
    }

    /** Use explicit independent prices so edits remain reviewable in the input field. */
    fun editableText(batch: MixedBatch): String =
        (batch.scatter.items.map { "${it.number}=${it.amountText}元" } +
         batch.suites.map { "${it.canonicalText}元" }).joinToString("\n")

    /** Re-run the exact same strict parser as the Send action; refuse partial rewrites. */
    fun convertAndVerify(batch: MixedBatch, suiteIndex: Int): Pair<MixedBatch, String> {
        val result = convert(batch, suiteIndex)
        val text = editableText(result)
        val reparsed = MixedParser.inspect(text)
        require(reparsed.valid && reparsed.batch?.command == result.command) {
            "转换后重新识别未通过，输入保持原样；请人工检查"
        }
        return result to text
    }
}
