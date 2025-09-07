package com.example.voicerec.contacts

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.StringWriter

class VCardTest {

    @Test
    fun `writes a complete vCard 3_0 entry`() {
        val card = ContactCard(
            displayName = "Abebe Kebede",
            givenName = "Abebe",
            familyName = "Kebede",
            phones = listOf(ContactCard.Phone("+251 911 234 567", "CELL")),
            emails = listOf(ContactCard.Email("abebe@example.com", "INTERNET,WORK")),
            organization = "Vintech",
            title = "Engineer",
        )

        assertEquals(
            "BEGIN:VCARD\r\n" +
                "VERSION:3.0\r\n" +
                "N:Kebede;Abebe;;;\r\n" +
                "FN:Abebe Kebede\r\n" +
                "ORG:Vintech\r\n" +
                "TITLE:Engineer\r\n" +
                "TEL;TYPE=CELL:+251 911 234 567\r\n" +
                "EMAIL;TYPE=INTERNET,WORK:abebe@example.com\r\n" +
                "END:VCARD\r\n",
            VCardWriter.card(card),
        )
    }

    @Test
    fun `escapes special characters`() {
        assertEquals("a\\;b\\,c\\\\d\\ne", VCardWriter.escape("a;b,c\\d\ne"))
    }

    @Test
    fun `keeps Amharic names intact`() {
        val vcard = VCardWriter.card(ContactCard(displayName = "አበበ ከበደ", phones = listOf(ContactCard.Phone("0911"))))
        assertTrue(vcard.contains("FN:አበበ ከበደ\r\n"))
    }

    @Test
    fun `folds long lines at 75 octets without splitting characters`() {
        val longName = "ሰላም".repeat(40) // 120 chars, 360 UTF-8 bytes
        val folded = VCardWriter.fold("FN:$longName")

        val lines = folded.split("\r\n")
        assertTrue(lines.size > 1)
        lines.forEach { assertTrue(it.toByteArray(Charsets.UTF_8).size <= 75) }
        lines.drop(1).forEach { assertTrue(it.startsWith(" ")) }
        // Unfolding gives back the original text.
        assertEquals("FN:$longName", folded.replace("\r\n ", ""))
    }

    @Test
    fun `falls back to phone number when contact has no name`() {
        val card = ContactCard(phones = listOf(ContactCard.Phone("0911000000")))
        assertTrue(VCardWriter.card(card).contains("FN:0911000000\r\n"))
    }

    @Test
    fun `normalize drops empty contacts and duplicates`() {
        val abebe = ContactCard(displayName = "Abebe", phones = listOf(ContactCard.Phone("+251911234567")))
        val cards = listOf(
            abebe,
            abebe.copy(phones = listOf(ContactCard.Phone("+251 911-234-567"))), // same number, other format
            ContactCard(displayName = "  "), // nothing to save
            ContactCard(displayName = "Almaz"),
        )

        val result = ContactCards.normalize(cards)

        assertEquals(listOf("Abebe", "Almaz"), result.map { it.formattedName })
    }

    @Test
    fun `normalize removes repeated numbers and emails within a contact`() {
        val card = ContactCard(
            displayName = "Sara",
            phones = listOf(ContactCard.Phone("0911 11 11 11"), ContactCard.Phone("0911111111"), ContactCard.Phone(" ")),
            emails = listOf(ContactCard.Email("Sara@Example.com"), ContactCard.Email("sara@example.com")),
        )

        val result = ContactCards.normalize(listOf(card)).single()

        assertEquals(1, result.phones.size)
        assertEquals(1, result.emails.size)
    }

    @Test
    fun `writes all cards`() {
        val out = StringWriter()
        VCardWriter.write(listOf(ContactCard(displayName = "A"), ContactCard(displayName = "B")), out)
        assertEquals(2, out.toString().split("BEGIN:VCARD").size - 1)
    }
}
