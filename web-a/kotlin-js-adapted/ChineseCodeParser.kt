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

    private val amt = Regex("(?:各打|各|打|[=＝])\\s*(\\d+(?:\\.\\d+)?|)?\\s*(角钱|毛钱|元|块|组|角|毛)?|[,，]\\s*(\\d+(?:\\.\\d+)?)\\s*(元|块|组)")
    private val fullPos = Regex("第([一二三四])位\\s*[:：]\\s*([0-9]{1,10})")
    private val namedPos = Regex("(全|[0-9]{1,10})(头位|百位|十位|尾位|个位|[+＋]?1位|[头百十尾个]+)")
    private val fourComma = Regex("^[0-9]{1,10}[,，][0-9]{1,10}[,，][0-9]{1,10}[,，][0-9]{1,10}$")
    private val dashScatter = Regex("^([0-9X]{4})-(\\d+(?:\\.\\d+)?)$")
    private val scatterCode = Regex("^[0-9X]{4}$")
    private val digitOrX = Regex("[0-9]+|X")
    // A four-slot plus mask is another spelling of X, but "+1位" is an established position alias.
    // Match only standalone four-slot tokens; preserve the original text length/offsets.
    private val plusMask = Regex("(?<![0-9X+])[0-9X+]{4}(?![0-9X+])")
    private val separators = Regex("[，,、。；;\\n\\r]+")

    fun parse(input: String): Result {
        val text = normalizeForOffsets(input)
        val entries = mutableListOf<Entry>()
        val errors = mutableListOf<Problem>()
        var from = 0
        var sawAmount = false
        var previousAmount: Long? = null
        for (m in amt.findAll(text)) {
            val unit = m.groupValues[2].ifBlank { m.groupValues[4] }
            val number = m.groupValues[1].ifBlank { m.groupValues[3] }
            if (number.isBlank() && unit.isBlank()) continue // e.g. ordinary prose containing 各
            val block = text.substring(from, m.range.first)
            val money = toJiao(number, unit)
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
                    parseBlock(block, money, entries, errors)
                }
                sawAmount = true
                previousAmount = money
            }
            from = m.range.last + 1
        }
        val trailing = stripTitle(text.substring(from)).trim(' ', '\n', '\r', '.', '。', ',', '，', '、', ';', '；')
        if (trailing.isNotBlank() && trailing != "五") {
            val singleDash = dashScatter.matchEntire(trailing)
            if (singleDash != null) {
                val jiao = toJiao(singleDash.groupValues[2], "元")
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
            "七子", "七仔", "五子", "五仔", "排五",
            "排列", "子", "七", "五"
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
        return normalizedMasks.replace(Regex("(?<![0-9X-])([0-9]{4})-(\\d{1,3}(?:\\.\\d+)?)(?=\\s|[,，、。；;]|$)"), "$1=$2")
    }

    private fun toJiao(number: String, unit: String): Long? = try {
        val value = if (number.isEmpty()) "1" else number
        val parts = value.split('.')
        require(parts.size in 1..2 && parts.all { it.isNotEmpty() && it.all(Char::isDigit) })
        val frac = parts.getOrElse(1) { "" }
        // Preserve the original JVM BigDecimal.longValueExact behavior without floats.
        require(frac.length <= 12)
        val numerator = (parts[0] + frac).toLong()
        val denominator = ("1" + "0".repeat(frac.length)).toLong()
        val unitTimes = if (unit.startsWith("角") || unit.startsWith("毛")) 1L else 10L
        require(numerator <= Long.MAX_VALUE / unitTimes)
        val product = numerator * unitTimes
        require(product % denominator == 0L)
        (product / denominator).takeIf { it > 0 }
    } catch (_: Exception) { null }

    private fun moneyText(jiao: Long): String = if (jiao % 10L == 0L)
        (jiao / 10L).toString() else "${jiao / 10L}.${jiao % 10L}"

    private fun stripTitle(s: String): String = s
        .replace(Regex("^\\s*(?:排列五|排列|直\\s*[:：]|直选\\s*[:：])\\s*", RegexOption.MULTILINE), "")
        .replace(Regex("^\\s*[一二三四五六七八九十0-9]+\\s*[:：]\\s*$", RegexOption.MULTILINE), "")
        .replace(Regex("^\\s*[:：]\\s*$", RegexOption.MULTILINE), "")

    private fun parseBlock(raw: String, money: Long, out: MutableList<Entry>, errs: MutableList<Problem>) {
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
                commaGroups.forEach { addScatter(it.trim(), money, it.trim(), out) }
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
                    if (components.size == 1) parseUnlabeled(v, money, out, errs)
                    else {
                        // An accidental internal space: '5 X26' is accepted only when merging
                        // makes exactly one 4-character code and no complete code is present.
                        val glued = components.joinToString("")
                        if (scatterCode.matches(glued) && components.none { scatterCode.matches(it) }) {
                            addScatter(glued, money, part, out)
                        } else {
                            components.forEach { parseUnlabeled(it, money, out, errs) }
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

    private fun parseUnlabeled(s: String, money: Long, out: MutableList<Entry>, errs: MutableList<Problem>) {
        if (scatterCode.matches(s)) { addScatter(s, money, s, out); return }
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
