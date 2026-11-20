package com.example.remotea

/**
 * v4.1.0 restricted style-adaptation layer.
 * Core amount/scope/position semantics stay in the deterministic parser; cloud rules only adapt writing style.
 * They cannot bypass amount limits, M1 validation, STOP gates or B-side execution checks.
 */
data class RecognitionRuleSpec(
    val id: String,
    val name: String,
    val pattern: String,
    val replacement: String,
    val sourceTemplate: String = "",
    val targetTemplate: String = "",
    val enabled: Boolean = true,
    val ruleType: String = "style",
    val dslVersion: Int = 1,
    val minClientCode: Int = 0
)

object RecognitionRuleTemplate {
    private val token = Regex("\\{(数字|金额)\\}")
    private val numeric = Regex("\\d+(?:\\.\\d+)?")

    /** Compile a template into a whole-line regex. No substring matching is allowed. */
    fun compile(source: String, target: String): Pair<String, String> {
        require(source.isNotBlank() && target.isNotBlank()) { "规则模板不能为空" }
        require(source.length <= 160 && target.length <= 240) { "规则模板过长" }
        val sourceTokens = token.findAll(source).map { it.groupValues[1] }.toList()
        val targetTokens = token.findAll(target).map { it.groupValues[1] }.toList()
        require(sourceTokens.isNotEmpty()) { "规则必须至少包含一个 {数字} 或 {金额}" }
        require(sourceTokens.size <= 8) { "单条规则占位符过多" }
        require(sourceTokens.groupingBy { it }.eachCount() == targetTokens.groupingBy { it }.eachCount()) {
            "标准写法必须完整保留原写法中的所有 {数字}/{金额}"
        }
        require(amountScales(source) == amountScales(target)) {
            "写法适配规则不能改变金额倍率（元/块/组 与 角/毛 不可互换）"
        }

        val used = mutableMapOf<String, MutableList<Int>>()
        var group = 0
        val body = buildString {
            var at = 0
            var previousKind: String? = null
            for (m in token.findAll(source)) {
                append(sourceLiteralPattern(source.substring(at, m.range.first), previousKind))
                group++
                val kind = m.groupValues[1]
                used.getOrPut(kind) { mutableListOf() }.add(group)
                append(if (kind == "数字") "([0-9]{1,10})" else "(\\d+(?:\\.\\d+)?)")
                previousKind = kind
                at = m.range.last + 1
            }
            append(sourceLiteralPattern(source.substring(at), previousKind))
        }
        val cursor = mutableMapOf<String, Int>()
        val replacement = buildString {
            var at = 0
            for (m in token.findAll(target)) {
                append(target.substring(at, m.range.first).replace("$", "\\$"))
                val kind = m.groupValues[1]
                val index = cursor[kind] ?: 0
                val groups = used[kind].orEmpty()
                require(index < groups.size) { "标准写法中的 {$kind} 在原写法中没有对应占位符" }
                append('$').append(groups[index])
                cursor[kind] = index + 1
                at = m.range.last + 1
            }
            append(target.substring(at).replace("$", "\\$"))
        }
        val pattern = "(?m)^$body$"
        Regex(pattern)
        return pattern to replacement
    }

    /**
     * Amount-unit aliases are semantic equivalents already accepted by the strict parser.
     * Yuan-scale aliases (元/块/组) may replace each other; jiao-scale aliases
     * (角钱/毛钱/角/毛) may replace each other. They are never mixed across scales.
     */
    private fun amountScales(template: String): List<Int> = token.findAll(template)
        .filter { it.groupValues[1] == "金额" }
        .map { m ->
            val tail = template.substring(m.range.last + 1).trimStart()
            when {
                tail.startsWith("角钱") || tail.startsWith("毛钱") || tail.startsWith("角") || tail.startsWith("毛") -> 1
                else -> 10 // explicit 元/块/组 and no-unit legacy amounts are yuan-scale
            }
        }.toList()

    private fun sourceLiteralPattern(literal: String, previousKind: String?): String {
        if (previousKind != "金额" || literal.isEmpty()) return Regex.escape(literal)
        val yuanAliases = listOf("元", "块", "组")
        val jiaoAliases = listOf("角钱", "毛钱", "角", "毛")
        val yuan = yuanAliases.firstOrNull { literal.startsWith(it) }
        if (yuan != null) {
            return "(?:元|块|组)" + Regex.escape(literal.substring(yuan.length))
        }
        val jiao = jiaoAliases.firstOrNull { literal.startsWith(it) }
        if (jiao != null) {
            return "(?:角钱|毛钱|角|毛)" + Regex.escape(literal.substring(jiao.length))
        }
        return Regex.escape(literal)
    }

    /**
     * Infer a reusable template from one real failed input and its correct normalized form.
     * Numeric values must be preserved in the same order; the last value after 各/=/每 is treated as amount.
     */
    fun inferFromExample(sourceExample: String, targetExample: String): Pair<String, String> {
        val source = sourceExample.trim()
        val target = targetExample.trim()
        require(source.isNotBlank() && target.isNotBlank()) { "原文和正确结果不能为空" }
        require(source.length <= 160 && target.length <= 240) { "示例过长" }
        val chineseAmount = Regex("[零〇一二两三四五六七八九十百半]+(?:块钱|元|块|角钱|毛钱|角|毛)")
        require(!chineseAmount.containsMatchIn(source)) {
            "中文金额属于核心语义（如五块/两毛），无需新增云端规则；请直接用 v4.1.0 识别"
        }

        val s = numeric.findAll(source).toList()
        val t = numeric.findAll(target).toList()
        require(s.isNotEmpty()) { "原文必须至少包含一个数字" }
        require(s.size <= 8) { "单条规则数字段过多" }

        // Every source number must still exist in the target in the same order. The target
        // may add fixed numeric literals (for example 0123456789 for “全尾”), but may not
        // silently drop or mutate a user-provided number.
        val targetIndexForSource = mutableListOf<Int>()
        var seek = 0
        s.forEachIndexed { i, sm ->
            val found = (seek until t.size).firstOrNull { t[it].value == sm.value }
            require(found != null) { "正确结果必须保留原文数字且顺序不变（第 ${i + 1} 个数字未保留）" }
            targetIndexForSource += found
            seek = found + 1
        }

        val kinds = s.indices.map { i ->
            val tm = t[targetIndexForSource[i]]
            if (isAmountContext(source, s[i]) || isAmountContext(target, tm)) "金额" else "数字"
        }.toMutableList()
        // A decimal is always an amount. If nothing was classified but the final number follows 各/=/每/打, use amount.
        s.indices.forEach { i -> if (s[i].value.contains('.')) kinds[i] = "金额" }
        if (kinds.none { it == "金额" } && s.isNotEmpty()) {
            val last = s.last()
            val prefix = source.substring(0, last.range.first).takeLast(3)
            if (prefix.any { it in "各每=打" }) kinds[kinds.lastIndex] = "金额"
        }

        val sourceTemplate = replaceNumbersWithTokens(source, s, kinds)
        val targetTemplate = replaceSelectedNumbersWithTokens(target, t, targetIndexForSource, kinds)
        val (pattern, replacement) = compile(sourceTemplate, targetTemplate)
        val actual = Regex(pattern).replace(source, replacement)
        require(actual == target) { "无法从该示例安全推导通用规则，请改用更明确的正确结果" }
        return sourceTemplate to targetTemplate
    }

    fun examplePair(sourceTemplate: String, targetTemplate: String): Pair<String, String> {
        val values = sampleValues()
        return fillTemplate(sourceTemplate, values.first, values.second) to
            fillTemplate(targetTemplate, values.first, values.second)
    }

    /** Four generalized samples used before publication, including different digit lengths. */
    fun generalizedPairs(sourceTemplate: String, targetTemplate: String): List<Pair<String, String>> {
        val digitSets = listOf(
            listOf("7", "38", "812", "12678", "45", "9031", "6", "1234567890"),
            listOf("12", "357", "1278", "38", "6", "90", "12345", "8"),
            listOf("812", "357", "12678", "38", "91", "4", "765432", "3"),
            listOf("1", "23", "456", "7890", "5", "67", "89012", "4")
        )
        val amounts = listOf(listOf("1", "1.5", "60", "120"), listOf("2", "0.5", "80", "3"), listOf("60", "120", "1", "2.5"), listOf("5", "20", "0.2", "88"))
        val yuanUnits = listOf("组", "元", "块", "元")
        return digitSets.indices.map { i ->
            val sourceVariant = varyYuanAmountUnit(sourceTemplate, yuanUnits[i])
            fillTemplate(sourceVariant, digitSets[i], amounts[i]) to fillTemplate(targetTemplate, digitSets[i], amounts[i])
        }
    }

    private fun varyYuanAmountUnit(template: String, unit: String): String =
        Regex("\\{金额\\}(元|块|组)").replace(template) { "{金额}$unit" }

    fun hasTemplateToken(text: String): Boolean = token.containsMatchIn(text)

    private fun sampleValues(): Pair<List<String>, List<String>> {
        val digits = listOf("12", "357", "1278", "38", "6", "9031", "45", "8")
        val amounts = listOf("1", "1.5", "60", "120", "2", "0.5", "80", "5")
        return digits to amounts
    }

    private fun fillTemplate(template: String, digits: List<String>, amounts: List<String>): String {
        var di = 0
        var ai = 0
        return token.replace(template) { m ->
            when (m.groupValues[1]) {
                "数字" -> digits.getOrElse(di++) { "7" }
                else -> amounts.getOrElse(ai++) { "1" }
            }
        }
    }

    private fun replaceNumbersWithTokens(text: String, matches: List<MatchResult>, kinds: List<String>): String {
        val out = StringBuilder()
        var at = 0
        matches.forEachIndexed { i, m ->
            out.append(text.substring(at, m.range.first))
            out.append('{').append(kinds[i]).append('}')
            at = m.range.last + 1
        }
        out.append(text.substring(at))
        return out.toString()
    }


    private fun replaceSelectedNumbersWithTokens(
        text: String,
        allMatches: List<MatchResult>,
        selectedIndices: List<Int>,
        kinds: List<String>
    ): String {
        val selected = selectedIndices.withIndex().associate { it.value to it.index }
        val out = StringBuilder()
        var at = 0
        allMatches.forEachIndexed { index, m ->
            out.append(text.substring(at, m.range.first))
            val sourceIndex = selected[index]
            if (sourceIndex == null) out.append(m.value)
            else out.append('{').append(kinds[sourceIndex]).append('}')
            at = m.range.last + 1
        }
        out.append(text.substring(at))
        return out.toString()
    }

    private fun isAmountContext(text: String, m: MatchResult): Boolean {
        if (m.value.contains('.')) return true
        val before = text.substring(0, m.range.first).takeLast(4)
        val after = text.substring(m.range.last + 1).take(4)
        if (before.any { it in "各每=打" }) return true
        if (after.startsWith("元") || after.startsWith("块") || after.startsWith("角") ||
            after.startsWith("组") || after.startsWith("注") || after.startsWith("份")) return true
        return false
    }
}

object RecognitionRuleRuntime {
    const val CLIENT_CODE = 173
    const val SUPPORTED_DSL_VERSION = 1
    const val SUPPORTED_RULE_TYPE = "style"

    private var rules: List<RecognitionRuleSpec> = emptyList()
    var version: Long = 0L
        private set

    // Only complete, known game/title labels may be ignored at the edge. Single Chinese
    // numerals such as “五” are NEVER noise because they may be an amount (五块).
    private val edgeNoiseLabels = listOf(
        "七星彩", "排列五", "七五", "五七", "七星", "七子", "七仔", "五子", "五仔", "排五", "排列"
    ).sortedByDescending { it.length }
    private val edgeNoiseAlt = edgeNoiseLabels.joinToString("|") { Regex.escape(it) }
    private val edgeNoisePrefix = Regex("^\\s*(?:(?:$edgeNoiseAlt)\\s*)*")
    private val edgeNoiseSuffix = Regex("(?:(?:\\s*(?:$edgeNoiseAlt)))*\\s*$")

    fun install(newVersion: Long, newRules: List<RecognitionRuleSpec>) {
        require(newVersion >= 0) { "规则版本无效" }
        require(newRules.size <= 100) { "规则数量超过上限" }
        newRules.filter { it.enabled }.forEach {
            require(it.ruleType == SUPPORTED_RULE_TYPE) { "当前客户端不支持规则类型：${it.ruleType}" }
            require(it.dslVersion <= SUPPORTED_DSL_VERSION) { "规则格式版本过新，请升级 A 端" }
            require(it.minClientCode <= CLIENT_CODE) { "该规则要求更高版本 A 端，请先升级" }
            require(it.pattern.length <= 500 && it.replacement.length <= 600) { "规则过长：${it.name}" }
            Regex(it.pattern)
        }
        rules = newRules.toList()
        version = newVersion
    }

    fun snapshot(): List<RecognitionRuleSpec> = rules.toList()

    /**
     * v4.1.0: each original line may be adapted by AT MOST ONE structural result.
     * Rules are evaluated against the original line in parallel; outputs are never fed
     * into another rule. Conflicting matches fail closed instead of using rule order.
     */
    fun apply(raw: String): String = raw.split('\n').joinToString("\n") { rawLine ->
        val cr = if (rawLine.endsWith('\r')) "\r" else ""
        val line = if (cr.isEmpty()) rawLine else rawLine.dropLast(1)
        val outputs = rules.filter { it.enabled }.mapNotNull { rewriteLineCandidate(line, it) }.distinct()
        require(outputs.size <= 1) { "云端识别规则冲突：同一行存在多个不同解释，已停止识别" }
        (outputs.singleOrNull() ?: line) + cr
    }.also { require(it.length <= 20000) { "规则展开后的输入过长，已拒绝识别" } }

    private fun rewriteLineCandidate(line: String, rule: RecognitionRuleSpec): String? {
        val regex = Regex(rule.pattern)
        if (regex.matches(line)) return regex.replace(line, rule.replacement)

        val prefix = edgeNoisePrefix.find(line)?.value.orEmpty()
        val remaining = line.substring(prefix.length)
        val suffix = edgeNoiseSuffix.find(remaining)?.value.orEmpty()
        if (prefix.isEmpty() && suffix.isEmpty()) return null
        val coreEnd = (remaining.length - suffix.length).coerceAtLeast(0)
        val core = remaining.substring(0, coreEnd)
        if (core.isBlank() || !regex.matches(core)) return null
        return prefix + regex.replace(core, rule.replacement) + suffix
    }

    /** Publish-time generalized rewrite, semantic validity and conflict checks. */
    fun validateForPublish(candidate: List<RecognitionRuleSpec>): String {
        val enabled = candidate.filter { it.enabled }
        var generalized = 0
        var semanticChecks = 0
        val samples = mutableListOf<Pair<RecognitionRuleSpec, Pair<String, String>>>()
        enabled.forEach { rule ->
            check(rule.ruleType == SUPPORTED_RULE_TYPE && rule.dslVersion <= SUPPORTED_DSL_VERSION) {
                "规则“${rule.name}”使用了当前版本不支持的规则类型/格式"
            }
            if (rule.sourceTemplate.isBlank() || rule.targetTemplate.isBlank()) return@forEach
            val pairs = RecognitionRuleTemplate.generalizedPairs(rule.sourceTemplate, rule.targetTemplate)
            pairs.forEach { pair ->
                val regex = Regex(rule.pattern)
                check(regex.matches(pair.first)) { "规则“${rule.name}”无法完整匹配泛化样例：${pair.first}" }
                check(regex.replace(pair.first, rule.replacement) == pair.second) { "规则“${rule.name}”泛化结果错误：${pair.first}" }
                check(regex.replace("前缀${pair.first}", rule.replacement) == "前缀${pair.first}") { "规则“${rule.name}”存在前缀子串误匹配风险" }
                check(regex.replace("${pair.first}后缀", rule.replacement) == "${pair.first}后缀") { "规则“${rule.name}”存在后缀子串误匹配风险" }
                val semantic = MixedParser.inspectCanonical(pair.second)
                check(semantic.valid && semantic.batch != null && semantic.batch.totalJiao > 0L) {
                    "规则“${rule.name}”的标准结果无法通过核心语义解析：${pair.second}"
                }
                samples += rule to pair
                generalized++
                semanticChecks++
            }
        }
        samples.forEach { (_, pair) ->
            val outputs = enabled.mapNotNull { r -> rewriteLineCandidate(pair.first, r) }.distinct()
            check(outputs.size <= 1) { "规则冲突：同一输入“${pair.first}”会得到不同标准化结果" }
        }
        return "$generalized 个泛化样例 + $semanticChecks 个最终语义校验通过；规则不链式执行，未发现冲突"
    }
}
