package com.example.voicerec.photos

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhotoRulesTest {
    @Test
    fun `queue id is based on the media id, not the file name`() {
        assertEquals("photo_42", PhotoRules.queueId(42))
        assertEquals(false, PhotoRules.queueId(42) == PhotoRules.queueId(43))
    }

    @Test
    fun `supports common image formats but not svg or video`() {
        listOf("image/jpeg", "image/png", "image/webp", "image/heic", "image/gif").forEach {
            assertTrue(it, PhotoRules.isSupportedImage(it))
        }
        assertFalse(PhotoRules.isSupportedImage("image/svg+xml"))
        assertFalse(PhotoRules.isSupportedImage("video/mp4"))
        assertFalse(PhotoRules.isSupportedImage(null))
    }

    @Test
    fun `size filter rejects empty and oversized files`() {
        val max = PhotoRules.maxBytes(10)
        assertTrue(PhotoRules.isEligible("image/jpeg", 1, max))
        assertTrue(PhotoRules.isEligible("image/jpeg", max, max))
        assertFalse(PhotoRules.isEligible("image/jpeg", 0, max))
        assertFalse(PhotoRules.isEligible("image/jpeg", max + 1, max))
    }

    @Test
    fun `max size is capped at the Telegram limit`() {
        assertEquals(50, PhotoRules.clampMaxFileMb(500))
        assertEquals(1, PhotoRules.clampMaxFileMb(0))
    }

    @Test
    fun `file names are sanitized and keep an extension`() {
        assertEquals("IMG_0001.jpg", PhotoRules.safeFileName("IMG_0001.jpg", 1, "image/jpeg"))
        val name = PhotoRules.safeFileName("a/b\"..png", 1, "image/png")
        assertFalse(name.contains('/') || name.contains('"'))
        assertTrue(name.endsWith(".png"))
        assertEquals("photo_7.heic", PhotoRules.safeFileName(null, 7, "image/heic"))
    }
}
