package app.subspace.core

/** Release version numbers such as "1.2.0" or GitHub tags such as "v1.2.0" (same rules as iPhone). */
object AppVersion {
    fun normalized(tag: String): String = tag.trim().removePrefix("v").removePrefix("V")
    private fun parts(version: String): List<Int> =
        normalized(version).substringBefore("-").split(".").map { it.toIntOrNull() ?: 0 }
    /** Whether [candidate] is a later release than [current] (1.10.0 > 1.9.9; 1.2 == 1.2.0). */
    fun isNewer(candidate: String, current: String): Boolean {
        val a = parts(candidate); val b = parts(current)
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }; val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return false
    }
}
