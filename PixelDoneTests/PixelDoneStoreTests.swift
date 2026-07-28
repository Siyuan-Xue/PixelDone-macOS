@testable import PixelDone
import PixelDoneDomain
import Testing

@Suite("macOS store persistence boundary")
@MainActor
struct PixelDoneStoreTests {
    @Test("A typed intent persists before publishing the new snapshot")
    func createTodo() async throws {
        let container = PixelDonePersistence.makeContainer(inMemory: true)
        let repository = PixelDoneRepository(modelContainer: container)
        let store = PixelDoneStore(repository: repository)

        await store.load()
        let originalCount = store.snapshot.todos.count
        await store.send(
            .createTodo(
                TodoDraft(
                    title: "Persist me",
                    priority: .high,
                    dueDate: .now.addingTimeInterval(3_600),
                    reminderRepeat: .none
                )
            )
        )

        #expect(store.snapshot.todos.count == originalCount + 1)
        let reloaded = try await repository.loadSnapshot()
        #expect(
            reloaded?.todos.contains(where: { $0.title == "Persist me" })
                == true
        )
    }

    @Test("Moving to Trash records its origin and timestamp")
    func trashRoundTrip() async throws {
        let container = PixelDonePersistence.makeContainer(inMemory: true)
        let repository = PixelDoneRepository(modelContainer: container)
        let store = PixelDoneStore(repository: repository)

        await store.load()
        let todo = try #require(store.snapshot.todos.first)
        await store.send(.moveToTrash(todo.id))

        let trashed = try #require(
            store.snapshot.todos.first(where: { $0.id == todo.id })
        )
        #expect(
            trashed.checklistID
                == PixelDoneProductBaseline.trashChecklistID
        )
        #expect(
            trashed.trashedFromChecklistID
                == PixelDoneProductBaseline.defaultChecklistID
        )
        #expect(trashed.trashedAtMillis != nil)
    }
}
