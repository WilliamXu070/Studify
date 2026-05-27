import UIKit

enum StudifyDebugVisualAid {
    private static let bannerTag = 0x570D1F

    static func intercepted(_ detail: String) {
        show(
            title: "STUDIFY HOOK FIRED",
            detail: detail,
            backgroundColor: UIColor(red: 0.95, green: 0.62, blue: 0.08, alpha: 0.96),
            duration: 5
        )
    }

    static func posting(_ detail: String) {
        show(
            title: "STUDIFY POST STARTED",
            detail: detail,
            backgroundColor: UIColor(red: 0.09, green: 0.40, blue: 0.95, alpha: 0.96),
            duration: 5
        )
    }

    static func accepted(_ detail: String) {
        show(
            title: "STUDIFY SERVER ACCEPTED",
            detail: detail,
            backgroundColor: UIColor(red: 0.12, green: 0.58, blue: 0.28, alpha: 0.96),
            duration: 5
        )
    }

    static func failed(_ detail: String) {
        show(
            title: "STUDIFY REQUEST FAILED",
            detail: detail,
            backgroundColor: UIColor(red: 0.78, green: 0.12, blue: 0.16, alpha: 0.96),
            duration: 7
        )
    }

    private static func show(
        title: String,
        detail: String,
        backgroundColor: UIColor,
        duration: TimeInterval
    ) {
        DispatchQueue.main.async {
            guard let window = activeWindow() else {
                writeDebugLog("[STUDIFY] Visual aid could not find an active window: \(title) \(detail)")
                return
            }

            window.viewWithTag(bannerTag)?.removeFromSuperview()

            let banner = UIView()
            banner.tag = bannerTag
            banner.translatesAutoresizingMaskIntoConstraints = false
            banner.backgroundColor = backgroundColor
            banner.layer.cornerRadius = 10
            banner.layer.borderWidth = 1
            banner.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
            banner.layer.shadowColor = UIColor.black.cgColor
            banner.layer.shadowOpacity = 0.28
            banner.layer.shadowRadius = 12
            banner.layer.shadowOffset = CGSize(width: 0, height: 6)
            banner.alpha = 0

            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.text = title
            titleLabel.textColor = .white
            titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
            titleLabel.numberOfLines = 1

            let detailLabel = UILabel()
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            detailLabel.text = detail
            detailLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            detailLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            detailLabel.numberOfLines = 2

            let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .vertical
            stack.spacing = 3

            banner.addSubview(stack)
            window.addSubview(banner)

            let topInset = max(window.safeAreaInsets.top, 24)
            NSLayoutConstraint.activate([
                banner.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 14),
                banner.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -14),
                banner.topAnchor.constraint(equalTo: window.topAnchor, constant: topInset + 8),

                stack.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
                stack.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
                stack.topAnchor.constraint(equalTo: banner.topAnchor, constant: 10),
                stack.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -10)
            ])

            UIView.animate(withDuration: 0.18) {
                banner.alpha = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard banner.superview != nil else { return }
                UIView.animate(withDuration: 0.24, animations: {
                    banner.alpha = 0
                }, completion: { _ in
                    banner.removeFromSuperview()
                })
            }
        }
    }

    private static func activeWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }

            return windows.first(where: { $0.isKeyWindow })
                ?? windows.first(where: { !$0.isHidden && $0.alpha > 0 })
                ?? UIApplication.shared.windows.first(where: { $0.isKeyWindow })
                ?? UIApplication.shared.windows.first
        }

        return UIApplication.shared.keyWindow ?? UIApplication.shared.windows.first
    }
}
