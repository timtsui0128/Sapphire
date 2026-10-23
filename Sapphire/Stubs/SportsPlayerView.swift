//
//  SportsPlayerView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import SwiftUI

struct SportsPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    init(navigationStack: Binding<[NotchWidgetMode]>) {
        _navigationStack = navigationStack
    }

    var body: some View {
        CommunitySportsBoardView()
    }
}
