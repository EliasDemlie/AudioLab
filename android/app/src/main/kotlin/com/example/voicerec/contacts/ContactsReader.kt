package com.example.voicerec.contacts

import android.content.ContentResolver
import android.database.Cursor
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Organization
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.CommonDataKinds.StructuredName
import android.provider.ContactsContract.Data
import android.util.Log

/**
 * Reads contacts from the Contacts Provider, limited to names, phone numbers,
 * emails and organization. Requires `READ_CONTACTS`; throws [SecurityException]
 * without it.
 */
class ContactsReader(private val resolver: ContentResolver) {

    fun read(): List<ContactCard> {
        val contacts = LinkedHashMap<Long, Builder>()
        val cursor = resolver.query(
            Data.CONTENT_URI,
            PROJECTION,
            "${Data.MIMETYPE} IN (?, ?, ?, ?)",
            arrayOf(
                StructuredName.CONTENT_ITEM_TYPE,
                Phone.CONTENT_ITEM_TYPE,
                Email.CONTENT_ITEM_TYPE,
                Organization.CONTENT_ITEM_TYPE,
            ),
            "${Data.DISPLAY_NAME} COLLATE NOCASE ASC",
        ) ?: throw IllegalStateException("Contacts provider is unavailable")

        var skipped = 0
        cursor.use {
            while (it.moveToNext()) {
                try {
                    val id = it.getLong(0)
                    val builder = contacts.getOrPut(id) { Builder(it.stringAt(2)) }
                    builder.add(it)
                } catch (e: Exception) {
                    // A malformed row shouldn't stop the whole backup.
                    skipped++
                }
            }
        }
        if (skipped > 0) Log.w(TAG, "Skipped $skipped malformed contact rows")
        return contacts.values.map { it.build() }
    }

    private class Builder(private val displayName: String?) {
        private var name: StructuredNameRow? = null
        private val phones = mutableListOf<ContactCard.Phone>()
        private val emails = mutableListOf<ContactCard.Email>()
        private var organization: String? = null
        private var title: String? = null

        fun add(cursor: Cursor) {
            when (cursor.getString(1)) {
                StructuredName.CONTENT_ITEM_TYPE -> if (name == null) {
                    // DATA2 given, DATA3 family, DATA4 prefix, DATA5 middle, DATA6 suffix.
                    name = StructuredNameRow(
                        given = cursor.stringAt(4),
                        family = cursor.stringAt(5),
                        prefix = cursor.stringAt(6),
                        middle = cursor.stringAt(7),
                        suffix = cursor.stringAt(8),
                    )
                }
                Phone.CONTENT_ITEM_TYPE -> cursor.stringAt(3)?.let {
                    phones += ContactCard.Phone(it, phoneType(cursor.intAt(4)))
                }
                Email.CONTENT_ITEM_TYPE -> cursor.stringAt(3)?.let {
                    emails += ContactCard.Email(it, emailType(cursor.intAt(4)))
                }
                Organization.CONTENT_ITEM_TYPE -> if (organization == null && title == null) {
                    // DATA1 company, DATA4 title.
                    organization = cursor.stringAt(3)
                    title = cursor.stringAt(6)
                }
            }
        }

        fun build() = ContactCard(
            displayName = displayName,
            givenName = name?.given,
            familyName = name?.family,
            middleName = name?.middle,
            prefix = name?.prefix,
            suffix = name?.suffix,
            phones = phones,
            emails = emails,
            organization = organization,
            title = title,
        )
    }

    private data class StructuredNameRow(
        val given: String?,
        val family: String?,
        val prefix: String?,
        val middle: String?,
        val suffix: String?,
    )

    private companion object {
        const val TAG = "ContactsReader"

        // Indexes are used above: 0 id, 1 mimetype, 2 display name, 3–8 DATA1–DATA6.
        val PROJECTION = arrayOf(
            Data.CONTACT_ID,
            Data.MIMETYPE,
            Data.DISPLAY_NAME,
            Data.DATA1,
            Data.DATA2,
            Data.DATA3,
            Data.DATA4,
            Data.DATA5,
            Data.DATA6,
        )

        fun Cursor.stringAt(index: Int): String? = if (isNull(index)) null else getString(index)

        fun Cursor.intAt(index: Int): Int = if (isNull(index)) 0 else getInt(index)

        fun phoneType(type: Int) = when (type) {
            Phone.TYPE_MOBILE -> "CELL"
            Phone.TYPE_HOME -> "HOME,VOICE"
            Phone.TYPE_WORK -> "WORK,VOICE"
            Phone.TYPE_FAX_WORK -> "WORK,FAX"
            Phone.TYPE_FAX_HOME -> "HOME,FAX"
            Phone.TYPE_PAGER -> "PAGER"
            else -> "VOICE"
        }

        fun emailType(type: Int) = when (type) {
            Email.TYPE_HOME -> "INTERNET,HOME"
            Email.TYPE_WORK -> "INTERNET,WORK"
            else -> "INTERNET"
        }
    }
}
