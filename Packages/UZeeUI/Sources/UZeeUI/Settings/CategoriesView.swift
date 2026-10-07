import SwiftUI
import UZeeCore

/// Settings → Categories (CAT-002…005): rename, reorder, hide, add, merge, delete when unused.
struct CategoriesView: View {
    @Bindable var session: AppSession
    @State private var editing: SpendCategory?
    @State private var addingTo: SpendCategory?
    @State private var usage: [UUID: Int] = [:]

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    row(group, isGroup: true)
                    ForEach(children(of: group)) { child in row(child, isGroup: false) }
                        .onMove { from, to in move(in: group, from: from, to: to) }
                    Button("Add subcategory", systemImage: "plus") { addingTo = group }
                        .font(.subheadline)
                        .accessibilityIdentifier("categories.add.\(group.name)")
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear(perform: loadUsage)
        .sheet(item: $editing, onDismiss: loadUsage) { category in
            NavigationStack { CategoryEditView(session: session, category: category, usage: usage[category.id] ?? 0) }
        }
        .sheet(item: $addingTo) { parent in
            NavigationStack { NewCategoryView(session: session, parent: parent) }
                .presentationDetents([.medium])
        }
    }

    /// Expense groups first, then income; the system "Balance adjustment" is not editable.
    private var groups: [SpendCategory] {
        let top = session.ledger.categories.filter { $0.parentID == nil && $0.type != .system }
        return top.filter { $0.type == .expense } + top.filter { $0.type == .income }
    }

    private func children(of parent: SpendCategory) -> [SpendCategory] {
        session.ledger.categories.filter { $0.parentID == parent.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func row(_ category: SpendCategory, isGroup: Bool) -> some View {
        Button { editing = category } label: {
            HStack(spacing: UZSpacing.l) {
                if isGroup { CategoryTile(category.group, size: 30) } else { Color.clear.frame(width: 30, height: 1) }
                Text(category.type == .income && isGroup ? "Income" : category.name)
                    .font(isGroup ? .body.weight(.semibold) : .body)
                    .foregroundStyle(category.isHidden ? UZColor.label2 : UZColor.label)
                Spacer()
                if category.isHidden { Text("Hidden").font(.footnote).foregroundStyle(UZColor.label2) }
                if let count = usage[category.id], count > 0 {
                    Text("\(count)").font(.footnote).monospacedDigit().foregroundStyle(UZColor.label2)
                        .accessibilityLabel("\(count) transactions")
                }
            }
        }
        .accessibilityIdentifier("categories.\(category.name)")
    }

    private func move(in parent: SpendCategory, from: IndexSet, to: Int) {
        var ids = children(of: parent).map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        session.perform("Couldn't save the new order. Try again.") { try session.activity.reorderCategories(ids) }
    }

    private func loadUsage() {
        usage = (try? session.activity.categoryUsage()) ?? [:]
    }
}

/// One category: rename, hide, merge or delete.
struct CategoryEditView: View {
    @Bindable var session: AppSession
    let category: SpendCategory
    let usage: Int
    @State private var name = ""
    @State private var problem: String?
    @State private var merging = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("category.name")
            } footer: {
                Text(usage == 0 ? "Not used yet." : "Used by \(usage) \(usage == 1 ? "transaction" : "transactions"). Renaming keeps them linked.")
            }
            if let problem {
                Section { Text(problem).foregroundStyle(UZColor.negative).accessibilityIdentifier("category.problem") }
            }
            Section {
                Toggle("Hide from pickers", isOn: Binding(get: { current.isHidden }, set: { setHidden($0) }))
                    .accessibilityIdentifier("category.hide")
            } footer: {
                Text("Hidden categories still show on old transactions.")
            }
            Section {
                Button("Merge into another category…") { merging = true }
                    .accessibilityIdentifier("category.merge")
                Button("Delete category", role: .destructive) {
                    if usage > 0 || hasChildren {
                        problem = hasChildren
                            ? "This group has subcategories. Merge it into another group instead."
                            : "Used by \(usage) \(usage == 1 ? "transaction" : "transactions"). Merge it into another category instead."
                    } else {
                        confirmDelete = true
                    }
                }
                .accessibilityIdentifier("category.delete")
            }
        }
        .navigationTitle("Edit category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: rename).accessibilityIdentifier("category.save")
            }
        }
        .onAppear { name = category.name }
        .navigationDestination(isPresented: $merging) {
            MergeTargetView(session: session, source: category) { dismiss() }
        }
        .confirmationDialog("Delete \(category.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if session.perform("Couldn't delete the category. Try again.", { try session.activity.deleteCategory(category.id) }) {
                    session.toasts.show("Category deleted")
                    dismiss()
                }
            }
        }
    }

    private var current: SpendCategory { session.ledger.category(category.id) ?? category }
    private var hasChildren: Bool { session.ledger.categories.contains { $0.parentID == category.id } }

    private func setHidden(_ hidden: Bool) {
        session.perform("Couldn't change the category. Try again.") { try session.activity.setCategoryHidden(hidden, category.id) }
    }

    private func rename() {
        guard name != category.name else { dismiss(); return }
        do {
            try session.activity.renameCategory(category.id, name)
            session.reload()
            session.toasts.show("Category renamed")
            dismiss()
        } catch {
            problem = CategoryProblemText.text(error)
        }
    }
}

/// Picks the category that receives everything from `source` (CAT-004).
struct MergeTargetView: View {
    @Bindable var session: AppSession
    let source: SpendCategory
    let done: () -> Void
    @State private var target: SpendCategory?

    var body: some View {
        List {
            ForEach(candidates) { category in
                Button { target = category } label: {
                    Text(session.ledger.categoryPath(category.id) ?? category.name).foregroundStyle(UZColor.label)
                }
                .accessibilityIdentifier("merge.\(category.name)")
            }
        }
        .navigationTitle("Merge into")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Merge \(source.name) into \(target?.name ?? "")?", isPresented: targetBinding, titleVisibility: .visible,
                            presenting: target) { target in
            Button("Merge") {
                if session.perform("Couldn't merge. Nothing was changed.", { try session.activity.mergeCategory(source.id, target.id) }) {
                    session.toasts.show("Merged into \(target.name)")
                    done()
                }
            }
            .accessibilityIdentifier("merge.confirm")
        } message: { _ in
            Text("All its transactions move to the new category, then \(source.name) is removed. This can't be undone.")
        }
    }

    /// Same tree; a group with subcategories can only merge into another group.
    private var candidates: [SpendCategory] {
        let hasChildren = session.ledger.categories.contains { $0.parentID == source.id }
        return session.ledger.categories.filter { candidate in
            candidate.id != source.id && candidate.type == source.type && candidate.parentID != source.id
                && (!hasChildren || candidate.parentID == nil)
        }
    }

    private var targetBinding: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }
}

/// Adds a subcategory under a group.
struct NewCategoryView: View {
    @Bindable var session: AppSession
    let parent: SpendCategory
    @State private var name = ""
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("Name", text: $name).accessibilityIdentifier("newCategory.name")
            if let problem { Text(problem).foregroundStyle(UZColor.negative) }
        }
        .navigationTitle("New in \(parent.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    do {
                        _ = try session.activity.createCategory(name, parent.id)
                        session.reload()
                        dismiss()
                    } catch {
                        problem = CategoryProblemText.text(error)
                    }
                }
                .accessibilityIdentifier("newCategory.save")
            }
        }
    }
}

/// Settings → Tags (CAT-006): add and remove tags; set them on a transaction's detail screen.
struct TagsView: View {
    @Bindable var session: AppSession
    @State private var name = ""
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New tag", text: $name)
                        .onSubmit(add)
                        .accessibilityIdentifier("tags.name")
                    Button("Add", action: add).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("tags.add")
                }
                if let problem { Text(problem).foregroundStyle(UZColor.negative) }
            } footer: {
                Text("Tags group transactions across categories, like a trip or a project.")
            }
            Section {
                ForEach(session.tags) { tag in
                    Text("#" + tag.name).accessibilityIdentifier("tag.\(tag.name)")
                }
                .onDelete { offsets in
                    let ids = offsets.map { session.tags[$0].id }
                    session.perform("Couldn't delete the tag. Try again.") { for id in ids { try session.activity.deleteTag(id) } }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        do {
            _ = try session.activity.createTag(name)
            name = ""
            problem = nil
            session.reload()
        } catch {
            problem = CategoryProblemText.text(error)
        }
    }
}

enum CategoryProblemText {
    static func text(_ error: any Error) -> String {
        switch error as? SpendCategory.Problem {
        case .emptyName: "Enter a name."
        case .nameTooLong: "Use \(SpendCategory.maxNameLength) characters or fewer."
        case .duplicateName: "That name is already used here."
        case .inUse: "It's in use. Merge it into another category instead."
        case .invalidMerge: "These two can't be merged."
        case .notFound, nil: "Couldn't save. Try again."
        }
    }
}
