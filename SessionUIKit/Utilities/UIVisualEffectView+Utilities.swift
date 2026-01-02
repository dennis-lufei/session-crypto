// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit

/// Extension for creating liquid glass blur effects
/// References:
/// - https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
/// - https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
/// - https://developer.apple.com/documentation/swiftui/glasseffectcontainer
public extension UIVisualEffectView {
    /// Creates a liquid glass blur effect view using systemMaterial
    static func createLiquidGlass(using theme: Theme) -> UIVisualEffectView {
        let result = UIVisualEffectView()
        let blurStyle: UIBlurEffect.Style = (theme.interfaceStyle == .light ?
            .systemMaterialLight :
            .systemMaterial
        )
        result.effect = UIBlurEffect(style: blurStyle)
        result.backgroundColor = .clear
        return result
    }
    
    /// Applies liquid glass blur effect with theme support
    func applyLiquidGlass(theme: Theme) {
        let blurStyle: UIBlurEffect.Style = (theme.interfaceStyle == .light ?
            .systemMaterialLight :
            .systemMaterial
        )
        self.effect = UIBlurEffect(style: blurStyle)
        self.backgroundColor = .clear
    }
    
    /// Applies liquid glass blur effect with ThemeManager observer
    func applyLiquidGlassWithObserver() {
        ThemeManager.onThemeChange(observer: self) { [weak self] theme, _, _ in
            self?.applyLiquidGlass(theme: theme)
        }
        applyLiquidGlass(theme: ThemeManager.currentTheme)
    }
}

