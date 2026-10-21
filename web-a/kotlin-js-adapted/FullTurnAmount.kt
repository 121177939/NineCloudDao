package com.example.remotea

/** Full-turn permutations are produced by the target app, NOT expanded into bets here. */
object FullTurnAmount {
    fun multiplier(code: String): Long {
        require(Regex("[0-9X]{4}").matches(code)) { "全转号码格式错误" }
        val divisors = code.groupingBy { it }.eachCount().values.map { count ->
            (1..count).fold(1L) { acc, n -> acc * n }
        }
        return 24L / divisors.fold(1L) { acc, n -> acc * n }
    }
}
