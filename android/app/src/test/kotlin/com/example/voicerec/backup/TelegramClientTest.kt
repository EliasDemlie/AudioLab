package com.example.voicerec.backup

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.DataInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

class TelegramClientTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private lateinit var server: ServerSocket
    private lateinit var file: File
    @Volatile private var requestPath = ""
    @Volatile private var requestContentType = ""
    @Volatile private var requestBody = ""
    private var responseCode = 200
    private var responseBody = ""

    @Before
    fun setUp() {
        file = tmp.newFile("rec_1.m4a").apply { writeText("AUDIO-BYTES") }
        server = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
        thread(isDaemon = true) { serveOne() }
    }

    @After
    fun tearDown() = server.close()

    /** Minimal HTTP/1.1 server: reads one request and sends the canned response. */
    private fun serveOne() {
        val socket = try {
            server.accept()
        } catch (e: IOException) {
            return
        }
        socket.use {
            val input = it.getInputStream()
            val headers = readHeaders(input)
            val requestLine = headers.first()
            requestPath = requestLine.split(" ")[1]
            fun header(name: String) = headers.firstOrNull { h -> h.startsWith("$name:", ignoreCase = true) }
                ?.substringAfter(':')?.trim().orEmpty()
            requestContentType = header("Content-Type")
            val length = header("Content-Length").toInt()
            requestBody = ByteArray(length).also { body -> DataInputStream(input).readFully(body) }
                .toString(Charsets.UTF_8)

            val bytes = responseBody.toByteArray()
            it.getOutputStream().apply {
                write("HTTP/1.1 $responseCode X\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
                write(bytes)
                flush()
            }
        }
    }

    private fun readHeaders(input: InputStream): List<String> {
        val lines = mutableListOf<String>()
        val line = StringBuilder()
        while (true) {
            val c = input.read()
            if (c < 0) break
            if (c == '\n'.code) {
                val text = line.toString().trimEnd('\r')
                if (text.isEmpty()) break
                lines += text
                line.clear()
            } else {
                line.append(c.toChar())
            }
        }
        return lines
    }

    private fun client(token: String = "123:SECRET") =
        TelegramClient(token, "-100777", "http://127.0.0.1:${server.localPort}")

    @Test
    fun `sends multipart sendDocument with chat id, caption and file`() {
        responseBody = """{"ok":true,"result":{"message_id":55,"document":{"file_id":"FID"}}}"""
        var lastProgress = 0f

        val result = client().send(file, "My caption") { lastProgress = it }

        assertEquals(SendResult.Sent(55, "FID", responseBody), result)
        assertEquals("/bot123:SECRET/sendDocument", requestPath)
        assertTrue(requestContentType.startsWith("multipart/form-data; boundary="))
        assertTrue(requestBody.contains("name=\"chat_id\"\r\n\r\n-100777\r\n"))
        assertTrue(requestBody.contains("name=\"caption\"\r\n\r\nMy caption\r\n"))
        assertTrue(requestBody.contains("name=\"document\"; filename=\"rec_1.m4a\""))
        assertTrue(requestBody.contains("Content-Type: audio/mp4\r\n\r\nAUDIO-BYTES\r\n"))
        assertEquals(1f, lastProgress)
    }

    @Test
    fun `contacts file is sent as vcard with unicode intact`() {
        responseBody = """{"ok":true,"result":{"message_id":56,"document":{"file_id":"VCF"}}}"""
        val vcf = tmp.newFile("contacts_1.vcf").apply { writeText("FN:አበበ\r\n", Charsets.UTF_8) }

        val result = client().send(vcf, "Contacts backup") {}

        assertEquals(SendResult.Sent(56, "VCF", responseBody), result)
        assertTrue(requestBody.contains("filename=\"contacts_1.vcf\"\r\nContent-Type: text/vcard\r\n\r\nFN:አበበ"))
    }

    @Test
    fun `server error is retryable`() {
        responseCode = 502
        responseBody = """{"ok":false,"error_code":502,"description":"Bad Gateway"}"""

        assertTrue(client().send(file, "") {} is SendResult.Retryable)
    }

    @Test
    fun `invalid token is permanent`() {
        responseCode = 401
        responseBody = """{"ok":false,"error_code":401,"description":"Unauthorized"}"""

        assertEquals(SendResult.Permanent("Bot token is invalid or revoked."), client().send(file, "") {})
    }

    @Test
    fun `network failure is retryable and does not leak the token`() {
        val closedPort = ServerSocket(0).use { it.localPort }
        val offline = TelegramClient("123:SECRET", "-100777", "http://127.0.0.1:$closedPort")

        val result = offline.send(file, "") {}

        assertTrue(result is SendResult.Retryable)
        assertTrue(!(result as SendResult.Retryable).message.contains("SECRET"))
    }

    @Test
    fun `missing configuration fails without a request`() {
        val result = client(token = "").send(file, "") {}

        assertEquals(SendResult.Permanent("Telegram backup is not configured."), result)
        assertEquals("", requestPath)
    }

    @Test
    fun `classify maps telegram errors`() {
        assertTrue(TelegramClient.classify(429, """{"ok":false,"parameters":{"retry_after":5}}""") is SendResult.Retryable)
        assertTrue(TelegramClient.classify(400, """{"ok":false,"description":"chat not found"}""") is SendResult.Permanent)
        assertTrue(TelegramClient.classify(403, """{"ok":false,"description":"Forbidden"}""") is SendResult.Permanent)
        assertTrue(TelegramClient.classify(413, "") is SendResult.Permanent)
        assertTrue(TelegramClient.classify(200, "not json") is SendResult.Retryable)
    }
}
