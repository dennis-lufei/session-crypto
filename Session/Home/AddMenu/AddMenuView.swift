// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Lucide
import SessionUIKit
import SessionUtilitiesKit

/// Menu view similar to WeChat's add menu, displayed from the "+" button
final class AddMenuView: UIView {
    struct MenuItem {
        let icon: UIImage
        let title: String
        let action: () -> Void
    }
    
    private let items: [MenuItem]
    private var itemViews: [MenuItemView] = []
    
    // MARK: - UI
    
    private lazy var blurEffectView: UIVisualEffectView = {
        let result = UIVisualEffectView()
        result.applyLiquidGlassWithObserver()
        return result
    }()
    
    private lazy var containerView: UIView = {
        let result = UIView()
        
        result.addSubview(blurEffectView)
        blurEffectView.pin(to: result)
        
        result.layer.cornerRadius = 14
        result.layer.masksToBounds = true
        result.layer.shadowColor = UIColor.black.cgColor
        result.layer.shadowOpacity = 0.25
        result.layer.shadowRadius = 16
        result.layer.shadowOffset = CGSize(width: 0, height: 4)
        result.clipsToBounds = false
        
        return result
    }()
    
    private lazy var stackView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.distribution = .fillEqually
        result.spacing = 1
        
        return result
    }()
    
    // MARK: - Initialization
    
    init(items: [MenuItem]) {
        self.items = items
        super.init(frame: .zero)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(items:) instead.")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = .clear
        addSubview(containerView)
        
        for item in items {
            let itemView = MenuItemView(item: item)
            itemViews.append(itemView)
            stackView.addArrangedSubview(itemView)
        }
        
        containerView.addSubview(stackView)
        stackView.pin(to: containerView, withInset: 0)
        
        containerView.set(.width, to: 180)
        
        let itemHeight: CGFloat = 56
        let totalHeight = CGFloat(items.count) * itemHeight
        containerView.set(.height, to: totalHeight)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Layout
    
    func show(from sourceView: UIView, in parentView: UIView) {
        parentView.addSubview(self)
        pin(to: parentView)
        
        // Position container below the source view
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Get the frame of sourceView in parentView's coordinate system
        let sourceFrame = sourceView.convert(sourceView.bounds, to: parentView)
        
        NSLayoutConstraint.activate([
            containerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -16),
            containerView.topAnchor.constraint(equalTo: parentView.topAnchor, constant: sourceFrame.maxY + 8)
        ])
        
        // Animate appearance
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.containerView.alpha = 1
            self.containerView.transform = .identity
        }
    }
    
    func hide(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn) {
            self.containerView.alpha = 0
            self.containerView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.removeFromSuperview()
            completion?()
        }
    }
    
    // MARK: - Actions
    
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: containerView)
        if !containerView.bounds.contains(location) {
            hide()
        }
    }
}

// MARK: - MenuItemView

private final class MenuItemView: UIView {
    private let item: AddMenuView.MenuItem
    
    private lazy var iconImageView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFit
        result.image = item.icon.withRenderingMode(.alwaysTemplate)
        result.themeTintColor = .textPrimary
        result.set(.width, to: 24)
        result.set(.height, to: 24)
        
        return result
    }()
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.mediumFontSize, weight: .medium)
        result.themeTextColor = .textPrimary
        result.text = item.title
        result.numberOfLines = 1
        
        return result
    }()
    
    private lazy var stackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [iconImageView, titleLabel])
        result.axis = .horizontal
        result.spacing = Values.smallSpacing
        result.alignment = .center
        result.isLayoutMarginsRelativeArrangement = true
        result.layoutMargins = UIEdgeInsets(
            top: 0,
            left: Values.largeSpacing,
            bottom: 0,
            right: Values.largeSpacing
        )
        
        return result
    }()
    
    init(item: AddMenuView.MenuItem) {
        self.item = item
        super.init(frame: .zero)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(item:) instead.")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        themeBackgroundColor = .clear
        
        addSubview(stackView)
        stackView.pin(to: self)
        set(.height, to: 56)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
    }
    
    @objc private func handleTap() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        item.action()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(withDuration: 0.15) {
            self.alpha = 0.8
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1.0
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1.0
        }
    }
}

