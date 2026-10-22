import UIKit

struct Todo {
    let number: Int
    let hours: Int
    var label: String { "Task #\(number)" }
    var estimate: String { "\(hours)h" }
}

final class TasksViewController: UITableViewController {

    private let tasks = (0..<40).map { Todo(number: 1001 + $0, hours: ($0 * 7) % 12 + 1) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tasks"
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tasks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "task") ?? UITableViewCell(style: .value1, reuseIdentifier: "task")
        cell.textLabel?.text = tasks[indexPath.row].label
        cell.detailTextLabel?.text = tasks[indexPath.row].estimate
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(TaskDetailViewController(task: tasks[indexPath.row]), animated: true)
    }
}

final class TaskDetailViewController: UIViewController, UIPopoverPresentationControllerDelegate {

    private let task: Todo
    private let optionsButton = UIButton(configuration: .tinted())
    private let summary = UILabel()

    init(task: Todo) {
        self.task = task
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = task.label
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        summary.text = "Estimate \(task.estimate)"
        summary.font = .preferredFont(forTextStyle: .title2)

        let done = UISwitch()
        done.addAction(UIAction { [weak self] action in
            self?.summary.text = "Estimate \(self?.task.estimate ?? "")" + ((action.sender as? UISwitch)?.isOn == true ? " · Done" : "")
        }, for: .valueChanged)

        let priority = UISegmentedControl(items: ["Low", "Medium", "High"])
        priority.selectedSegmentIndex = 1

        let note = UITextField()
        note.placeholder = "Add a comment"
        note.borderStyle = .roundedRect
        note.returnKeyType = .done
        note.addAction(UIAction { _ in note.resignFirstResponder() }, for: .editingDidEndOnExit)

        optionsButton.configuration?.title = "Options…"
        optionsButton.addAction(UIAction { [weak self] _ in self?.showOptions() }, for: .touchUpInside)

        let toast = UIButton(configuration: .tinted())
        toast.configuration?.title = "Save"
        toast.addAction(UIAction { _ in Toast.show("Task saved") }, for: .touchUpInside)

        let secret = UIButton(configuration: .plain())
        secret.configuration?.title = "Recovery key"
        secret.addAction(UIAction { [weak self] _ in self?.navigationController?.pushViewController(RecoveryKeyViewController(), animated: true) }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [summary, row("Done", done), priority, note, optionsButton, toast, secret])
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

    private let choices = ["Remind me", "Flag", "Duplicate", "Move to next week"]
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

final class RecoveryKeyViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recovery key"
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "K7QD-29XF-M4LP\nRW8N-3HCT-V6ZB"
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
