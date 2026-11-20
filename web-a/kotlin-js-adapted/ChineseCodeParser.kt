package com.example.remotea

/**
 * An Android-independent recognition engine. Money is stored in integer jiao (0.1 CNY).
 * Strict-by-default: ambiguous input is reported as an error, never silently dispatched.
 * Do not treat this module as proof that an external application's order was accepted.
 */
object ChineseCodeParser {
    enum class Kind { SCATTER, SUITE_2, SUITE_3, SUITE_4 }

    data class Entry(
        val kind: Kind,
        val canonical: String,
        val amountJiao: Long,
        val combinations: Long,
        val positions: Map<Int, String> = emptyMap(),
        val source: String = ""
    ) {
        val totalJiao: Long get() = Math.multiplyExact(amountJiao, combinations)
    }
    data class Problem(val source: String, val reason: String)
    data class Result(val entries: List<Entry>, val problems: List<Problem>) {
        val valid: Boolean get() = problems.isEmpty() && entries.isNotEmpty()
        val scatter: List<Entry> get() = entries.filter { it.kind == Kind.SCATTER }
        val suites: List<Entry> get() = entries.filter { it.kind != Kind.SCATTER }
        val totalJiao: Long get() = entries.fold(0L) { a, e -> Math.addExact(a, e.totalJiao) }
    }

    // v4.1.0: amount is a semantic token, not arbitrary text. Chinese numerals are
    // parsed deterministically; an explicit but unknown amount never falls back to 1 yuan.
    private val cnIntegerPattern = "[零〇一二两三四五六七八九十百]+"
    private val cnNumberPattern = "$cnIntegerPattern(?:点[零〇一二三四五六七八九]+)?"
    private val amountExprPattern = "(?:" +
        "$cnIntegerPattern(?:元|块)(?:半|[零〇一二两三四五六七八九](?:角|毛)?)" +
        "|$cnIntegerPattern(?:元|块)$cnIntegerPattern(?:角|毛)" +
        "|\\d+(?:\\.\\d+)?(?:角钱|毛钱|块钱|元|块|组|角|毛)?" +
        "|$cnNumberPattern(?:角钱|毛钱|块钱|元|块|组|角|毛)?" +
        ")"
    private val commaAmountExprPattern = "(?:" +
        "\\d+(?:\\.\\d+)?(?:角钱|毛钱|块钱|元|块|组|角|毛)" +
        "|$cnNumberPattern(?:角钱|毛钱|块钱|元|块|组|角|毛)" +
        ")"
    private val amountBoundary = "(?=\\s|[,，、。；;.\\n\\r]|(?:排列五|排列|七星彩|七星|五子|七子|排五)|$)"
    private val amt = Regex("(?:(?:[=＝]\\s*(?:各打|每个|各|每|打)?|各打|每个|各|每|打)\\s*($amountExprPattern)|[,，]\\s*($commaAmountExprPattern))$amountBoundary")
    private val fullPos = Regex("第([一二三四])位\\s*[:：]\\s*([0-9]{1,10})")
    private val namedPos = Regex("(全|[0-9]{1,10})(头位|百位|十位|尾位|个位|[+＋]?1位|[头百十尾个]+)")
    private val fourComma = Regex("^[0-9]{1,10}[,，][0-9]{1,10}[,，][0-9]{1,10}[,，][0-9]{1,10}$")
    private val dashScatter = Regex("^([0-9X]{4})-(\\d+(?:\\.\\d+)?)$")
    private val scatterCode = Regex("^[0-9X]{4}$")
    private val digitOrX = Regex("[0-9]+|X")
    // A four-slot plus mask is another spelling of X, but "+1位" is an established position alias.
    // Match only standalone four-slot tokens; preserve the original text length/offsets.
    private val plusMask = Regex("(?<![0-9X+])[0-9X+]{4}(?![0-9X+])")
    private val separators = Regex("[，,、。；;.\\n\\r]+")

    fun parse(input: String, ambiguitySelections: List<RecognitionAmbiguitySelection> = emptyList()): Result {
        val text = normalizeForOffsets(input)
        val entries = mutableListOf<Entry>()
        val ambiguityChoices = RecognitionAmbiguityChoices(ambiguitySelections)
        val errors = mutableListOf<Problem>()
        var from = 0
        var sawAmount = false
        var previousAmount: Long? = null
        for (m in amt.findAll(text)) {
            val amountExpression = m.groupValues[1].ifBlank { m.groupValues[2] }
            val block = text.substring(from, m.range.first)
            val money = toJiaoExpression(amountExpression)
            if (money == null) {
                errors += Problem(m.value, "金额无效")
            } else {
                val normalizedBlock = stripTitle(block).trim(' ', '\n', '\r', '.', '。', ',', '，', '、', ';', '；')
                if (normalizedBlock.isBlank() && sawAmount && previousAmount == money) {
                    // Traditional pasted text can repeat the just-used group price, e.g.
                    // "2875打1块，各打1块，5396...". BatchParser already treats the
                    // second amount as a redundant note. Keep the mixed suite parser in parity
                    // instead of turning the harmless repeat into a batch-blocking error.
                } else {
                    parseBlock(block, money, entries, errors, ambiguityChoices)
                }
                sawAmount = true
                previousAmount = money
            }
            from = m.range.last + 1
        }
        val trailing = stripTitle(text.substring(from)).trim(' ', '\n', '\r', '.', '。', ',', '，', '、', ';', '；')
        if (trailing.isNotBlank()) {
            val singleDash = dashScatter.matchEntire(trailing)
            if (singleDash != null) {
                val jiao = decimalToJiao(singleDash.groupValues[2], "元")
                if (jiao != null) {
                    entries += Entry(Kind.SCATTER, singleDash.groupValues[1] + "=" + moneyText(jiao), jiao, 1, source = trailing)
                } else errors += Problem(trailing, "金额无效")
            } else {
                errors += Problem(trailing, "缺少或无法确定金额")
            }
        }
        if (!sawAmount && entries.isEmpty() && errors.isEmpty()) errors += Problem(input, "没有可识别号码")
        return Result(entries, errors)
    }

    /**
     * v4.1.3 preview helper: locate the explicit amount token that governs a source
     * fragment. Offsets stay aligned because normalizeForOffsets preserves UTF-16
     * length for the supported normalizations. Stop at a hard sentence boundary so a
     * later unrelated bet amount is never highlighted.
     */
    internal fun followingAmountSpan(input: String, after: Int): IntRange? {
        val text = normalizeForOffsets(input)
        val safeAfter = after.coerceIn(0, text.length)
        val match = amt.findAll(text, safeAfter).firstOrNull() ?: return null
        val between = text.substring(safeAfter, match.range.first)
        if (between.any { it == '。' || it == '.' || it == '；' || it == ';' || it == '\n' || it == '\r' }) return null
        return match.range
    }

    internal fun normalizeForOffsets(s: String): String {
        val raw0 = s.replace('Ⅹ', 'X').replace('ⅹ', 'X').replace('ｘ', 'X').replace('Ｘ', 'X')
            .replace('x', 'X').replace('*', 'X').replace('＊', 'X')
            .replace('Χ', 'X').replace('χ', 'X').replace('Х', 'X').replace('х', 'X')
            .replace('－', '-').replace('—', '-').replace('–', '-').replace('﹣', '-')
            .replace(Regex("(?<=[0-9X])一(?=[0-9X])"), "-")
            .replace('＝', '=').replace('\t', ' ').replace('\u00A0', ' ')
            .map { c -> if (c in '０'..'９') ('0'.code + c.code - '０'.code).toChar() else c }.joinToString("")
        // v2.0.16: confirmed pasted lottery/game headings and short aliases are formatting noise, not bet content.
        // Replace them with equal-length spaces (rather than deleting) so EditText error
        // offsets remain aligned with the user's original text. Long labels are stripped
        // first, then the short standalone-style labels requested by the user.
        val noiseLabels = listOf(
            "七星彩", "排列五", "七五", "五七", "七星",
            "七子", "七仔", "五子", "五仔", "排五", "排列"
        ).sortedByDescending { it.length }
        val raw = noiseLabels.fold(raw0) { acc, label ->
            acc.replace(label, " ".repeat(label.length))
        }
        // Legacy all-digit 4-character code + hyphen + short amount (e.g. 3849-1)
        // remains a SCATTER entry. IMPORTANT: a 4-slot mask containing X plus a
        // hyphenated digit group is a suite mask, not "code-amount". For example
        // XX38-05 inside "XX38-05，XX49-27各2元" means 38十位 + 05尾位 and
        // shares the following 2-yuan group amount. Do not rewrite X masks here.
        // Long pasted scatter lists often use .. / ... / .... as separators.
        // Keep UTF-16 offsets exactly unchanged; never touch a single decimal
        // dot such as 各1.5元, and never silently strip unknown characters.
        val normalizedDots = raw.replace(Regex("\\.{2,}")) { ",".repeat(it.value.length) }
            .replace(Regex("(?<=[0-9X])\\.(?=[0-9X]{4}(?![0-9X]))"), ",")
        val normalizedMasks = plusMask.replace(normalizedDots) { m ->
            if ('+' in m.value) m.value.replace('+', 'X') else m.value
        }
        // Do NOT rewrite 1649-49 into 1649=49 here. Inside a block such as
        // "1649-49，XX17-49各2元" both codes share the final amount. Legacy
        // single scatter code-amount syntax is handled later only as a fallback.
        return normalizedMasks
    }

    private fun decimalToJiao(number: String, unit: String): Long? = try {
        val parts = number.split('.')
        require(parts.size in 1..2 && parts.all { it.isNotEmpty() && it.all(Char::isDigit) })
        val frac = parts.getOrElse(1) { "" }
        require(frac.length <= 12)
        val numerator = (parts[0] + frac).toLong()
        val denominator = ("1" + "0".repeat(frac.length)).toLong()
        val times = if (unit.startsWith("角") || unit.startsWith("毛")) 1L else 10L
        require(numerator <= Long.MAX_VALUE / times)
        val product = numerator * times
        require(product % denominator == 0L)
        (product / denominator).takeIf { it > 0L }
    } catch (_: Exception) { null }

    private fun chineseDigit(c: Char): Int? = when (c) {
        '零', '〇' -> 0; '一' -> 1; '二', '两' -> 2; '三' -> 3; '四' -> 4
        '五' -> 5; '六' -> 6; '七' -> 7; '八' -> 8; '九' -> 9; else -> null
    }

    private fun chineseInteger(raw: String): Long? {
        if (raw.isBlank()) return null
        if ('十' !in raw && '百' !in raw) {
            val digits = raw.map { chineseDigit(it) ?: return null }
            return digits.joinToString("").toLongOrNull()
        }
        var total = 0L
        var pending: Int? = null
        for (c in raw) {
            when (c) {
                '十' -> { total += (pending ?: 1) * 10L; pending = null }
                '百' -> { total += (pending ?: 1) * 100L; pending = null }
                else -> pending = chineseDigit(c) ?: return null
            }
        }
        total += (pending ?: 0)
        return total.takeIf { it in 0..100000L }
    }

    private fun chineseNumberText(raw: String): String? {
        val parts = raw.split('点')
        if (parts.size > 2) return null
        val whole = chineseInteger(parts[0]) ?: return null
        if (parts.size == 1) return whole.toString()
        val frac = parts[1].map { chineseDigit(it) ?: return null }.joinToString("")
        if (frac.isBlank()) return null
        return "$whole.$frac"
    }

    /** Parse explicit Chinese/Arabic amount expressions into integer jiao, fail-closed. */
    internal fun toJiaoExpression(raw: String): Long? {
        val s = raw.replace(" ", "").replace("块钱", "块").replace("角钱", "角")
            .replace("毛钱", "毛").replace("组", "元")
        if (s.isBlank()) return null

        Regex("^(\\d+(?:\\.\\d+)?)(元|块|角|毛)?$").matchEntire(s)?.let {
            return decimalToJiao(it.groupValues[1], it.groupValues[2].ifBlank { "元" })
        }
        Regex("^(\\d+)(元|块)(半|\\d(?:角|毛)?)$").matchEntire(s)?.let {
            val whole = it.groupValues[1].toLongOrNull() ?: return null
            val tail = it.groupValues[3]
            val jiao = if (tail == "半") 5L else tail.first().digitToInt().toLong()
            return (whole * 10L + jiao).takeIf { v -> v > 0L }
        }
        Regex("^(\\d+)(元|块)(\\d+)(角|毛)$").matchEntire(s)?.let {
            val yuan = it.groupValues[1].toLongOrNull() ?: return null
            val jiao = it.groupValues[3].toLongOrNull() ?: return null
            if (jiao !in 0..9) return null
            return (yuan * 10L + jiao).takeIf { v -> v > 0L }
        }

        Regex("^($cnIntegerPattern)(元|块)($cnIntegerPattern)(角|毛)$").matchEntire(s)?.let {
            val yuan = chineseInteger(it.groupValues[1]) ?: return null
            val jiao = chineseInteger(it.groupValues[3]) ?: return null
            if (jiao !in 0..9) return null
            return (yuan * 10L + jiao).takeIf { v -> v > 0L }
        }
        Regex("^($cnIntegerPattern)(元|块)(半|[零〇一二两三四五六七八九](?:角|毛)?)$").matchEntire(s)?.let {
            val yuan = chineseInteger(it.groupValues[1]) ?: return null
            val tail = it.groupValues[3]
            val jiao = if (tail == "半") 5L else chineseDigit(tail.first())?.toLong() ?: return null
            return (yuan * 10L + jiao).takeIf { v -> v > 0L }
        }
        Regex("^($cnNumberPattern)(元|块|角|毛)?$").matchEntire(s)?.let {
            val number = chineseNumberText(it.groupValues[1]) ?: return null
            return decimalToJiao(number, it.groupValues[2].ifBlank { "元" })
        }
        return null
    }

    private fun moneyText(jiao: Long): String = if (jiao % 10L == 0L)
        (jiao / 10L).toString() else "${jiao / 10L}.${jiao % 10L}"

    private fun stripTitle(s: String): String = s
        .replace(Regex("^\\s*(?:排列五|排列|直\\s*[:：]|直选\\s*[:：])\\s*", RegexOption.MULTILINE), "")
        // Ignore short numbered section labels such as "五:" that users often paste
        // before a block of suites. They are headings, not bet content.
        .replace(Regex("^\\s*[一二三四五六七八九十0-9]+\\s*[:：]\\s*$", RegexOption.MULTILINE), "")
        .replace(Regex("^\\s*[:：]\\s*$", RegexOption.MULTILINE), "")

    private fun parseBlock(raw: String, money: Long, out: MutableList<Entry>, errs: MutableList<Problem>, ambiguityChoices: RecognitionAmbiguityChoices) {
        val text = stripTitle(raw).trim(' ', '\n', '\r', '.', '。', ',', '，', '、', ';', '；')
        if (text.isBlank()) {
            errs += Problem(raw, "金额前缺少号码")
            return
        }
        // A multi-line set of 第一位...第四位 fields belongs to one suite.
        val fullMatches = fullPos.findAll(text).toList()
        if (fullMatches.isNotEmpty()) {
            val remainder = fullPos.replace(text, "").replace(separators, "").trim()
            if (remainder.isNotBlank()) {
                errs += Problem(raw.trim(), "位置块包含无法识别的文字")
                return
            }
            val map = linkedMapOf<Int, String>()
            for (m in fullMatches) {
                val index = "一二三四".indexOf(m.groupValues[1])
                if (index in map) { errs += Problem(raw.trim(), "重复位置"); return }
                map[index] = m.groupValues[2]
            }
            addSuite(map, money, raw.trim(), out, errs)
            return
        }
        // Named position fragments can also be pasted on separate lines, e.g.
        // "1234头\n1234尾各1块". If the whole amount block consists only of
        // 2..4 unique named positions, keep them as ONE suite before line splitting.
        // If positions repeat, leave the old line-by-line path intact so two complete
        // suites sharing one amount are not accidentally merged.
        val blockNamed = namedPos.findAll(text).toList()
        if (blockNamed.isNotEmpty()) {
            val remainder = namedPos.replace(text, "").replace(separators, "").trim()
            val positionTags = blockNamed.flatMap { positionIndices(it.groupValues[2]) }
            if (remainder.isBlank() && positionTags.size in 2..4 && positionTags.toSet().size == positionTags.size) {
                parseNamed(text, money, out, errs)
                return
            }
        }
        for (line in text.split(Regex("[\\n\\r；;。]+"))) {
            val r = line.trim(' ', '，', ',', '、', '.')
            if (r.isBlank()) continue
            // Exactly four comma-separated FOUR-DIGIT codes are four scatter bets,
            // not a four-position suite. This legacy writing is common in pasted lists.
            // Check it before the generic four-position comma syntax.
            // Exactly FOUR numeric dot groups are the existing four-position suite
            // syntax with a different separator, not decimal prices or short scatters.
            // Only parse inside an already separately-priced block; no guessing of
            // two-digit/three-digit padding or changing the amount policy.
            if (r.matches(Regex("[0-9]{1,10}(?:\\.[0-9]{1,10}){3}"))) {
                addSuite(r.split('.').withIndex().associate { it.index to it.value }, money, r, out, errs)
                continue
            }
            val commaGroups = r.split(',', '，')
            if (commaGroups.size == 4 && commaGroups.all { scatterCode.matches(it.trim()) }) {
                val suiteMeaningLegal = commaGroups.all { g -> val d = g.trim(); d.toSet().size == d.length }
                val decision = if (suiteMeaningLegal) ambiguityChoices.next("four_scatter_or_position", r) else null
                if (decision == "four_position") {
                    addSuite(commaGroups.withIndex().associate { it.index to it.value.trim() }, money, r, out, errs)
                } else {
                    commaGroups.forEach { addScatter(it.trim(), money, it.trim(), out) }
                }
                continue
            }
            // Other exactly-four unsigned digit groups remain the compact four-position suite syntax.
            if (fourComma.matches(r)) {
                addSuite(commaGroups.withIndex().associate { it.index to it.value }, money, r, out, errs)
                continue
            }
            // ordinary text may contain several codes separated by Chinese commas
            val parts = r.split(Regex("[，,、]+"))
            for (part in parts) {
                val v = part.trim()
                if (v.isBlank()) continue
                if (v.contains('头') || v.contains('百') || v.contains('十') || v.contains('尾') || v.contains('个')) {
                    parseNamed(part, money, out, errs)
                } else {
                    val components = v.split(Regex("\\s+"))
                    if (components.size == 1) parseUnlabeled(v, money, out, errs, ambiguityChoices)
                    else {
                        // An accidental internal space: '5 X26' is accepted only when merging
                        // makes exactly one 4-character code and no complete code is present.
                        val glued = components.joinToString("")
                        if (scatterCode.matches(glued) && components.none { scatterCode.matches(it) }) {
                            addScatter(glued, money, part, out)
                        } else {
                            components.forEach { parseUnlabeled(it, money, out, errs, ambiguityChoices) }
                        }
                    }
                }
            }
        }
    }

    private fun parseNamed(raw: String, money: Long, out: MutableList<Entry>, errs: MutableList<Problem>) {
        // Allow neighboring named groups with optional spaces. Multiple identical suites
        // separated by a comma are split by parseBlock and remain distinct.
        // "123头45尾二=5": "二" explicitly labels a two-position suite, not a
        // third position or part of the wager amount. Keep the original source
        // unchanged for provenance and only allow this suffix on EXACTLY two positions.
        val twoPositionLabel = raw.trimEnd().endsWith("二")
        val body = if (twoPositionLabel) raw.trimEnd().dropLast(1) else raw
        val matches = namedPos.findAll(body).toList()
        val remainder = namedPos.replace(body, "").trim()
        if (remainder.isNotBlank() || matches.isEmpty()) {
            errs += Problem(raw.trim(), "套码位置格式有误")
            return
        }
        val map = linkedMapOf<Int, String>()
        for (m in matches) {
            val digits = if (m.groupValues[1] == "全") "0123456789" else m.groupValues[1]
            val indices = positionIndices(m.groupValues[2])
            if (indices.isEmpty()) {
                errs += Problem(raw.trim(), "位置重复或不合法")
                return
            }
            for (index in indices) {
                if (map.containsKey(index)) {
                    errs += Problem(raw.trim(), "位置重复或不合法")
                    return
                }
                map[index] = digits
            }
        }
        if (twoPositionLabel && map.size != 2) {
            errs += Problem(raw.trim(), "二定位标记必须对应恰好两个位置")
            return
        }
        // v4.0.0 confirmed shorthand: a single explicit head means that head + full tail.
        // Example: 4头各120 / 0头各60. No other single-position shorthand is guessed.
        if (!twoPositionLabel && map.size == 1 && map.containsKey(0)) map[3] = "0123456789"
        addSuite(map, money, raw.trim(), out, errs)
    }

    private fun positionIndices(tag: String): List<Int> =
        if (tag.length > 1 && tag.all { it in "头百十尾个" }) {
            tag.mapNotNull { positionIndex(it.toString()) }
        } else listOfNotNull(positionIndex(tag))

    private fun positionIndex(tag: String): Int? = when (tag) {
        "头", "头位" -> 0
        "百", "百位" -> 1
        "十", "十位", "1位", "+1位", "＋1位" -> 2
        "尾", "尾位", "个", "个位" -> 3
        else -> null
    }

    private fun parseUnlabeled(s: String, money: Long, out: MutableList<Entry>, errs: MutableList<Problem>, ambiguityChoices: RecognitionAmbiguityChoices? = null) {
        if (scatterCode.matches(s)) { addScatter(s, money, s, out); return }
        val dashAmbiguous = Regex("^([0-9]{4})-([0-9]{1,10})$").matchEntire(s)
        if (dashAmbiguous != null) {
            val internalAmount = decimalToJiao(dashAmbiguous.groupValues[2], "元")
            val scatterLegal = internalAmount != null && internalAmount <= Int.MAX_VALUE &&
                PositionAmountPolicy.accepts(4, internalAmount.toInt())
            val suiteLegal = money <= Int.MAX_VALUE && PositionAmountPolicy.accepts(2, money.toInt())
            val decision = if (scatterLegal && suiteLegal) ambiguityChoices?.next("dash_amount_or_head_tail", s) else null
            if (decision == "scatter_amount" || (decision == null && scatterLegal && !suiteLegal)) {
                if (!scatterLegal || internalAmount == null) errs += Problem(s, "金额无效")
                else addScatter(dashAmbiguous.groupValues[1], internalAmount, s, out)
                return
            }
        }
        // 4-part numeric hyphen groups: head / hundred / ten / tail.
        val numeric = s.split('-')
        if (numeric.size == 4 && numeric.all { it.matches(Regex("[0-9]{1,10}")) }) {
            addSuite(numeric.withIndex().associate { it.index to it.value }, money, s, out, errs)
            return
        }
        // Two numeric groups joined by a hyphen mean head + tail.
        if (numeric.size == 2 && numeric.all { it.matches(Regex("[0-9]{1,10}")) }) {
            addSuite(mapOf(0 to numeric[0], 3 to numeric[1]), money, s, out, errs)
            return
        }
        // Mask form: X is a blank slot, hyphen is only a visual separator.
        // e.g. 0-16XX -> 0 | 16 | X | X ; 8X249-5 -> 8 | X | 249 | 5.
        if (s.contains('X') || s.contains('-')) {
            val compact = s.replace("-", "")
            if (compact.matches(Regex("[0-9X]+"))) {
                val tokens = digitOrX.findAll(s).map { it.value }.toList()
                if (tokens.size == 4 && tokens.any { it == "X" }) {
                    val map = tokens.withIndex().filter { it.value != "X" }.associate { it.index to it.value }
                    addSuite(map, money, s, out, errs)
                    return
                }
            }
        }
        errs += Problem(s, "号码格式错误")
    }


    /**
     * Find only cases where more than one already-supported deterministic meaning is legal.
     * v4.1.1 deliberately keeps this list narrow; ordinary unknown input remains a hard failure.
     */
    fun findAmbiguities(input: String): List<RecognitionAmbiguity> {
        val text = normalizeForOffsets(input)
        val result = mutableListOf<RecognitionAmbiguity>()
        val occurrence = mutableMapOf<Pair<String, String>, Int>()
        var from = 0

        fun nextOccurrence(type: String, source: String): Int {
            val key = type to source
            val n = occurrence[key] ?: 0
            occurrence[key] = n + 1
            return n
        }
        fun uniqueDigits(value: String): Boolean = value.isNotBlank() && value.all { it.isDigit() } && value.toSet().size == value.length
        fun moneyLabel(jiao: Long): String = if (jiao % 10L == 0L) "${jiao / 10L}元" else "${jiao / 10L}.${jiao % 10L}元"

        for (m in amt.findAll(text)) {
            val amountExpression = m.groupValues[1].ifBlank { m.groupValues[2] }
            val sharedMoney = toJiaoExpression(amountExpression)
            if (sharedMoney != null) {
                val block = text.substring(from, m.range.first)
                // Scan comma/line-separated individual clauses for 4-digit-number + dash + digits.
                val clauseRegex = Regex("[^，,、。；;.\\n\\r]+")
                for (cm in clauseRegex.findAll(block)) {
                    val rawClause = cm.value
                    val leading = rawClause.indexOfFirst { !it.isWhitespace() }.let { if (it < 0) 0 else it }
                    val trailing = rawClause.indexOfLast { !it.isWhitespace() }.let { if (it < 0) rawClause.length - 1 else it }
                    val clause = rawClause.substring(leading, trailing + 1)
                    val dm = Regex("^([0-9]{4})-([0-9]{1,10})$").matchEntire(clause) ?: continue
                    val head = dm.groupValues[1]
                    val tail = dm.groupValues[2]
                    if (!uniqueDigits(head) || !uniqueDigits(tail)) continue
                    val internalMoney = decimalToJiao(tail, "元") ?: continue
                    val scatterLegal = internalMoney <= Int.MAX_VALUE && PositionAmountPolicy.accepts(4, internalMoney.toInt())
                    val suiteLegal = sharedMoney <= Int.MAX_VALUE && PositionAmountPolicy.accepts(2, sharedMoney.toInt())
                    if (!scatterLegal || !suiteLegal) continue
                    val combos = head.length.toLong() * tail.length.toLong()
                    val globalStart = from + cm.range.first + leading
                    val globalEnd = globalStart + clause.length
                    val occ = nextOccurrence("dash_amount_or_head_tail", clause)
                    result += RecognitionAmbiguity(
                        id = "dash:$globalStart:$globalEnd",
                        type = "dash_amount_or_head_tail",
                        source = clause,
                        start = globalStart,
                        endExclusive = globalEnd,
                        occurrence = occ,
                        explanation = "“号码-数字”既可能是号码金额，也可能是头尾二定位并继承本段金额。",
                        choices = listOf(
                            RecognitionAmbiguityChoice(
                                key = "scatter_amount",
                                title = "号码金额（散码）",
                                normalized = "$head 各${moneyLabel(internalMoney)}",
                                detail = "1 个独立号码 · 本项 ${moneyLabel(internalMoney)}",
                                combinations = 1,
                                totalJiao = internalMoney
                            ),
                            RecognitionAmbiguityChoice(
                                key = "head_tail_shared",
                                title = "头尾二定位（套码）",
                                normalized = "${head}头${tail}尾，各${moneyLabel(sharedMoney)}",
                                detail = "$combos 组 × ${moneyLabel(sharedMoney)} · 本项 ${moneyLabel(sharedMoney * combos)}",
                                combinations = combos,
                                totalJiao = sharedMoney * combos
                            )
                        )
                    )
                }

                // Exactly four comma-separated four-digit codes may be either four scatters or one 4-position suite.
                val lineRegex = Regex("[^。；;.\\n\\r]+")
                for (lm in lineRegex.findAll(block)) {
                    val cleanLine = lm.value.trim().trim('，', ',', '、').trim()
                    val groups = cleanLine.split(',', '，').map { it.trim() }
                    if (groups.size != 4 || groups.any { !scatterCode.matches(it) }) continue
                    if (groups.any { !uniqueDigits(it) }) continue // suite meaning would be illegal
                    val localStart = lm.value.indexOf(cleanLine).takeIf { it >= 0 } ?: continue
                    val lineStart = from + lm.range.first + localStart
                    val lineEnd = lineStart + cleanLine.length
                    val occ = nextOccurrence("four_scatter_or_position", cleanLine)
                    val combos = groups.fold(1L) { a, g -> Math.multiplyExact(a, g.length.toLong()) }
                    result += RecognitionAmbiguity(
                        id = "four:$lineStart:$lineEnd",
                        type = "four_scatter_or_position",
                        source = cleanLine,
                        start = lineStart,
                        endExclusive = lineEnd,
                        occurrence = occ,
                        explanation = "刚好四组四位数字，既可能是 4 个独立号码，也可能分别代表头/百/十/尾。",
                        choices = listOf(
                            RecognitionAmbiguityChoice(
                                key = "four_scatter",
                                title = "4 个独立号码",
                                normalized = groups.joinToString("、") + "，各${moneyLabel(sharedMoney)}",
                                detail = "4 个号码 × ${moneyLabel(sharedMoney)} · 合计 ${moneyLabel(sharedMoney * 4L)}",
                                combinations = 4,
                                totalJiao = sharedMoney * 4L
                            ),
                            RecognitionAmbiguityChoice(
                                key = "four_position",
                                title = "四定位",
                                normalized = "${groups[0]}头${groups[1]}百${groups[2]}十${groups[3]}尾，各${moneyLabel(sharedMoney)}",
                                detail = "$combos 组 × ${moneyLabel(sharedMoney)} · 合计 ${moneyLabel(sharedMoney * combos)}",
                                combinations = combos,
                                totalJiao = sharedMoney * combos
                            )
                        )
                    )
                }
            }
            from = m.range.last + 1
        }
        return result.distinctBy { listOf(it.type, it.start, it.endExclusive, it.source) }
            .sortedBy { it.start }
    }

    private fun addScatter(code: String, amount: Long, source: String, out: MutableList<Entry>) {
        out += Entry(Kind.SCATTER, "$code=${moneyText(amount)}", amount, 1, source = source)
    }

    private fun addSuite(positions: Map<Int, String>, money: Long, source: String,
                         out: MutableList<Entry>, errs: MutableList<Problem>) {
        if (positions.size !in 2..4 || positions.keys.any { it !in 0..3 }) {
            errs += Problem(source, "套码必须指定2～4个不同位置"); return
        }
        val sorted = positions.toList().sortedBy { it.first }.toMap()
        if (sorted.values.any { it.length !in 1..10 || it.any { c -> c !in '0'..'9' } || it.toSet().size != it.length }) {
            errs += Problem(source, "同一位置数字必须是1～10个不同数字"); return
        }
        val positionsName = listOf("头", "百", "十", "尾")
        var combinations = 1L
        for (v in sorted.values) combinations = Math.multiplyExact(combinations, v.length.toLong())
        val normal = sorted.entries.joinToString("") { (idx, digits) -> digits + positionsName[idx] } + "=${moneyText(money)}"
        val kind = when (positions.size) { 2 -> Kind.SUITE_2; 3 -> Kind.SUITE_3; else -> Kind.SUITE_4 }
        out += Entry(kind, normal, money, combinations, sorted, source)
    }
}
