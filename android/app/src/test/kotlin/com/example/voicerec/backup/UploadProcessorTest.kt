package com.example.voicerec.backup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class UploadProcessorTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private lateinit var file: File
    private lateinit var store: FakeStore

    @Before
    fun setUp() {
        file = tmp.newFile("rec_20261012_120000.m4a").apply { writeBytes(ByteArray(1024)) }
        store = FakeStore().apply { add(file) }
    }

    @Test
    fun `successful upload saves telegram response`() {
        val sender = FakeSender(SendResult.Sent(messageId = 42, fileId = "abc", rawResponse = "{}"))

        val outcome = UploadProcessor(store, sender).process(ID)

        assertEquals(UploadProcessor.Outcome.DONE, outcome)
        val record = store.get(ID)!!
        assertEquals(UploadStatus.UPLOADED, record.status)
        assertEquals(42L, record.telegramMessageId)
        assertEquals("abc", record.telegramFileId)
        assertEquals(1, record.attempts)
    }

    @Test
    fun `network failure is retried and keeps the error`() {
        val sender = FakeSender(SendResult.Retryable("Network error"))

        val outcome = UploadProcessor(store, sender).process(ID)

        assertEquals(UploadProcessor.Outcome.RETRY, outcome)
        val record = store.get(ID)!!
        assertEquals(UploadStatus.PENDING, record.status)
        assertEquals("Network error", record.lastError)
    }

    @Test
    fun `retry then success uploads once`() {
        val sender = FakeSender(
            SendResult.Retryable("Network error"),
            SendResult.Sent(messageId = 7, fileId = null, rawResponse = "{}"),
        )
        val processor = UploadProcessor(store, sender)

        assertEquals(UploadProcessor.Outcome.RETRY, processor.process(ID))
        assertEquals(UploadProcessor.Outcome.DONE, processor.process(ID))

        assertEquals(2, sender.calls)
        assertEquals(UploadStatus.UPLOADED, store.get(ID)!!.status)
        assertEquals(2, store.get(ID)!!.attempts)
    }

    @Test
    fun `already uploaded recording is never sent again`() {
        val sender = FakeSender(SendResult.Sent(messageId = 1, fileId = null, rawResponse = "{}"))
        val processor = UploadProcessor(store, sender)

        processor.process(ID)
        val second = processor.process(ID)

        assertEquals(UploadProcessor.Outcome.DONE, second)
        assertEquals(1, sender.calls)
    }

    @Test
    fun `gives up after max attempts`() {
        val sender = FakeSender(SendResult.Retryable("Server error"))
        val processor = UploadProcessor(store, sender, maxAttempts = 3)

        repeat(2) { assertEquals(UploadProcessor.Outcome.RETRY, processor.process(ID)) }
        val last = processor.process(ID)

        assertEquals(UploadProcessor.Outcome.FAILED, last)
        assertEquals(UploadStatus.FAILED, store.get(ID)!!.status)
        assertTrue(store.get(ID)!!.lastError!!.startsWith("Gave up after 3 attempts"))
    }

    @Test
    fun `permanent error fails without retry`() {
        val sender = FakeSender(SendResult.Permanent("Bot token is invalid or revoked."))

        val outcome = UploadProcessor(store, sender).process(ID)

        assertEquals(UploadProcessor.Outcome.FAILED, outcome)
        assertEquals("Bot token is invalid or revoked.", store.get(ID)!!.lastError)
    }

    @Test
    fun `oversized file fails before any upload`() {
        val sender = FakeSender(SendResult.Sent(messageId = 1, fileId = null, rawResponse = "{}"))

        val outcome = UploadProcessor(store, sender, maxFileBytes = 100).process(ID)

        assertEquals(UploadProcessor.Outcome.FAILED, outcome)
        assertEquals(0, sender.calls)
        assertTrue(store.get(ID)!!.lastError!!.contains("at most"))
    }

    @Test
    fun `missing file fails and is not deleted from the queue`() {
        file.delete()
        val sender = FakeSender(SendResult.Sent(messageId = 1, fileId = null, rawResponse = "{}"))

        val outcome = UploadProcessor(store, sender).process(ID)

        assertEquals(UploadProcessor.Outcome.FAILED, outcome)
        assertEquals(0, sender.calls)
    }

    @Test
    fun `upload never deletes the local file`() {
        UploadProcessor(store, FakeSender(SendResult.Sent(1, null, "{}"))).process(ID)
        assertTrue(file.exists())
    }

    @Test
    fun `forgotten recording is skipped`() {
        val sender = FakeSender(SendResult.Sent(messageId = 1, fileId = null, rawResponse = "{}"))

        val outcome = UploadProcessor(FakeStore(), sender).process(ID)

        assertEquals(UploadProcessor.Outcome.DONE, outcome)
        assertEquals(0, sender.calls)
    }

    @Test
    fun `blocked source keeps the item pending without sending`() {
        val sender = FakeSender(SendResult.Sent(messageId = 1, fileId = null, rawResponse = "{}"))
        val source = FakeSource(UploadSource.Resolved.Blocked("Paused"))

        val outcome = UploadProcessor(store, sender, source = source).process(ID)

        assertEquals(UploadProcessor.Outcome.BLOCKED, outcome)
        assertEquals(0, sender.calls)
        assertEquals(UploadStatus.PENDING, store.get(ID)!!.status)
        assertEquals("Paused", store.get(ID)!!.lastError)
        assertEquals(0, store.get(ID)!!.attempts)
    }

    @Test
    fun `unavailable source fails the item`() {
        val sender = FakeSender(SendResult.Sent(messageId = 1, fileId = null, rawResponse = "{}"))
        val source = FakeSource(UploadSource.Resolved.Unavailable("Deleted"))

        assertEquals(UploadProcessor.Outcome.FAILED, UploadProcessor(store, sender, source = source).process(ID))
        assertEquals(UploadStatus.FAILED, store.get(ID)!!.status)
        assertEquals(0, sender.calls)
    }

    @Test
    fun `source file is sent with its caption and released afterwards`() {
        var released = false
        val sender = FakeSender(SendResult.Sent(messageId = 1, fileId = null, rawResponse = "{}"))
        val source = FakeSource(UploadSource.Resolved.Ready(file, "My caption") { released = true })

        assertEquals(UploadProcessor.Outcome.DONE, UploadProcessor(store, sender, source = source).process(ID))
        assertEquals("My caption", sender.lastCaption)
        assertTrue(released)
    }

    @Test
    fun `source is released even when the upload is retried`() {
        var released = false
        val sender = FakeSender(SendResult.Retryable("Network error"))
        val source = FakeSource(UploadSource.Resolved.Ready(file) { released = true })

        assertEquals(UploadProcessor.Outcome.RETRY, UploadProcessor(store, sender, source = source).process(ID))
        assertTrue(released)
    }

    @Test
    fun `source that does not handle a record leaves it on the normal path`() {
        val sender = FakeSender(SendResult.Sent(messageId = 1, fileId = null, rawResponse = "{}"))
        val source = FakeSource(UploadSource.Resolved.Blocked("x"), handlesAll = false)

        assertEquals(UploadProcessor.Outcome.DONE, UploadProcessor(store, sender, source = source).process(ID))
        assertEquals(1, sender.calls)
    }

    private class FakeSource(
        private val resolved: UploadSource.Resolved,
        private val handlesAll: Boolean = true,
    ) : UploadSource {
        override fun handles(record: UploadRecord) = handlesAll
        override fun open(record: UploadRecord) = resolved
    }

    private companion object {
        const val ID = "rec_20261012_120000"
    }

    private class FakeSender(vararg results: SendResult) : DocumentSender {
        private val queue = ArrayDeque(results.toList())
        var calls = 0
        var lastCaption: String? = null

        override fun send(file: File, caption: String, onProgress: (Float) -> Unit): SendResult {
            calls++
            lastCaption = caption
            onProgress(1f)
            return if (queue.size > 1) queue.removeFirst() else queue.first()
        }
    }

    private class FakeStore : UploadStore {
        private val records = mutableMapOf<String, UploadRecord>()

        fun add(file: File) {
            records[file.nameWithoutExtension] =
                UploadRecord(file.nameWithoutExtension, file.absolutePath, UploadStatus.PENDING)
        }

        override fun get(recordingId: String) = records[recordingId]

        private fun edit(id: String, change: (UploadRecord) -> UploadRecord) {
            records[id] = change(records.getValue(id))
        }

        override fun markUploading(recordingId: String) =
            edit(recordingId) { it.copy(status = UploadStatus.UPLOADING, progress = 0f, attempts = it.attempts + 1) }

        override fun updateProgress(recordingId: String, progress: Float) =
            edit(recordingId) { it.copy(progress = progress) }

        override fun markUploaded(recordingId: String, messageId: Long, fileId: String?, response: String) =
            edit(recordingId) {
                it.copy(status = UploadStatus.UPLOADED, telegramMessageId = messageId, telegramFileId = fileId)
            }

        override fun markPending(recordingId: String, error: String) =
            edit(recordingId) { it.copy(status = UploadStatus.PENDING, lastError = error) }

        override fun markFailed(recordingId: String, error: String) =
            edit(recordingId) { it.copy(status = UploadStatus.FAILED, lastError = error) }
    }
}
