package com.example.voicerec.contacts

import java.io.Writer
import java.util.Locale

/** The contact fields we back up. Nothing else (photos, addresses, notes) is read. */
data class ContactCard(
    val displayName: String? = null,
    val givenName: String? = null,
    val familyName: String? = null,
    val middleName: String? = null,
    val prefix: String? = null,
    val suffix: String? = null,
    val phones: List<Phone> = emptyList(),
    val emails: List<Email> = emptyList(),
    val organization: String? = null,
    val title: String? = null,
) {
    /** [type] is a vCard TYPE value, e.g. `CELL` or `WORK,FAX`. */
    data class Phone(val number: String, val type: String = "VOICE")
    data class Email(val address: String, val type: String = "INTERNET")

    /** Best name to show: display name, then structured name, organization, phone or email. */
    val formattedName: String
        get() = displayName.clean()
            ?: listOfNotNull(givenName.clean(), middleName.clean(), familyName.clean())
                .joinToString(" ").ifBlank { null }
            ?: organization.clean()
            ?: phones.firstOrNull()?.number
            ?: emails.firstOrNull()?.address
            ?: ""

    val hasContent: Boolean
        get() = formattedName.isNotBlank()
}

private fun String?.clean(): String? = this?.trim()?.takeIf { it.isNotEmpty() }

object ContactCards {
    /**
     * Drops empty entries, removes repeated numbers/emails within a contact,
     * and removes duplicate contacts (same name, numbers and emails).
     */
    fun normalize(cards: List<ContactCard>): List<ContactCard> {
        val seen = HashSet<String>()
        return cards.mapNotNull { card ->
            val cleaned = card.copy(
                phones = card.phones
                    .filter { it.number.isNotBlank() }
                    .distinctBy { phoneKey(it.number) },
                emails = card.emails
                    .filter { it.address.isNotBlank() }
                    .distinctBy { it.address.trim().lowercase(Locale.ROOT) },
            )
            if (!cleaned.hasContent) return@mapNotNull null

            val key = listOf(
                cleaned.formattedName.trim().lowercase(Locale.ROOT),
                cleaned.phones.map { phoneKey(it.number) }.sorted().joinToString(","),
                cleaned.emails.map { it.address.trim().lowercase(Locale.ROOT) }.sorted().joinToString(","),
            ).joinToString("|")
            if (seen.add(key)) cleaned else null
        }
    }

    /** `+251 91-123 4567` and `+251911234567` are the same number. */
    private fun phoneKey(number: String) = number.filter { it.isDigit() || it == '+' }
}

/** Writes vCard 3.0 (RFC 2426): UTF-8, CRLF line endings, escaped values, folded lines. */
object VCardWriter {
    private const val MAX_LINE_OCTETS = 75

    fun write(cards: List<ContactCard>, out: Writer) {
        cards.forEach { out.write(card(it)) }
    }

    fun card(card: ContactCard): String = buildString {
        line("BEGIN:VCARD")
        line("VERSION:3.0")
        line(
            "N:" + listOf(card.familyName, card.givenName, card.middleName, card.prefix, card.suffix)
                .joinToString(";") { escape(it.orEmpty().trim()) },
        )
        line("FN:" + escape(card.formattedName))
        card.organization.clean()?.let { line("ORG:" + escape(it)) }
        card.title.clean()?.let { line("TITLE:" + escape(it)) }
        card.phones.forEach { line("TEL;TYPE=${it.type}:" + escape(it.number.trim())) }
        card.emails.forEach { line("EMAIL;TYPE=${it.type}:" + escape(it.address.trim())) }
        line("END:VCARD")
    }

    /** Escapes `\`, `;`, `,` and newlines in a property value. */
    fun escape(value: String): String = value
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")
        .replace("\r", "\\n")

    /**
     * Folds a content line at 75 octets. Splits only between code points, so
     * multi-byte UTF-8 characters (e.g. Amharic) are never cut in half.
     */
    fun fold(line: String): String {
        val result = StringBuilder()
        var octets = 0
        var limit = MAX_LINE_OCTETS
        var i = 0
        while (i < line.length) {
            val codePoint = line.codePointAt(i)
            val size = utf8Size(codePoint)
            if (octets + size > limit) {
                result.append("\r\n ")
                octets = 0
                limit = MAX_LINE_OCTETS - 1 // the leading space counts
            }
            result.appendCodePoint(codePoint)
            octets += size
            i += Character.charCount(codePoint)
        }
        return result.toString()
    }

    private fun StringBuilder.line(content: String) {
        append(fold(content)).append("\r\n")
    }

    private fun utf8Size(codePoint: Int) = when {
        codePoint < 0x80 -> 1
        codePoint < 0x800 -> 2
        codePoint < 0x10000 -> 3
        else -> 4
    }
}
