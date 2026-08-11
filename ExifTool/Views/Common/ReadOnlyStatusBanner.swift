import SwiftUI

struct ReadOnlyStatusBanner: View {
    let isReadOnly: Bool

    var body: some View {
        Label(
            isReadOnly ? "只读模式已开启，不会修改照片或写入元数据" : "只读模式已关闭",
            systemImage: isReadOnly ? "lock" : "lock.open"
        )
        .font(.callout)
        .foregroundStyle(isReadOnly ? .green : .orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}
