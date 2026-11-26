package app.subspace.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = Color(0xFFB099FF), onPrimary = Color(0xFF1E1240),
    primaryContainer = Color(0xFF3A2A73), onPrimaryContainer = Color(0xFFE6DEFF),
    secondary = Color(0xFF59A6FF), onSecondary = Color(0xFF00213F),
    background = Color(0xFF0B0B0E), onBackground = Color(0xFFF2F2F7),
    surface = Color(0xFF0B0B0E), onSurface = Color(0xFFF2F2F7),
    surfaceContainerLowest = Color(0xFF0B0B0E), surfaceContainerLow = Color(0xFF141418),
    surfaceContainer = Color(0xFF1C1C1F), surfaceContainerHigh = Color(0xFF232327), surfaceContainerHighest = Color(0xFF2C2C30),
    onSurfaceVariant = Color(0xFFA1A1AA), outline = Color(0xFF3F3F46), outlineVariant = Color(0xFF2A2A30),
    error = Color(0xFFFF8A80), tertiary = Color(0xFFFFB86B),
)
private val LightColors = lightColorScheme(
    primary = Color(0xFF5C3BB8), onPrimary = Color.White,
    primaryContainer = Color(0xFFE6DEFF), onPrimaryContainer = Color(0xFF1E1240),
    secondary = Color(0xFF245EB3), onSecondary = Color.White,
    background = Color(0xFFF2F2F7), onBackground = Color(0xFF111114),
    surface = Color(0xFFF2F2F7), onSurface = Color(0xFF111114),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFF7F7FA),
    surfaceContainer = Color.White, surfaceContainerHigh = Color(0xFFECECF1), surfaceContainerHighest = Color(0xFFE4E4EA),
    onSurfaceVariant = Color(0xFF5B5B66), outline = Color(0xFFC7C7CF), outlineVariant = Color(0xFFE0E0E6),
    tertiary = Color(0xFFB35C00),
)

@Composable
fun SubspaceTheme(appearance: String, content: @Composable () -> Unit) {
    val dark = appearance == "dark" || isSystemInDarkTheme()
    MaterialTheme(colorScheme = if (dark) DarkColors else LightColors, content = content)
}

/** Past estimates vs. forecast in charts, matching the iOS blue/purple. */
object ChartColors {
    val past: Color @Composable @ReadOnlyComposable get() = MaterialTheme.colorScheme.secondary
    val forecast: Color @Composable @ReadOnlyComposable get() = MaterialTheme.colorScheme.primary
    val warning: Color @Composable @ReadOnlyComposable get() = MaterialTheme.colorScheme.tertiary
}
