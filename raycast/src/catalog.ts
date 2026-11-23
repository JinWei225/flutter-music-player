import { open } from "@raycast/api";
import { execFile, spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, normalize } from "node:path";
import { promisify } from "node:util";

/**
 * Where Mewsic shares its files: ~/Library/Application Support/Mewsic on the
 * Mac, ~\.mewsic on Windows (not %LOCALAPPDATA%: Raycast's extensions cannot
 * see files there).
 */
function sharedFolder(): string {
  if (process.platform === "win32") {
    return join(homedir(), ".mewsic");
  }
  return join(homedir(), "Library", "Application Support", "Mewsic");
}

/**
 * The album list Mewsic shares after every library scan (see
 * lib/platform/album_catalog.dart in the app). The Mac app is sandboxed, so
 * this file is the only way to see its library from outside.
 */
export const SHARED_FOLDER = sharedFolder();
export const CATALOG_PATH = join(SHARED_FOLDER, "albums.json");

/** The file shape this extension understands; the app writes the same number. */
const FORMAT = 1;

export type AlbumAction = "open" | "play" | "shuffle" | "next";

export interface Album {
  id: string;
  name: string;
  artist: string;
  year: string | null;
  songs: number;
  seconds: number;
  /** Absolute path to a PNG of the cover, or null when the album has none. */
  cover: string | null;
  /** The mewsic:// link for each action. The app builds them; we only open them. */
  links: Record<AlbumAction, string>;
  tracks: Track[];
}

export type SongAction = "play" | "next";

export interface Track {
  title: string;
  artist: string;
  number: number | null;
  disc: number | null;
  seconds: number | null;
  /** "play" plays from this song with the rest of its album after it; "next" queues just the song. */
  links: Record<SongAction, string>;
}

export class CatalogError extends Error {
  constructor(
    message: string,
    readonly kind: "missing" | "format",
  ) {
    super(message);
  }
}

export async function loadAlbums(): Promise<Album[]> {
  let text: string;
  try {
    text = await readFile(CATALOG_PATH, "utf8");
  } catch (error) {
    console.error(`Could not read ${CATALOG_PATH}:`, error);
    throw new CatalogError("Mewsic has not shared its albums yet.", "missing");
  }
  const json = JSON.parse(text) as { format?: number; albums?: Album[] };
  if (json.format !== FORMAT || !Array.isArray(json.albums)) {
    throw new CatalogError("This Mewsic writes a newer album list than the extension reads.", "format");
  }
  // The app joins paths with "/", which on Windows leaves "\" and "/" mixed;
  // Raycast wants one style for an image path.
  return json.albums.map((album) => ({ ...album, cover: album.cover ? normalize(album.cover) : null }));
}

const run = promisify(execFile);

/**
 * Hands a mewsic:// link to the app. Playing happens with Mewsic left in the
 * background (`open -g`), so Raycast closes onto whatever you were doing;
 * opening an album brings the window forward.
 *
 * On Windows the link goes to the registered mewsic:// handler, and the app
 * itself decides whether to come forward (see link_router.cpp): only for
 * opening an album or the search prompt.
 */
export async function openLink(link: string, { background }: { background: boolean }) {
  if (process.platform === "win32") {
    // Raycast is a packaged app and may not see the mewsic: handler Mewsic
    // registers, so start Mewsic itself (it hands the link to the running
    // copy). Mewsic writes where it lives to app.txt; the handler is the
    // fallback.
    try {
      const exe = (await readFile(join(SHARED_FOLDER, "app.txt"), "utf8")).trim();
      await new Promise<void>((resolve, reject) => {
        // Detached: on a cold start this process is the app and never exits.
        const child = spawn(exe, [link], { detached: true, stdio: "ignore", windowsHide: true });
        child.once("error", reject);
        child.once("spawn", () => {
          child.unref();
          resolve();
        });
      });
    } catch {
      await open(link);
    }
    return;
  }
  await run("/usr/bin/open", background ? ["-g", link] : [link]);
}

/** Every song in the library, each with the album it belongs to. */
export function songsOf(albums: Album[]): { track: Track; album: Album }[] {
  return albums.flatMap((album) => (album.tracks ?? []).map((track) => ({ track, album })));
}

/** "2023 · 6 songs · 17:44" */
export function describe(album: Album): string {
  const songs = album.songs === 1 ? "1 song" : `${album.songs} songs`;
  return [album.year, songs, formatDuration(album.seconds)].filter(Boolean).join(" · ");
}

export function formatDuration(total: number): string {
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = String(total % 60).padStart(2, "0");
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${seconds}` : `${minutes}:${seconds}`;
}
