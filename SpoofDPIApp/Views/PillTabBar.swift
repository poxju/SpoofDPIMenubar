import SwiftUI

struct PillTabBar<Tab: Hashable & CaseIterable & Identifiable>: View where Tab.AllCases: RandomAccessCollection {
    @Binding var selection: Tab
    let title: KeyPath<Tab, String>
    var icon: KeyPath<Tab, String>? = nil
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(Array(Tab.allCases)) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.55), in: Capsule(style: .continuous))
    }

    private func tabButton(_ tab: Tab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                selection = tab
            }
        } label: {
            Text(tab[keyPath: title])
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                .lineLimit(1)
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, compact ? 8 : 14)
                .padding(.vertical, compact ? 5 : 7)
                .frame(maxWidth: .infinity)
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct UnderlineTabBar<Tab: Hashable & CaseIterable & Identifiable>: View where Tab.AllCases: RandomAccessCollection {
    @Binding var selection: Tab
    let title: KeyPath<Tab, String>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Tab.allCases)) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab[keyPath: title])
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selection == tab ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .frame(maxWidth: .infinity)

                        Capsule()
                            .fill(selection == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                            .padding(.horizontal, 4)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
