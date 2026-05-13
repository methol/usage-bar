import XCTest
import AppKit
@testable import UsageBar

final class MenuBarIconRendererTests: XCTestCase {
    private func assertUsableTemplateIcon(_ image: NSImage, _ message: String) {
        XCTAssertTrue(image.isTemplate, "\(message): 菜单栏图标必须是 template image（随系统深浅色翻转）")
        XCTAssertGreaterThan(image.size.width, 0, "\(message): 宽度应 > 0")
        XCTAssertGreaterThan(image.size.height, 0, "\(message): 高度应 > 0")
        XCTAssertNotNil(image.tiffRepresentation, "\(message): 应能产出位图表示")
    }

    func testRenderIconForCodexProducesTemplateImage() {
        // Codex 菜单栏 glyph 现走 codex-logo.png（lobehub/lobe-icons），资源缺失时回退 `</>` 自绘 —— 两种情况都应得到可用的 template 图标。
        let image = renderIcon(providerID: .codex, primaryLabel: "5h", secondaryLabel: "7d", pct5h: 0.4, pct7d: 0.1)
        assertUsableTemplateIcon(image, "renderIcon(.codex)")
    }

    func testRenderIconForClaudeProducesTemplateImage() {
        let image = renderIcon(providerID: .claude, primaryLabel: "5h", secondaryLabel: "7d", pct5h: 0.4, pct7d: 0.1)
        assertUsableTemplateIcon(image, "renderIcon(.claude)")
    }

    func testRenderUnauthenticatedIconForCodexProducesTemplateImage() {
        let image = renderUnauthenticatedIcon(providerID: .codex, primaryLabel: "5h", secondaryLabel: "7d")
        assertUsableTemplateIcon(image, "renderUnauthenticatedIcon(.codex)")
    }

    // 注：codex-logo.png / claude-logo.png 是否真的打进 .app bundle，由 macos/scripts/verify-release.sh
    // + `make release-artifacts` 守（resource bundle 在 swift test 运行时不一定可定位，不在单测里验）。
}
