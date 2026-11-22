import { showHUD } from "@raycast/api";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { openLink, SHARED_FOLDER } from "./catalog";

/**
 * The player commands Mewsic takes as mewsic://control links, as spelled in
 * the link. (Unlike album and song links, these never change, so the
 * extension writes them itself.)
 */
export type Control = "play-pause" | "next" | "previous" | "shuffle" | "shuffle-all";

/** What Mewsic writes to player.json whenever the song, play state or shuffle changes. */
interface PlayerStatus {
  /** The id of the last control link Mewsic carried out. */
  handled: string | null;
  playing: boolean;
  shuffle: boolean;
  repeat: string;
  track: { title: string; artist: string; album: string } | null;
}

const STATUS_PATH = join(SHARED_FOLDER, "player.json");

async function readStatus(): Promise<PlayerStatus | null> {
  try {
    return JSON.parse(await readFile(STATUS_PATH, "utf8")) as PlayerStatus;
  } catch {
    // Missing, or caught mid-rename: try again on the next poll.
    return null;
  }
}

/**
 * Sends [control] to Mewsic, leaving it in the background, then says what
 * happened. The link carries an id, which Mewsic writes back to player.json
 * once the command has taken effect; we wait for that rather than for any
 * change to the file, because a cold start first rewrites it with the fresh
 * app's empty player. "Shuffle all" may also wait for the library scan, so
 * the wait is generous; it ends as soon as the id shows up.
 */
export async function runControl(control: Control) {
  const id = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
  await openLink(`mewsic://control?do=${control}&id=${id}`, { background: true });

  let status: PlayerStatus | null = null;
  for (let waited = 0; waited < 15000; waited += 100) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    status = (await readStatus()) ?? status;
    if (status?.handled === id) break;
  }
  await showHUD(describe(control, status));
}

function describe(control: Control, status: PlayerStatus | null): string {
  if (control === "shuffle") return status?.shuffle ? "Shuffle on" : "Shuffle off";
  if (!status?.track) return "Nothing playing in Mewsic";
  const { track } = status;
  const song = `${track.title} — ${track.artist}`;
  if (!status.playing) return `Paused: ${song}`;
  return control === "shuffle-all" ? `Shuffling all songs: ${song}` : `Playing ${song}`;
}
