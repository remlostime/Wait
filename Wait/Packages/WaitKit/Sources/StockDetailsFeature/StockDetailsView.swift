//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import MarketDataClient
import StockChartFeature
import SwiftUI

// MARK: - StockDetailsView

public struct StockDetailsView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<StockDetailsFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.l) {
        header
        card { StockChartView(store: store.scope(\.chart, action: \.chart), ladder: store.item.ladder) }
        card { ladderCard }
        card { StatsSection(quote: store.quote) }
        card { checklistRow }
        card { notesCard }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(store.item.symbol)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          store.send(.favoriteTapped)
        } label: {
          Label(store.item.isFavorite ? "Unfavorite" : "Favorite", systemImage: store.item.isFavorite ? "star.fill" : "star")
        }
        .tint(store.item.isFavorite ? Palette.warning : nil)
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button(role: .destructive) {
            store.send(.deleteTapped)
          } label: {
            Label("Remove from Watchlist", systemImage: "trash")
          }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
        }
      }
    }
    .task { await store.send(.task).finish() }
    .sheet(item: $store.scope(\.$destination, action: \.destination).ladderEditor) { editor in
      NavigationStack { LadderEditorView(store: editor) }
        .presentationDetents([.medium, .large])
    }
    .sheet(item: $store.scope(\.$destination, action: \.destination).notesEditor) { notes in
      NavigationStack { NotesEditorView(store: notes) }
    }
    .sheet(isPresented: $store.isShowingLadderHistory) {
      NavigationStack { LadderHistoryView(history: store.item.ladderHistory) }
    }
    .alert($store.scope(\.alert, action: \.alert))
  }

  // MARK: Private

  @Bindable private var store: StoreOf<StockDetailsFeature>

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(store.item.name).font(.subheadline).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
        if let quote = store.quote {
          Text(quote.price, format: .currency(code: "USD")).font(.largeTitle.weight(.bold).monospacedDigit())
          if let change = quote.changePercent {
            Text(change / 100, format: .percent.precision(.fractionLength(2))).foregroundStyle(Palette.change(change))
          }
        } else {
          Text("—").font(.largeTitle.weight(.bold))
        }
      }
      HStack(spacing: Spacing.s) {
        StatusPill(status: store.status)
        TemperatureBadge(temperature: store.temperature)
        if store.quote?.isStale == true {
          Label("Cached", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var ladderCard: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      HStack {
        Text("Ladder").font(.headline)
        Spacer()
        Button("History") { store.send(.historyTapped) }
          .disabled(store.item.ladderHistory.isEmpty)
        Button("Edit") { store.send(.editLadderTapped) }
      }
      if store.item.ladder.isEmpty {
        Text("Set a buy price to see the temperature.").foregroundStyle(.secondary)
      } else {
        ThermometerBar(value: store.temperature?.value)
        ForEach(store.item.ladder.rungs, id: \.rung) { rung in
          HStack {
            Text(rung.isDerived ? "\(rung.rung.title) (derived)" : rung.rung.title)
            Spacer()
            Text(rung.price, format: .currency(code: "USD")).monospacedDigit()
            if let price = store.quote?.price, price > 0 {
              Text(((rung.price - price) / price).doubleValue, format: .percent.precision(.fractionLength(1)))
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)
            }
          }
          .font(.subheadline)
        }
      }
    }
  }

  private var checklistRow: some View {
    Button {
      store.send(.checklistTapped)
    } label: {
      HStack {
        Label("Checklist", systemImage: "checklist")
        Spacer()
        Text("\(store.item.checkedCount) / \(store.item.checklist.count)").foregroundStyle(.secondary)
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
      }
    }
    .buttonStyle(.plain)
  }

  private var notesCard: some View {
    VStack(alignment: .leading, spacing: Spacing.s) {
      HStack {
        Text("Notes").font(.headline)
        Spacer()
        Button("Edit") { store.send(.editNotesTapped) }
      }
      Text(store.item.memo.isEmpty ? "No notes yet." : store.item.memo)
        .foregroundStyle(store.item.memo.isEmpty ? .secondary : .primary)
    }
  }

  private func card(@ViewBuilder _ content: () -> some View) -> some View {
    content()
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
  }
}

// MARK: - ThermometerBar

/// The 0–100 temperature as a gradient track with a marker.
struct ThermometerBar: View {
  let value: Double?

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(LinearGradient(colors: [.blue, .teal, .gray, .orange, .red], startPoint: .leading, endPoint: .trailing))
          .frame(height: 8)
        if let value {
          Circle()
            .fill(.background)
            .overlay(Circle().stroke(.primary, lineWidth: 2))
            .frame(width: 16, height: 16)
            .offset(x: max(0, min(1, value / 100)) * (proxy.size.width - 16))
        }
      }
      .frame(maxHeight: .infinity)
    }
    .frame(height: 16)
    .accessibilityElement()
    .accessibilityLabel(value.map { "Temperature \(Int($0.rounded())) of 100" } ?? "No temperature")
  }
}

#Preview {
  NavigationStack {
    StockDetailsView(store: Store(initialState: StockDetailsFeature.State(item: Shared(value: WatchlistItem(
      symbol: "AAPL",
      name: "Apple Inc",
      ladder: (try? PriceLadder(buyLow: 100, buyHigh: 115, fair: 140, trim: 180)) ?? .empty,
      memo: "Long term hold.\nRevisit after earnings.",
      checklist: ChecklistTemplate.defaultItems,
      createdAt: .now,
      updatedAt: .now
    )))) {
      StockDetailsFeature()
    } withDependencies: {
      $0.marketData = .previewValue
    })
  }
}
