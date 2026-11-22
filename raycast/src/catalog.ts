import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

/**
 * The album list Mewsic shares after every library scan (see
 * lib/platform/album_catalog.dart in the app). The app is sandboxed, so this
 * file is the only way to see its library from outside.
 */
export const SHARED_FOLDER = join(homedir(), "Library", "Application Support", "Mewsic");
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
  } catch {
    throw new CatalogError("Mewsic has not shared its albums yet.", "missing");
  }
  const json = JSON.parse(text) as { format?: number; albums?: Album[] };
  if (json.format !== FORMAT || !Array.isArray(json.albums)) {
    throw new CatalogError("This Mewsic writes a newer album list than the extension reads.", "format");
  }
  return json.albums;
}

const run = promisify(execFile);

/**
 * Hands a mewsic:// link to the app. Playing happens with Mewsic left in the
 * background (`open -g`), so Raycast closes onto whatever you were doing;
 * opening an album brings the window forward.
 */
export async function openLink(link: string, { background }: { background: boolean }) {
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
