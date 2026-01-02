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
        result.layer.cornerRadius = 16
        result.clipsToBounds = true
        return result
    }()
    
    private lazy var containerView: UIView = {
        let result = UIView()
        
        result.addSubview(blurEffectView)
        blurEffectView.pin(to: result)
        
        result.layer.cornerRadius = 16
        result.layer.masksToBounds = false
        result.clipsToBounds = false
        result.layer.shadowColor = UIColor.black.cgColor
        result.layer.shadowOpacity = 0.25
        result.layer.shadowRadius = 16
        result.layer.shadowOffset = CGSize(width: 0, height: 4)
        
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
        
        // Ensure corner radius is applied after layout
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.containerView.layoutIfNeeded()
            self.blurEffectView.layer.cornerRadius = 16
            self.blurEffectView.clipsToBounds = true
        }
        
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
        
        // Ensure menu doesn't get covered by navigation bar
        // Calculate top position: ensure at least 8pt below the button, or below safe area if button is too high
        let safeAreaTop = parentView.safeAreaInsets.top
        let buttonBottom = sourceFrame.maxY
        let spacing: CGFloat = 8
        let calculatedTop = buttonBottom + spacing
        
        // Use safe area top anchor to ensure menu is always visible
        // If calculated position is above safe area, place it below safe area with spacing
        let topOffset = max(calculatedTop - safeAreaTop, spacing)
        
        NSLayoutConstraint.activate([
            containerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -16),
            containerView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: topOffset)
        ])
        
        // Ensure layout and corner radius are set before animation
        containerView.layoutIfNeeded()
        blurEffectView.layer.cornerRadius = 16
        blurEffectView.clipsToBounds = true
        
        // Set initial state for animation
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85).translatedBy(x: 0, y: -10)
        
        // Animate container appearance with spring animation
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.containerView.alpha = 1.0
                self.containerView.transform = .identity
            }
        )
        
        // Animate menu items with staggered appearance
        for (index, itemView) in itemViews.enumerated() {
            itemView.alpha = 0
            itemView.transform = CGAffineTransform(translationX: 0, y: -10)
            
            UIView.animate(
                withDuration: 0.3,
                delay: 0.05 + Double(index) * 0.03,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.3,
                options: [.curveEaseOut],
                animations: {
                    itemView.alpha = 1.0
                    itemView.transform = .identity
                }
            )
        }
    }
    
    func hide(completion: (() -> Void)? = nil) {
        // Animate menu items disappearing first (reverse stagger)
        for (index, itemView) in itemViews.enumerated().reversed() {
            UIView.animate(
                withDuration: 0.2,
                delay: Double(itemViews.count - 1 - index) * 0.02,
                options: [.curveEaseIn],
                animations: {
                    itemView.alpha = 0
                    itemView.transform = CGAffineTransform(translationX: 0, y: -5)
                }
            )
        }
        
        // Animate container disappearing
        UIView.animate(
            withDuration: 0.25,
            delay: 0.05,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.5,
            options: [.curveEaseIn],
            animations: {
                self.containerView.alpha = 0
                self.containerView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85).translatedBy(x: 0, y: -10)
            },
            completion: { _ in
                self.removeFromSuperview()
                completion?()
            }
        )
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

