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
  playing: boolean;
  shuffle: boolean;
  repeat: string;
  track: { title: string; artist: string; album: string } | null;
}

const STATUS_PATH = join(SHARED_FOLDER, "player.json");

async function readStatus(): Promise<string | null> {
  try {
    return await readFile(STATUS_PATH, "utf8");
  } catch {
    return null;
  }
}

/**
 * Sends [control] to Mewsic, leaving it in the background, then says what
 * happened: Mewsic rewrites player.json once the command has taken effect,
 * so we wait for that (a few seconds at most, as a cold start or a library
 * scan for "shuffle all" takes a moment) and describe the new state.
 */
export async function runControl(control: Control) {
  const before = await readStatus();
  await openLink(`mewsic://control?do=${control}`, { background: true });

  let text = before;
  for (let waited = 0; waited < 5000; waited += 100) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    text = await readStatus();
    if (text !== null && text !== before) break;
  }
  const status = text ? (JSON.parse(text) as PlayerStatus) : null;
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
