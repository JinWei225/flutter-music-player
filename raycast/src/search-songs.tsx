import { useCachedPromise } from "@raycast/utils";
import { loadAlbums, songsOf } from "./catalog";
import { SongList } from "./songs";

export default function SearchSongs() {
  const { data: albums, isLoading } = useCachedPromise(loadAlbums, [], {
    keepPreviousData: true,
    failureToastOptions: { title: "Could not read Mewsic's songs", message: "Open Mewsic once so it can share them." },
  });
  return <SongList songs={songsOf(albums ?? [])} isLoading={isLoading} />;
}
