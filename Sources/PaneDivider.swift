// Interaction and visual design: Claude Opus 5.5.
import SwiftUI
import AppKit

/// 竖向分隔线：8pt 点击区，1pt 线。onDelta 传水平增量（向右为正）。
struct PaneDivider: View {
    var lineColor: Color
    var accentColor: Color
    var label: String
    var valueDescription: String = ""
    var keyboardStep: CGFloat = 16
    var accessibilityDirection: CGFloat = 1
    var onDelta: (CGFloat) -> Void
    var onReset: () -> Void
    var onDragEnded: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var lastX: CGFloat?
    @State private var cursorPushed = false
    @FocusState private var isFocused: Bool

    private var highlighted: Bool { isHovering || isDragging || isFocused }

    var body: some View {
        Rectangle()
            .fill(highlighted ? accentColor : lineColor)
            .frame(width: highlighted ? 2 : 1)
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                updateCursor()
            }
            .gesture(drag)
            .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
            .focusable()
            .focused($isFocused)
            .onMoveCommand { direction in
                switch direction {
                case .left: onDelta(-keyboardStep); onDragEnded?()
                case .right: onDelta(keyboardStep); onDragEnded?()
                default: break
                }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(valueDescription)
            .help(L("拖动调整宽度 · 双击恢复默认 · 方向键微调"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onDelta(keyboardStep * accessibilityDirection)
                case .decrement: onDelta(-keyboardStep * accessibilityDirection)
                @unknown default: break
                }
                onDragEnded?()
            }
            .accessibilityAction(named: L("复位")) { onReset() }
            .animation(isDragging ? nil : .easeOut(duration: 0.12), value: highlighted)
            .onDisappear {
                if cursorPushed { NSCursor.pop(); cursorPushed = false }
            }
    }

    // 全局坐标：分隔线自身随拖动移动，局部坐标会跟着漂移造成抖动
    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    lastX = value.startLocation.x
                    updateCursor()
                }
                let delta = value.location.x - (lastX ?? value.location.x)
                lastX = value.location.x
                guard delta != 0 else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { onDelta(delta) }
            }
            .onEnded { _ in
                isDragging = false
                lastX = nil
                updateCursor()
                onDragEnded?()
            }
    }

    // 拖动时指针可能离开 8pt 区域，用状态位保证 push/pop 成对
    private func updateCursor() {
        let wanted = isHovering || isDragging
        if wanted && !cursorPushed {
            NSCursor.resizeLeftRight.push()
            cursorPushed = true
        } else if !wanted && cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}
