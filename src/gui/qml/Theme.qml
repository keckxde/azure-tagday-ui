import QtQuick 2.15

pragma Singleton

QtObject {
    // Palette - Modern Dark Theme
    readonly property color bgDark: "#0d1117"
    readonly property color bgSidebar: "#161b22"
    readonly property color bgCard: "#21262d"
    readonly property color bgCardHover: "#30363d"
    readonly property color border: "#30363d"
    readonly property color borderFocus: "#58a6ff"

    // Text colors
    readonly property color textPrimary: "#f0f6fc"
    readonly property color textSecondary: "#8b949e"
    readonly property color textMuted: "#484f58"

    // Accents & Badges
    readonly property color accent: "#238636"
    readonly property color accentHover: "#2ea043"
    readonly property color primaryBlue: "#1f6feb"
    readonly property color primaryBlueHover: "#388bfd"

    // Status colors
    readonly property color colorGreen: "#238636"
    readonly property color colorRed: "#da3633"
    readonly property color colorYellow: "#d29922"
    readonly property color colorPurple: "#8957e5"
    readonly property color colorGrey: "#6e7681"

    // Typography
    readonly property string fontMono: "Consolas, 'Courier New', monospace"
    readonly property string fontSans: "Segoe UI, -apple-system, sans-serif"

    // Spacing
    readonly property int radiusSmall: 4
    readonly property int radiusMedium: 6
    readonly property int radiusLarge: 8
}
