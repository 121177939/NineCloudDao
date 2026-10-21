package com.example.remotea

internal object Math {
    fun multiplyExact(a: Long, b: Long): Long {
        require(a >= 0L && b >= 0L && (b == 0L || a <= Long.MAX_VALUE / b)) { "金额计算溢出" }
        return a * b
    }
    fun addExact(a: Long, b: Long): Long {
        require(a >= 0 && b >= 0 && a <= Long.MAX_VALUE - b) { "金额计算溢出" }
        return a + b
    }
}
internal object Character {
    fun isSpaceChar(c: Char) = c == '\u3000' || c == '\u00A0' || c == '\u2007' || c == '\u202F'
}
