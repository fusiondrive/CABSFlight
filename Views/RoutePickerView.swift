//
//  RoutePickerView.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import SwiftUI

/// Horizontal scrolling route selector with glassmorphic pills
struct RoutePickerView: View {
    @ObservedObject var viewModel: BusTrackingViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.routes) { route in
                    RouteButton(
                        route: route,
                        isSelected: viewModel.selectedRoute?.id == route.id,
                        action: { viewModel.selectRoute(route) }
                    )
                }
            }
            .padding(.horizontal, Theme.paddingMedium)
            .padding(.vertical, Theme.paddingSmall)
        }
    }
}

/// Individual route selector button
struct RouteButton: View {
    let route: Route
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Route color indicator
                Circle()
                    .fill(route.color)
                    .frame(width: 10, height: 10)
                
                // Route code
                Text(route.id)
                    .font(Theme.bodyFont(14))
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? route.color.opacity(0.2) : Theme.cardBackground)
                    .overlay(
                        Capsule()
                            .stroke(
                                isSelected ? route.color : Theme.border,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.animationSpring, value: isSelected)
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        
        VStack {
            Spacer()
            RoutePickerView(viewModel: BusTrackingViewModel())
                .frostedGlass()
        }
    }
    .preferredColorScheme(.dark)
}
