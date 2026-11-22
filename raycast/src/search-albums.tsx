import { Action, ActionPanel, Grid, Icon, Keyboard, showHUD, showToast, Toast } from "@raycast/api";
import { useCachedPromise } from "@raycast/utils";
import { Album, AlbumAction, CatalogError, describe, loadAlbums, openLink, songsOf } from "./catalog";
import { SongList } from "./songs";

export default function SearchAlbums() {
  // Cached, so the grid appears at once with last time's albums while the
  // file is read again.
  const { data: albums, isLoading, error, revalidate } = useCachedPromise(loadAlbums, [], {
    keepPreviousData: true,
    failureToastOptions: { title: "Could not read Mewsic's albums" },
  });

  if (error instanceof CatalogError && !albums?.length) {
    return (
      <Grid>
        <Grid.EmptyView
          icon={Icon.Music}
          title={error.kind === "missing" ? "No albums from Mewsic yet" : "Update the Mewsic extension"}
          description={
            error.kind === "missing"
              ? "Open Mewsic once. After it scans your music, it shares the album list here."
              : error.message
          }
          actions={
            <ActionPanel>
              <Action
                title="Open Mewsic"
                icon={Icon.AppWindow}
                onAction={() => openLink("mewsic://search?q=", { background: false })}
              />
              <Action title="Try Again" icon={Icon.ArrowClockwise} onAction={revalidate} />
            </ActionPanel>
          }
        />
      </Grid>
    );
  }

  return (
    <Grid columns={5} aspectRatio="1" fit={Grid.Fit.Fill} isLoading={isLoading} searchBarPlaceholder="Album or artist">
      {albums?.map((album) => (
        <Grid.Item
          key={album.id}
          content={album.cover ? { source: album.cover } : { source: Icon.Music }}
          title={album.name}
          subtitle={album.artist}
          keywords={[album.artist, ...(album.year ? [album.year] : [])]}
          actions={<AlbumActions album={album} />}
        />
      ))}
    </Grid>
  );
}

function AlbumActions({ album }: { album: Album }) {
  return (
    <ActionPanel title={`${album.name} — ${album.artist}`}>
      <ActionPanel.Section>
        <Act album={album} action="play" title="Play" icon={Icon.Play} hud={`Playing ${album.name}`} />
        <Act
          album={album}
          action="shuffle"
          title="Shuffle"
          icon={Icon.Shuffle}
          hud={`Shuffling ${album.name}`}
          shortcut={{ modifiers: ["cmd"], key: "s" }}
        />
        <Act
          album={album}
          action="next"
          title="Play Next"
          icon={Icon.Text}
          hud={`Playing next: ${album.name}`}
          shortcut={{ modifiers: ["cmd"], key: "n" }}
        />
        <Act
          album={album}
          action="open"
          title="Open in Mewsic"
          icon={Icon.AppWindow}
          shortcut={Keyboard.Shortcut.Common.Open}
        />
      </ActionPanel.Section>
      <ActionPanel.Section title={describe(album)}>
        <Action.Push
          title="Show Songs"
          icon={Icon.List}
          shortcut={{ modifiers: ["cmd"], key: "return" }}
          target={<SongList songs={songsOf([album])} navigationTitle={album.name} showAlbum={false} />}
        />
        <Action.CopyToClipboard
          title="Copy Album Link"
          content={album.links.open}
          shortcut={Keyboard.Shortcut.Common.Copy}
        />
      </ActionPanel.Section>
    </ActionPanel>
  );
}

function Act(props: {
  album: Album;
  action: AlbumAction;
  title: string;
  icon: Icon;
  /** Shown as Raycast closes; "Opening <album>" when not given. */
  hud?: string;
  shortcut?: Keyboard.Shortcut;
}) {
  const { album, action, title, icon, hud, shortcut } = props;
  return (
    <Action
      title={title}
      icon={icon}
      shortcut={shortcut}
      onAction={async () => {
        try {
          await openLink(album.links[action], { background: action !== "open" });
          await showHUD(hud ?? `Opening ${album.name}`);
        } catch (e) {
          await showToast({ style: Toast.Style.Failure, title: "Could not reach Mewsic", message: String(e) });
        }
      }}
    />
  );
}
