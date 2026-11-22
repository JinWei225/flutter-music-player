import { Action, ActionPanel, Icon, Keyboard, List, showHUD, showToast, Toast } from "@raycast/api";
import { Album, formatDuration, openLink, Track } from "./catalog";

/**
 * Songs as a searchable list, matched on title, artist and album. Used for
 * the whole library (Search Songs) and for one album (an album's Show Songs).
 */
export function SongList(props: {
  songs: { track: Track; album: Album }[];
  isLoading?: boolean;
  navigationTitle?: string;
  /** Hide the album beside each song when every song is from the same one. */
  showAlbum?: boolean;
}) {
  const { songs, isLoading, navigationTitle, showAlbum = true } = props;
  return (
    <List isLoading={isLoading} navigationTitle={navigationTitle} searchBarPlaceholder="Song, artist or album">
      {songs.map(({ track, album }) => (
        <List.Item
          key={track.links.play}
          icon={album.cover ? { source: album.cover } : Icon.Music}
          title={track.title}
          subtitle={track.artist}
          keywords={[album.name, album.artist]}
          accessories={[
            ...(showAlbum ? [{ text: album.name }] : []),
            ...(track.seconds ? [{ text: formatDuration(track.seconds) }] : []),
          ]}
          actions={<SongActions track={track} album={album} />}
        />
      ))}
    </List>
  );
}

function SongActions({ track, album }: { track: Track; album: Album }) {
  async function send(link: string, background: boolean, hud: string) {
    try {
      await openLink(link, { background });
      await showHUD(hud);
    } catch (e) {
      await showToast({ style: Toast.Style.Failure, title: "Could not reach Mewsic", message: String(e) });
    }
  }
  return (
    <ActionPanel title={`${track.title} — ${track.artist}`}>
      <Action
        title="Play"
        icon={Icon.Play}
        onAction={() => send(track.links.play, true, `Playing ${track.title}`)}
      />
      <Action
        title="Play Next"
        icon={Icon.Text}
        shortcut={{ modifiers: ["cmd"], key: "n" }}
        onAction={() => send(track.links.next, true, `Playing next: ${track.title}`)}
      />
      <Action
        title="Open Album in Mewsic"
        icon={Icon.AppWindow}
        shortcut={Keyboard.Shortcut.Common.Open}
        onAction={() => send(album.links.open, false, `Opening ${album.name}`)}
      />
    </ActionPanel>
  );
}
