//
//  GlassCard.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import SwiftUI

/// Glassmorphic card style modifier
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadiusMedium
    var padding: CGFloat = Theme.paddingMedium
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            )
    }
}

/// Frosted glass background with blur
struct FrostedGlass: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadiusMedium
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Theme.cornerRadiusMedium, padding: CGFloat = Theme.paddingMedium) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }
    
    func frostedGlass(cornerRadius: CGFloat = Theme.cornerRadiusMedium) -> some View {
        modifier(FrostedGlass(cornerRadius: cornerRadius))
    }
}
