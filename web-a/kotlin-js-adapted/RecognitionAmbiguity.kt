package com.example.remotea

/**
 * v4.1.1 explicit ambiguity layer.
 *
 * These records never make a betting decision by themselves.  They only describe
 * cases where TWO deterministic interpretations are both legal.  A must choose one
 * before the normal full preview/send path can continue.
 */
data class RecognitionAmbiguityChoice(
    val key: String,
    val title: String,
    val normalized: String,
    val detail: String,
    val combinations: Long,
    val totalJiao: Long
)

data class RecognitionAmbiguity(
    val id: String,
    val type: String,
    val source: String,
    val start: Int,
    val endExclusive: Int,
    val occurrence: Int,
    val explanation: String,
    val choices: List<RecognitionAmbiguityChoice>
)

data class RecognitionAmbiguitySelection(
    val type: String,
    val source: String,
    val occurrence: Int,
    val choiceKey: String
)

/** Per-parse cursor so repeated identical snippets may be answered independently. */
internal class RecognitionAmbiguityChoices(selections: List<RecognitionAmbiguitySelection>) {
    private val byKey = selections.associateBy { Triple(it.type, it.source, it.occurrence) }
    private val nextOccurrence = mutableMapOf<Pair<String, String>, Int>()

    fun next(type: String, source: String): String? {
        val key = type to source
        val occurrence = nextOccurrence[key] ?: 0
        nextOccurrence[key] = occurrence + 1
        return byKey[Triple(type, source, occurrence)]?.choiceKey
    }
}
