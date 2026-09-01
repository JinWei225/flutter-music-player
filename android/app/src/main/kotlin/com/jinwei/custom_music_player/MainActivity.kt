package com.jinwei.custom_music_player

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Build
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity rather than FlutterActivity: audio_service needs the
// activity to participate in the media session's lifecycle.
class MainActivity : AudioServiceActivity() {
    private companion object {
        const val CHANNEL = "com.jinwei.custom_music_player/library"
        const val PERMISSION_REQUEST = 4711
    }

    /** Held while the system permission dialog is up. */
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureAudioPermission" -> ensureAudioPermission(result)
                    "queryAudio" -> {
                        try {
                            result.success(queryAudio())
                        } catch (e: Exception) {
                            result.error("QUERY_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // --- permission ----------------------------------------------------------

    /** Android 13 split media access out of the broad storage permission. */
    private fun audioPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun ensureAudioPermission(result: MethodChannel.Result) {
        val permission = audioPermission()
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        // Only one dialog can be in flight; a second caller is told "not yet"
        // rather than being left without a reply.
        if (pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        requestPermissions(arrayOf(permission), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    // --- library -------------------------------------------------------------

    /**
     * Reads the device's audio library from MediaStore.
     *
     * MediaStore has already parsed the tags, so this returns the same fields
     * the desktop tag parsers produce, keyed identically. Playback uses the
     * content:// URI rather than a file path, which is the only form that
     * works under scoped storage.
     */
    @Suppress("DEPRECATION")
    private fun queryAudio(): List<Map<String, Any?>> {
        val columns = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.YEAR,
            // DATA is deprecated but still populated for shared-storage media,
            // and it is the only way to re-read tags ourselves when the
            // scanner got them wrong. Playback still uses the content:// URI.
            MediaStore.Audio.Media.DATA,
        )
        // ALBUM_ARTIST only exists from API 30; without it a compilation falls
        // back to the per-track artist, which is the desktop behaviour too.
        val hasAlbumArtist = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        if (hasAlbumArtist) columns.add(MediaStore.Audio.Media.ALBUM_ARTIST)

        val rows = mutableListOf<Map<String, Any?>>()
        val cursor: Cursor? = contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            columns.toTypedArray(),
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.ARTIST} ASC, ${MediaStore.Audio.Media.ALBUM} ASC, ${MediaStore.Audio.Media.TRACK} ASC",
        )

        cursor?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val trackCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val durationCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val yearCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            val dataCol = c.getColumnIndex(MediaStore.Audio.Media.DATA)
            val albumArtistCol =
                if (hasAlbumArtist) c.getColumnIndex(MediaStore.Audio.Media.ALBUM_ARTIST) else -1

            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                val uri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                )

                // MediaStore packs disc and track as disc*1000 + track.
                val rawTrack = if (c.isNull(trackCol)) 0 else c.getInt(trackCol)
                val disc = if (rawTrack > 1000) rawTrack / 1000 else null
                val track = if (rawTrack > 1000) rawTrack % 1000 else rawTrack

                val year = if (c.isNull(yearCol)) null else c.getInt(yearCol)

                rows.add(
                    mapOf(
                        "source" to uri.toString(),
                        "title" to c.getString(titleCol),
                        "artist" to c.getString(artistCol),
                        "album" to c.getString(albumCol),
                        "albumArtist" to
                            if (albumArtistCol >= 0) c.getString(albumArtistCol) else null,
                        "trackNumber" to if (track > 0) track else null,
                        "discNumber" to disc,
                        "durationMs" to
                            if (c.isNull(durationCol)) null else c.getLong(durationCol),
                        "year" to year?.takeIf { it > 0 }?.toString(),
                        "path" to if (dataCol >= 0) c.getString(dataCol) else null,
                    )
                )
            }
        }
        return rows
    }
}
