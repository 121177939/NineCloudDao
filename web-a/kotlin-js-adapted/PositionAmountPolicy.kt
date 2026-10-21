package com.example.remotea

/**
 * Amount rules for NEW tasks created on A.
 *
 * Two-position bets accept whole-yuan stakes only (1, 2, 3, 4... yuan).
 * Jiao/fractional-yuan stakes such as 1.1 / 1.5 / 3.1 are rejected.
 * Three- and four-position bets keep the existing exact-jiao support.
 * This rule is intentionally kept out of MixedProtocol.decode/SuiteBet.validate so
 * historical queued records remain readable and are not silently rewritten.
 */
object PositionAmountPolicy {
    fun positionCount(number: String): Int = number.count { it != 'X' }

    fun accepts(positionCount: Int, amountJiao: Int): Boolean = when (positionCount) {
        2 -> amountJiao in 10..1_000_000 && amountJiao % 10 == 0
        3, 4 -> amountJiao in 1..1_000_000
        else -> false
    }

    fun error(positionCount: Int): String = when (positionCount) {
        2 -> "二字定位金额只支持整数元，不支持 1.1、1.5、3.1 等角元/小数金额"
        else -> "金额或定位位数不符合规则"
    }
}
