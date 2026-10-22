import UIKit

struct Order {
    let number: Int
    let total: Double
    var label: String { "Order #\(number)" }
    var amount: String { String(format: "$%.2f", total) }
}

final class OrdersViewController: UITableViewController {

    private let orders = (0..<40).map { Order(number: 1001 + $0, total: Double(($0 * 37) % 90) + 4.5) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Orders"
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        orders.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "order") ?? UITableViewCell(style: .value1, reuseIdentifier: "order")
        cell.textLabel?.text = orders[indexPath.row].label
        cell.detailTextLabel?.text = orders[indexPath.row].amount
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(OrderDetailViewController(order: orders[indexPath.row]), animated: true)
    }
}

final class OrderDetailViewController: UIViewController, UIPopoverPresentationControllerDelegate {

    private let order: Order
    private let optionsButton = UIButton(configuration: .tinted())
    private let summary = UILabel()

    init(order: Order) {
        self.order = order
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = order.label
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        summary.text = "Total \(order.amount)"
        summary.font = .preferredFont(forTextStyle: .title2)

        let paid = UISwitch()
        paid.addAction(UIAction { [weak self] action in
            self?.summary.text = "Total \(self?.order.amount ?? "")" + ((action.sender as? UISwitch)?.isOn == true ? " · Paid" : "")
        }, for: .valueChanged)

        let type = UISegmentedControl(items: ["Dine in", "Takeaway", "Delivery"])
        type.selectedSegmentIndex = 0

        let note = UITextField()
        note.placeholder = "Note for the kitchen"
        note.borderStyle = .roundedRect
        note.returnKeyType = .done
        note.addAction(UIAction { _ in note.resignFirstResponder() }, for: .editingDidEndOnExit)

        optionsButton.configuration?.title = "Options…"
        optionsButton.addAction(UIAction { [weak self] _ in self?.showOptions() }, for: .touchUpInside)

        let toast = UIButton(configuration: .tinted())
        toast.configuration?.title = "Save"
        toast.addAction(UIAction { _ in Toast.show("Order saved") }, for: .touchUpInside)

        let card = UIButton(configuration: .plain())
        card.configuration?.title = "Payment card details"
        card.addAction(UIAction { [weak self] _ in self?.navigationController?.pushViewController(CardDetailsViewController(), animated: true) }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [summary, row("Paid", paid), type, note, optionsButton, toast, card])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor)
        ])
    }

    private func row(_ title: String, _ control: UIView) -> UIStackView {
        let label = UILabel()
        label.text = title
        let row = UIStackView(arrangedSubviews: [label, control])
        row.distribution = .equalSpacing
        return row
    }

    private func showOptions() {
        let options = OptionsViewController { [weak self] choice in
            self?.optionsButton.configuration?.title = "Options: \(choice)"
        }
        options.modalPresentationStyle = .popover
        options.preferredContentSize = CGSize(width: 260, height: 176)
        options.popoverPresentationController?.sourceView = optionsButton
        options.popoverPresentationController?.sourceRect = optionsButton.bounds
        options.popoverPresentationController?.delegate = self
        present(options, animated: true)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}

final class OptionsViewController: UITableViewController {

    private let choices = ["No onions", "Extra spicy", "Gift wrap", "Call on arrival"]
    private let onChoose: (String) -> Void

    init(onChoose: @escaping (String) -> Void) {
        self.onChoose = onChoose
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { nil }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        choices.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.textLabel?.text = choices[indexPath.row]
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onChoose(choices[indexPath.row])
        dismiss(animated: true)
    }
}

final class CardDetailsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Card"
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "4242 4242 4242 4242\nExp 12/29 · CVC 123"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

enum Toast {

    private static var window: UIWindow?

    static func show(_ text: String) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        let label = PaddedLabel()
        label.text = text
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .headline)
        label.backgroundColor = .systemGreen
        label.layer.cornerRadius = 14
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor, constant: -70)
        ])
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.window === window { self.window = nil }
            window.isHidden = true
        }
    }
}

private final class PaddedLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 32, height: size.height + 20)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 16, dy: 10))
    }
}
