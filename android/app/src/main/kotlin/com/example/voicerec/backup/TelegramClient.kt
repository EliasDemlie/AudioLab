package com.example.voicerec.backup

import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

sealed interface SendResult {
    data class Sent(val messageId: Long, val fileId: String?, val rawResponse: String) : SendResult

    /** Temporary problem (network, rate limit, server error): try again later. */
    data class Retryable(val message: String) : SendResult

    /** Retrying won't help (bad token, bot not in channel, file too large…). */
    data class Permanent(val message: String) : SendResult
}

fun interface DocumentSender {
    fun send(file: File, caption: String, onProgress: (Float) -> Unit): SendResult
}

/**
 * Uploads a file with the Telegram Bot API `sendDocument` (multipart/form-data).
 *
 * The token is part of the request URL, so neither the URL nor raw exception
 * messages are ever logged or returned.
 */
class TelegramClient(
    private val botToken: String,
    private val chatId: String,
    private val baseUrl: String = "https://api.telegram.org",
) : DocumentSender {

    override fun send(file: File, caption: String, onProgress: (Float) -> Unit): SendResult {
        if (botToken.isBlank() || chatId.isBlank()) {
            return SendResult.Permanent("Telegram backup is not configured.")
        }

        val boundary = "voicerec-" + UUID.randomUUID().toString().replace("-", "")
        val head = buildString {
            appendField(boundary, "chat_id", chatId)
            if (caption.isNotBlank()) appendField(boundary, "caption", caption.take(MAX_CAPTION_LENGTH))
            append("--$boundary\r\n")
            append("Content-Disposition: form-data; name=\"document\"; filename=\"${file.name}\"\r\n")
            append("Content-Type: ${mimeType(file)}\r\n\r\n")
        }.toByteArray(Charsets.UTF_8)
        val tail = "\r\n--$boundary--\r\n".toByteArray(Charsets.UTF_8)
        val totalBytes = head.size + file.length() + tail.size

        var connection: HttpURLConnection? = null
        return try {
            connection = (URL("$baseUrl/bot$botToken/sendDocument").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                // Fixed length streams the body as we write it, so progress is real.
                setFixedLengthStreamingMode(totalBytes)
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            }

            connection.outputStream.use { out ->
                out.write(head)
                var sent = head.size.toLong()
                file.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        out.write(buffer, 0, read)
                        sent += read
                        onProgress(sent.toFloat() / totalBytes)
                    }
                }
                out.write(tail)
            }
            onProgress(1f)

            val code = connection.responseCode
            val stream = if (code < 400) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            classify(code, body)
        } catch (e: IOException) {
            // Only the exception type: messages can contain the request URL.
            SendResult.Retryable("Network error (${e.javaClass.simpleName}). Will retry when online.")
        } finally {
            connection?.disconnect()
        }
    }

    private fun StringBuilder.appendField(boundary: String, name: String, value: String) {
        append("--$boundary\r\n")
        append("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
        append(value).append("\r\n")
    }

    private fun mimeType(file: File) = when (file.extension) {
        "aac" -> "audio/aac"
        "vcf" -> "text/vcard"
        else -> "audio/mp4"
    }

    companion object {
        /** Bot API limit for uploads: 50 MB. */
        const val MAX_FILE_BYTES = 50L * 1000 * 1000
        private const val MAX_CAPTION_LENGTH = 1024
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 120_000

        /** Maps a Bot API response to a [SendResult]. */
        fun classify(code: Int, body: String): SendResult {
            val json = runCatching { JSONObject(body) }.getOrNull()
            val description = json?.optString("description")?.takeIf { it.isNotBlank() } ?: "HTTP $code"

            if (code == 200 && json?.optBoolean("ok") == true) {
                val result = json.optJSONObject("result")
                val messageId = result?.optLong("message_id", -1L) ?: -1L
                if (messageId < 0) return SendResult.Retryable("Unexpected Telegram response.")
                val fileId = listOf("document", "audio", "voice").firstNotNullOfOrNull { key ->
                    result?.optJSONObject(key)?.optString("file_id")?.takeIf { it.isNotEmpty() }
                }
                return SendResult.Sent(messageId, fileId, body)
            }

            return when {
                code == 429 -> {
                    val retryAfter = json?.optJSONObject("parameters")?.optInt("retry_after", 0) ?: 0
                    SendResult.Retryable("Rate limited by Telegram (retry after ${retryAfter}s).")
                }
                code >= 500 -> SendResult.Retryable("Telegram server error: $description")
                code == 401 || code == 404 -> SendResult.Permanent("Bot token is invalid or revoked.")
                code == 403 -> SendResult.Permanent("Bot can't post to the channel. Make it a channel admin. ($description)")
                code == 413 -> SendResult.Permanent("File is too large for Telegram.")
                code == 400 -> SendResult.Permanent("Telegram rejected the upload: $description")
                else -> SendResult.Retryable("Unexpected Telegram response: $description")
            }
        }
    }
}
