package com.example.voicerec.photos

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import com.example.voicerec.backup.TelegramBackup
import com.example.voicerec.backup.UploadStatus
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit


object PhotoBackup {
    private const val DRAIN_WORK = "photo-upload-drain"
    private const val TRIGGER_WORK = "photo-scan-trigger"
    private const val PERIODIC_WORK = "photo-scan-periodic"
    private const val PERIODIC_HOURS = 6L

    val executor: ExecutorService = Executors.newSingleThreadExecutor()

    private fun settings(context: Context) = PhotoSettings(context)

    // --- user actions ------------------------------------------------------------

    /** Call only after the user has agreed and Android access is granted. */
    fun enable(context: Context, includeExisting: Boolean) {
        val s = settings(context)
        s.enabled = true
        s.paused = false
        s.includeExisting = includeExisting
        s.resetScanPosition()
        ensureWatchers(context)
        scanAsync(context)
    }

    /**
     * Stops discovery and scheduling. Pending items are removed if [clearPending],
     * otherwise kept (and resumed if the user turns backup on again).
     */
    fun disable(context: Context, clearPending: Boolean) {
        settings(context).apply { enabled = false; paused = false }
        val work = WorkManager.getInstance(context)
        work.cancelUniqueWork(TRIGGER_WORK)
        work.cancelUniqueWork(PERIODIC_WORK)
        work.cancelUniqueWork(DRAIN_WORK)
        val store = TelegramBackup.uploadStore(context)
        if (clearPending) store.deleteUnfinishedByPrefix(PhotoRules.ID_PREFIX)
        else store.requeueInterrupted(PhotoRules.ID_PREFIX)
        PhotoSource.clearStaging(context)
    }

    fun setPaused(context: Context, paused: Boolean) {
        val s = settings(context)
        if (!s.enabled) return
        s.paused = paused
        if (!paused) scanAsync(context, forceDrain = true)
    }

    fun setWifiOnly(context: Context, wifiOnly: Boolean) {
        val s = settings(context)
        if (s.wifiOnly == wifiOnly) return
        s.wifiOnly = wifiOnly
        // Replace the scheduled drain so the new network constraint applies.
        if (s.enabled && !s.paused) scheduleDrain(context, replace = true)
    }

    fun setMaxFileMb(context: Context, mb: Int) {
        val s = settings(context)
        if (s.maxFileMb == PhotoRules.clampMaxFileMb(mb)) return
        s.maxFileMb = mb
        // Photos skipped for size may now qualify; rescan (the queue prevents duplicates).
        s.resetScanPosition()
        scanAsync(context)
    }

    fun setIncludeExisting(context: Context, include: Boolean) {
        val s = settings(context)
        if (s.includeExisting == include) return
        s.includeExisting = include
        s.resetScanPosition()
        scanAsync(context)
    }

    fun retryFailed(context: Context) {
        TelegramBackup.uploadStore(context).resetFailedByPrefix(PhotoRules.ID_PREFIX)
        scanAsync(context, forceDrain = true)
    }

    // --- discovery ---------------------------------------------------------------

    fun scanAsync(context: Context, forceDrain: Boolean = false) {
        val app = context.applicationContext
        executor.execute { runCatching { scan(app, forceDrain) } }
    }

    /**
     * Looks for new authorized photos and queues them. Does nothing unless the
     * feature is enabled, not paused, configured, and Android access is granted.
     * Returns the number of newly queued photos.
     */
    @Synchronized
    fun scan(context: Context, forceDrain: Boolean = false): Int {
        val s = settings(context)
        if (!s.enabled || s.paused || !TelegramBackup.isConfigured) return 0
        val access = PhotoAccess.current(context)
        if (access == PhotoAccess.NONE) return 0

        // The authorized set may have changed: look again and let blocked items retry.
        var resume = forceDrain
        if (access.wireName != s.lastAccess) {
            s.lastAccess = access.wireName
            s.scannedId = 0
            resume = true
        }

        val library = PhotoLibrary(context.contentResolver)
        if (access == PhotoAccess.FULL && !s.includeExisting && s.baselineId < 0) {
            s.baselineId = library.maxId()
        }
        // With a hand-picked selection every selected photo is eligible: the user chose it.
        val floor = if (access == PhotoAccess.FULL && !s.includeExisting) maxOf(s.baselineId, 0L) else 0L
        val after = if (access == PhotoAccess.FULL) maxOf(s.scannedId, floor) else floor

        val page = try {
            library.imagesAfter(after)
        } catch (e: SecurityException) {
            return 0
        }

        val maxBytes = PhotoRules.maxBytes(s.maxFileMb)
        val items = page.images
            .filter { PhotoRules.isEligible(it.mimeType, it.sizeBytes, maxBytes) }
            .map { PhotoRules.queueId(it.id) to PhotoLibrary.uriFor(it.id).toString() }
        val added = TelegramBackup.uploadStore(context).insertBatchIfAbsent(items)

        if (access == PhotoAccess.FULL) s.scannedId = page.lastIdSeen
        s.lastScanAtMillis = System.currentTimeMillis()
        if (added > 0 || resume) scheduleDrain(context)
        return added
    }

    // --- scheduling --------------------------------------------------------------

    /** Watches for new images (content trigger) and rescans every few hours as a safety net. */
    fun ensureWatchers(context: Context) {
        scheduleTrigger(context, ExistingWorkPolicy.KEEP)
        val periodic = PeriodicWorkRequest.Builder(PhotoScanWorker::class.java, PERIODIC_HOURS, TimeUnit.HOURS).build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(PERIODIC_WORK, ExistingPeriodicWorkPolicy.KEEP, periodic)
    }

    fun ensureWatchersIfEnabled(context: Context) {
        if (settings(context).enabled) ensureWatchers(context)
    }

    fun scheduleTrigger(context: Context, policy: ExistingWorkPolicy) {
        val request = OneTimeWorkRequest.Builder(PhotoScanWorker::class.java)
            .setConstraints(
                Constraints.Builder()
                    .addContentUriTrigger(PhotoLibrary.COLLECTION, true)
                    .setTriggerContentUpdateDelay(10, TimeUnit.SECONDS)
                    .setTriggerContentMaxDelay(1, TimeUnit.MINUTES)
                    .build(),
            )
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(TRIGGER_WORK, policy, request)
    }

    /** Starts (or keeps) the single job that uploads queued photos one by one. */
    fun scheduleDrain(context: Context, replace: Boolean = false, append: Boolean = false) {
        val network = if (settings(context).wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED
        val request = OneTimeWorkRequest.Builder(PhotoUploadWorker::class.java)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(network).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        val policy = when {
            replace -> ExistingWorkPolicy.REPLACE
            append -> ExistingWorkPolicy.APPEND_OR_REPLACE
            else -> ExistingWorkPolicy.KEEP
        }
        WorkManager.getInstance(context).enqueueUniqueWork(DRAIN_WORK, policy, request)
    }

    // --- state for the UI --------------------------------------------------------

    fun state(context: Context): Map<String, Any?> {
        val s = settings(context)
        val counts = TelegramBackup.uploadStore(context).countsByPrefix(PhotoRules.ID_PREFIX)
        return mapOf(
            "configured" to TelegramBackup.isConfigured,
            "enabled" to s.enabled,
            "promptShown" to s.promptShown,
            "paused" to s.paused,
            "access" to PhotoAccess.current(context).wireName,
            "includeExisting" to s.includeExisting,
            "wifiOnly" to s.wifiOnly,
            "maxFileMb" to s.maxFileMb,
            "maxFileMbLimit" to PhotoRules.MAX_FILE_MB_LIMIT,
            "lastScanAtMillis" to s.lastScanAtMillis.takeIf { it > 0 },
            "pending" to (counts[UploadStatus.PENDING.wireName] ?: 0),
            "uploading" to (counts[UploadStatus.UPLOADING.wireName] ?: 0),
            "uploaded" to (counts[UploadStatus.UPLOADED.wireName] ?: 0),
            "failed" to (counts[UploadStatus.FAILED.wireName] ?: 0),
            "sdkInt" to android.os.Build.VERSION.SDK_INT,
        )
    }
}
