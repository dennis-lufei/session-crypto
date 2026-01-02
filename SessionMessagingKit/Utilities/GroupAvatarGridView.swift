// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUtilitiesKit
import SessionUIKit

/// 群组头像网格视图，支持最多显示9个成员头像
public final class GroupAvatarGridView: UIView {
    private static let maxMembers = 9
    private let size: ProfilePictureView.Info.Size
    private var dataManager: ImageDataManagerType?
    private var memberViews: [SessionImageView] = []
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    
    public init(
        size: ProfilePictureView.Info.Size = .list,
        dataManager: ImageDataManagerType? = nil
    ) {
        self.size = size
        self.dataManager = dataManager
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        layer.cornerRadius = 4  // 正方形小圆角
    }
    
    public func setDataManager(_ dataManager: ImageDataManagerType?) {
        self.dataManager = dataManager
        if let dataManager = dataManager {
            memberViews.forEach { $0.setDataManager(dataManager) }
        }
    }
    
    /// 更新成员头像
    /// - Parameters:
    ///   - members: 成员信息数组，最多取前9个
    ///   - using: 依赖项
    public func update(
        members: [MemberInfo],
        using dependencies: Dependencies
    ) {
        // 清除现有视图
        memberViews.forEach { $0.removeFromSuperview() }
        memberViews.removeAll()
        
        // 最多显示9个成员
        let displayMembers = Array(members.prefix(GroupAvatarGridView.maxMembers))
        guard !displayMembers.isEmpty else { return }
        
        // 创建网格布局
        let layoutInfo = calculateLayoutInfo(count: displayMembers.count)
        let spacing: CGFloat = 1
        let cellSize = calculateCellSize(layoutInfo: layoutInfo, spacing: spacing)
        
        // 计算整个网格的实际宽度和高度
        let gridWidth = CGFloat(layoutInfo.maxColumns) * cellSize + CGFloat(layoutInfo.maxColumns - 1) * spacing
        let gridHeight = CGFloat(layoutInfo.rows.count) * cellSize + CGFloat(layoutInfo.rows.count - 1) * spacing
        
        // 计算整个网格的水平和垂直偏移量（用于居中）
        let containerSize = size.viewSize
        let horizontalOffset = (containerSize - gridWidth) / 2
        let verticalOffset = (containerSize - gridHeight) / 2
        
        // 创建并布局头像视图
        var memberIndex = 0
        for (rowIndex, rowInfo) in layoutInfo.rows.enumerated() {
            let rowColumns = rowInfo.columns
            // 计算该行的水平偏移量（用于居中）
            let rowOffset = calculateRowOffset(
                rowColumns: rowColumns,
                maxColumns: layoutInfo.maxColumns,
                cellSize: cellSize,
                spacing: spacing
            )
            
            for colIndex in 0..<rowColumns {
                guard memberIndex < displayMembers.count else { break }
                let member = displayMembers[memberIndex]
                
                // 创建 SessionImageView 来直接显示头像
                let avatarView = SessionImageView(
                    dataManager: dataManager ?? dependencies[singleton: .imageDataManager]
                )
                avatarView.translatesAutoresizingMaskIntoConstraints = false
                avatarView.contentMode = .scaleAspectFit
                avatarView.clipsToBounds = true
                avatarView.layer.cornerRadius = 4  // 正方形小圆角
                avatarView.themeBackgroundColor = .backgroundSecondary
                
                addSubview(avatarView)
                memberViews.append(avatarView)
                
                // 计算位置：考虑整体偏移（用于居中）和行偏移
                let x = horizontalOffset + rowOffset + CGFloat(colIndex) * (cellSize + spacing)
                let y = verticalOffset + CGFloat(rowIndex) * (cellSize + spacing)
                
                avatarView.pin(UIView.HorizontalEdge.leading, to: UIView.HorizontalEdge.leading, of: self, withInset: x)
                avatarView.pin(UIView.VerticalEdge.top, to: UIView.VerticalEdge.top, of: self, withInset: y)
                avatarView.set(UIView.Dimension.width, to: cellSize)
                avatarView.set(UIView.Dimension.height, to: cellSize)
                
                // 获取头像数据源并加载图片
                let (info, _) = ProfilePictureView.Info.generateInfoFrom(
                    size: size,
                    publicKey: member.profileId,
                    threadVariant: SessionThread.Variant.contact,
                    displayPictureUrl: member.displayPictureUrl,
                    profile: member.profile,
                    using: dependencies
                )
                
                // 如果有图片源，加载图片；否则显示占位符
                if let source = info?.source {
                    avatarView.loadImage(source)
                } else {
                    // 如果没有图片源，显示占位符（使用用户ID的前两个字符）
                    let placeholderText = String(member.profileId.prefix(2)).uppercased()
                    avatarView.loadImage(.placeholderIcon(
                        seed: member.profileId,
                        text: placeholderText,
                        size: cellSize
                    ))
                }
                
                memberIndex += 1
            }
        }
        
        // 容器大小固定为 size.viewSize（与 ProfilePictureView 保持一致）
        // containerSize 已在上面声明，这里直接使用
        
        // 更新约束
        if let widthConstraint = widthConstraint {
            widthConstraint.constant = containerSize
        } else {
            widthConstraint = set(UIView.Dimension.width, to: containerSize)
        }
        
        if let heightConstraint = heightConstraint {
            heightConstraint.constant = containerSize
        } else {
            heightConstraint = set(UIView.Dimension.height, to: containerSize)
        }
    }
    
    /// 行布局信息
    private struct RowLayoutInfo {
        let columns: Int  // 该行的列数
    }
    
    /// 布局信息
    private struct LayoutInfo {
        let rows: [RowLayoutInfo]
        let maxColumns: Int  // 最大列数，用于计算单元格大小
    }
    
    /// 计算布局信息
    private func calculateLayoutInfo(count: Int) -> LayoutInfo {
        switch count {
        case 1:
            // 1个头像：平铺展示（1x1）
            return LayoutInfo(rows: [RowLayoutInfo(columns: 1)], maxColumns: 1)
            
        case 2:
            // 2个头像：显示一排，垂直居中
            return LayoutInfo(rows: [RowLayoutInfo(columns: 2)], maxColumns: 2)
            
        case 3:
            // 3个头像：显示两排，第一排1个，第二排2个
            return LayoutInfo(
                rows: [
                    RowLayoutInfo(columns: 1),
                    RowLayoutInfo(columns: 2)
                ],
                maxColumns: 2
            )
            
        case 4:
            // 4个头像：展示两排，每一排两个
            return LayoutInfo(
                rows: [
                    RowLayoutInfo(columns: 2),
                    RowLayoutInfo(columns: 2)
                ],
                maxColumns: 2
            )
            
        case 5:
            // 5个头像：展示两排，第一排2个水平居中，第二排3个
            return LayoutInfo(
                rows: [
                    RowLayoutInfo(columns: 2),
                    RowLayoutInfo(columns: 3)
                ],
                maxColumns: 3
            )
            
        case 6:
            // 6个头像：展示两排，每一排都三个
            return LayoutInfo(
                rows: [
                    RowLayoutInfo(columns: 3),
                    RowLayoutInfo(columns: 3)
                ],
                maxColumns: 3
            )
            
        case 7:
            // 7个头像：展示三排，第一排1个，第二第三排均为三个
            return LayoutInfo(
                rows: [
                    RowLayoutInfo(columns: 1),
                    RowLayoutInfo(columns: 3),
                    RowLayoutInfo(columns: 3)
                ],
                maxColumns: 3
            )
            
        case 8:
            // 8个头像：展示三排，第一排2个，第二第三排均为三个
            return LayoutInfo(
                rows: [
                    RowLayoutInfo(columns: 2),
                    RowLayoutInfo(columns: 3),
                    RowLayoutInfo(columns: 3)
                ],
                maxColumns: 3
            )
            
        default: // 9个或更多
            // 9个或更多头像：展示三排，每一排都是三个
            return LayoutInfo(
                rows: [
                    RowLayoutInfo(columns: 3),
                    RowLayoutInfo(columns: 3),
                    RowLayoutInfo(columns: 3)
                ],
                maxColumns: 3
            )
        }
    }
    
    /// 计算行的水平偏移量（用于居中）
    private func calculateRowOffset(
        rowColumns: Int,
        maxColumns: Int,
        cellSize: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        // 如果该行的列数等于最大列数，则不需要偏移
        guard rowColumns < maxColumns else { return 0 }
        
        // 计算该行需要的总宽度
        let rowWidth = CGFloat(rowColumns) * cellSize + CGFloat(rowColumns - 1) * spacing
        // 计算居中所需的偏移量
        let containerSize = size.viewSize
        return (containerSize - rowWidth) / 2
    }
    
    /// 计算每个单元格的大小
    private func calculateCellSize(layoutInfo: LayoutInfo, spacing: CGFloat) -> CGFloat {
        let containerSize = size.viewSize
        let maxColumns = layoutInfo.maxColumns
        let maxRows = layoutInfo.rows.count
        
        // 计算水平和垂直方向的总间距
        let horizontalSpacing = CGFloat(maxColumns - 1) * spacing
        let verticalSpacing = CGFloat(maxRows - 1) * spacing
        
        // 单元格大小应该同时考虑行和列，确保整个网格正好填满容器
        let cellWidth = (containerSize - horizontalSpacing) / CGFloat(maxColumns)
        let cellHeight = (containerSize - verticalSpacing) / CGFloat(maxRows)
        
        // 取较小值，确保网格不会超出容器，并且所有头像都是正方形
        return min(cellWidth, cellHeight)
    }
    
    /// 成员信息结构
    public struct MemberInfo {
        let profileId: String
        let displayPictureUrl: String?
        let profile: Profile?
        
        public init(profileId: String, displayPictureUrl: String? = nil, profile: Profile? = nil) {
            self.profileId = profileId
            self.displayPictureUrl = displayPictureUrl
            self.profile = profile
        }
    }
}

