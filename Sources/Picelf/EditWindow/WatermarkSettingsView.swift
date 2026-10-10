import SwiftUI
import AppKit

struct WatermarkSettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var prefs = AppPreferences.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: EditorTheme.spacing10) {
            // 标题栏
            HStack {
                Text(L10n.watermark)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(EditorTheme.primaryText)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(EditorTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .iconTip(.closePanel)
            }
            
            // 主开关
            mainToggle
            
            if prefs.watermarkConfig.isEnabled {
                // 内容设置
                contentSection
                
                // 样式设置
                styleSection
                
                // 平铺设置
                tiledSection
                
                // 预览区
                watermarkPreviewSection
            }
            
            // 底部按钮
            HStack {
                Button(L10n.resetToDefaults) {
                    // 只重置样式参数，保留启用状态和位置
                    var current = prefs.watermarkConfig
                    current.text = ""
                    current.fontSize = 24
                    current.fontName = "SF Pro Display"
                    current.color = CodableColor(color: .white)
                    current.opacity = 0.5
                    current.hasShadow = true
                    current.shadowRadius = 2
                    current.rotation = 0
                    current.tiledEnabled = false
                    current.tiledAngle = -30
                    current.tiledSpacingX = 200
                    current.tiledSpacingY = 100
                    prefs.watermarkConfig = current
                }
                .buttonStyle(EditorSecondaryButtonStyle())
                
                Spacer()
                
                Button(L10n.done) {
                    isPresented = false
                }
                .buttonStyle(EditorPrimaryButtonStyle())
            }
        }
        .padding(EditorTheme.spacing12)
        .frame(width: 320)
        .tint(EditorTheme.accent)
    }
    
    // MARK: - Main Toggle
    
    private var mainToggle: some View {
        Toggle(isOn: $prefs.watermarkConfig.isEnabled) {
            HStack(spacing: 8) {
                Image(systemName: prefs.watermarkConfig.isEnabled ? "drop.fill" : "drop")
                    .foregroundStyle(prefs.watermarkConfig.isEnabled ? EditorTheme.accent : EditorTheme.secondaryText)
                Text(L10n.watermarkEnabled)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EditorTheme.primaryText)
            }
        }
        .toggleStyle(.switch)
        .padding(EditorTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .fill(EditorTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .stroke(EditorTheme.panelBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: EditorTheme.spacing8) {
            Text(L10n.watermarkContent)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorTheme.secondaryText)
            
            // 文本输入
            HStack(spacing: 8) {
                Text(L10n.watermarkText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: 44, alignment: .leading)
                
                TextField(L10n.watermarkTextPlaceholder, text: $prefs.watermarkConfig.text)
                    .textFieldStyle(.roundedBorder)
            }
            
            // 位置选择
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.watermarkPosition)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
                
                WatermarkPositionPicker(position: $prefs.watermarkConfig.position)
            }
        }
        .padding(EditorTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .fill(EditorTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .stroke(EditorTheme.panelBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Style Section
    
    private var styleSection: some View {
        VStack(alignment: .leading, spacing: EditorTheme.spacing8) {
            Text(L10n.watermarkStyle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorTheme.secondaryText)
            
            // 字体选择
            formRow(L10n.watermarkFont) {
                Menu {
                    ForEach(fontOptions, id: \.self) { font in
                        Button(font) {
                            prefs.watermarkConfig.fontName = font
                        }
                    }
                } label: {
                    HStack {
                        Text(prefs.watermarkConfig.fontName)
                            .font(.system(size: 12))
                            .foregroundStyle(EditorTheme.primaryText)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(EditorTheme.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(EditorTheme.fieldBackground)
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
            }
            
            // 字号
            formRow(L10n.watermarkFontSize) {
                HStack(spacing: 8) {
                    Slider(value: $prefs.watermarkConfig.fontSize, in: 12...48, step: 1)
                    Text("\(Int(prefs.watermarkConfig.fontSize))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            
            // 颜色
            formRow(L10n.watermarkColor) {
                ColorPicker("", selection: Binding(
                    get: { prefs.watermarkConfig.color.color },
                    set: { prefs.watermarkConfig.color = CodableColor(color: $0) }
                ))
                .labelsHidden()
            }
            
            // 透明度
            formRow(L10n.watermarkOpacity) {
                HStack(spacing: 8) {
                    Slider(value: $prefs.watermarkConfig.opacity, in: 0.1...1.0, step: 0.05)
                    Text("\(Int(prefs.watermarkConfig.opacity * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .frame(width: 32, alignment: .trailing)
                }
            }
            
            // 阴影开关
            formRow(L10n.watermarkShadow) {
                Toggle("", isOn: $prefs.watermarkConfig.hasShadow)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            
            // 阴影半径（仅在启用阴影时显示）
            if prefs.watermarkConfig.hasShadow {
                formRow(L10n.watermarkShadowRadius) {
                    HStack(spacing: 8) {
                        Slider(value: $prefs.watermarkConfig.shadowRadius, in: 0...10, step: 0.5)
                        Text("\(Int(prefs.watermarkConfig.shadowRadius))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(EditorTheme.secondaryText)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
            
            // 旋转
            formRow(L10n.watermarkRotation) {
                HStack(spacing: 8) {
                    Slider(value: $prefs.watermarkConfig.rotation, in: -45...45, step: 1)
                    Text("\(Int(prefs.watermarkConfig.rotation))°")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(EditorTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .fill(EditorTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .stroke(EditorTheme.panelBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Tiled Section
    
    private var tiledSection: some View {
        VStack(alignment: .leading, spacing: EditorTheme.spacing8) {
            // 平铺开关
            Toggle(isOn: $prefs.watermarkConfig.tiledEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: prefs.watermarkConfig.tiledEnabled ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .foregroundStyle(prefs.watermarkConfig.tiledEnabled ? EditorTheme.accent : EditorTheme.secondaryText)
                    Text(L10n.watermarkTiledEnabled)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EditorTheme.primaryText)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            
            // 平铺设置（仅在启用时显示）
            if prefs.watermarkConfig.tiledEnabled {
                // 角度
                formRow(L10n.watermarkTiledAngle) {
                    HStack(spacing: 8) {
                        Slider(value: $prefs.watermarkConfig.tiledAngle, in: -60...60, step: 1)
                        Text("\(Int(prefs.watermarkConfig.tiledAngle))°")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(EditorTheme.secondaryText)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                
                // 间距
                formRow(L10n.watermarkTiledSpacing) {
                    HStack(spacing: 8) {
                        Slider(value: $prefs.watermarkConfig.tiledSpacingX, in: 50...500, step: 10)
                        Text("\(Int(prefs.watermarkConfig.tiledSpacingX))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(EditorTheme.secondaryText)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
        .padding(EditorTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .fill(EditorTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .stroke(EditorTheme.panelBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Helpers
    
    private var fontOptions: [String] {
        ["SF Pro Display", "SF Pro Text", "Helvetica Neue", "Arial", "Times New Roman", "Georgia", "Courier New"]
    }
    
    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 60, alignment: .leading)
            content()
        }
    }
    
    // MARK: - Preview Section
    
    private var watermarkPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.watermarkPreview)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorTheme.secondaryText)
            
            WatermarkPreviewCanvas(config: prefs.watermarkConfig)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                        .fill(previewBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                        .stroke(EditorTheme.panelBorder, lineWidth: 1)
                )
        }
        .padding(EditorTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .fill(EditorTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EditorTheme.radiusMedium)
                .stroke(EditorTheme.panelBorder, lineWidth: 1)
        )
    }
    
    private var previewBackgroundColor: Color {
        // 根据水印颜色自动选择背景
        let brightness = prefs.watermarkConfig.color.brightnessComponent
        return brightness > 0.6 ? Color(white: 0.2) : Color(white: 0.85)
    }
}

// MARK: - Position Picker

struct WatermarkPositionPicker: View {
    @Binding var position: WatermarkPosition
    
    private let gridSize: CGFloat = 32
    private let spacing: CGFloat = 4
    
    private let grid: [[WatermarkPosition]] = [
        [.topLeft,     .topCenter,     .topRight],
        [.middleLeft,  .middleCenter,  .middleRight],
        [.bottomLeft,  .bottomCenter,  .bottomRight]
    ]
    
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        let pos = grid[row][col]
                        Button(action: { position = pos }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(position == pos
                                        ? EditorTheme.accent
                                        : EditorTheme.fieldBackground)
                                    .frame(width: gridSize, height: gridSize)
                                
                                // Position indicator dot
                                Circle()
                                    .fill(position == pos ? .white : EditorTheme.tertiaryText.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                    .offset(offsetFor(row: row, col: col))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(pos.localizedName)
                    }
                }
            }
        }
    }
    
    private func offsetFor(row: Int, col: Int) -> CGSize {
        let dx: CGFloat = col == 0 ? -8 : (col == 2 ? 8 : 0)
        let dy: CGFloat = row == 0 ? -8 : (row == 2 ? 8 : 0)
        return CGSize(width: dx, height: dy)
    }
}

// MARK: - Preview Canvas

struct WatermarkPreviewCanvas: View {
    let config: WatermarkConfig
    
    var body: some View {
        Canvas { context, size in
            // 绘制模拟背景
            let rect = CGRect(origin: .zero, size: size)
            let bgColor = isLightWatermark ? Color(white: 0.2) : Color(white: 0.85)
            context.fill(Path(rect), with: .color(bgColor))
            
            // 绘制水印
            drawWatermark(config: config, in: context, canvasSize: size)
        }
    }
    
    private var isLightWatermark: Bool {
        config.color.brightnessComponent > 0.6
    }
    
    private func drawWatermark(config: WatermarkConfig, in context: GraphicsContext, canvasSize: CGSize) {
        guard !config.text.isEmpty else { return }
        
        if config.tiledEnabled {
            drawTiledWatermark(config: config, in: context, canvasSize: canvasSize)
        } else {
            drawSingleWatermark(config: config, in: context, canvasSize: canvasSize)
        }
    }
    
    private func drawSingleWatermark(config: WatermarkConfig, in context: GraphicsContext, canvasSize: CGSize) {
        let padding: CGFloat = 16
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let position = config.position.anchorPoint(in: canvasRect, padding: padding)
        
        drawWatermarkText(config: config, at: position, in: context)
    }
    
    private func drawTiledWatermark(config: WatermarkConfig, in context: GraphicsContext, canvasSize: CGSize) {
        let angle = config.tiledAngle * .pi / 180
        let spacingX = config.tiledSpacingX
        let spacingY = config.tiledSpacingY
        
        // 旋转30度后，需要更大的覆盖范围
        let diagonal = sqrt(canvasSize.width * canvasSize.width + canvasSize.height * canvasSize.height)
        let coverSize = diagonal * 1.5
        
        let cols = Int(coverSize / spacingX) + 2
        let rows = Int(coverSize / spacingY) + 2
        
        for row in -rows...rows {
            for col in -cols...cols {
                let baseX = canvasSize.width / 2 + CGFloat(col) * spacingX
                let baseY = canvasSize.height / 2 + CGFloat(row) * spacingY
                
                // 应用旋转
                let cosA = cos(angle)
                let sinA = sin(angle)
                let rotatedX = (baseX - canvasSize.width / 2) * cosA - (baseY - canvasSize.height / 2) * sinA + canvasSize.width / 2
                let rotatedY = (baseX - canvasSize.width / 2) * sinA + (baseY - canvasSize.height / 2) * cosA + canvasSize.height / 2
                
                let pos = CGPoint(x: rotatedX, y: rotatedY)
                
                // 只绘制在画布范围内的水印
                if pos.x > -50 && pos.x < canvasSize.width + 50 &&
                   pos.y > -50 && pos.y < canvasSize.height + 50 {
                    drawWatermarkText(config: config, at: pos, in: context)
                }
            }
        }
    }
    
    private func drawWatermarkText(config: WatermarkConfig, at position: CGPoint, in context: GraphicsContext) {
        let textColor = config.color.color.opacity(config.opacity)
        
        var textContext = context
        if config.hasShadow {
            textContext.addFilter(.shadow(
                color: .black.opacity(0.5),
                radius: config.shadowRadius,
                x: 1,
                y: -1
            ))
        }
        
        var resolvedContext = textContext
        if config.rotation != 0 {
            let transform = CGAffineTransform.identity
                .translatedBy(x: position.x, y: position.y)
                .rotated(by: config.rotation * .pi / 180)
                .translatedBy(x: -position.x, y: -position.y)
            resolvedContext.concatenate(transform)
        }
        
        let text = Text(config.text)
            .font(.system(size: config.fontSize, weight: .semibold))
            .foregroundStyle(textColor)
        
        resolvedContext.draw(text, at: position, anchor: .center)
    }
}

// MARK: - Preview

#Preview {
    WatermarkSettingsView(isPresented: .constant(true))
}
