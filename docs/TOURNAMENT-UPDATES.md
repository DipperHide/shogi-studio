# Tournament updates / 棋谱更新 / 棋譜更新

## Operation

1. `scripts/update_tournaments.py` reads the public official event pages for Ōi, Ōza, Kiō, Kisei, Eiō and Ryūō. It follows only matching links on `live.shogi.or.jp`, checks the current and previous years, and retains completed records. An empty event page is not treated as proof that the event has no games.
2. The checked-in `godot/assets/data/tournament-index.json` contains metadata and hashes, **not the recent move sequence or commentary**. It is a starting catalog for new installations.
3. `.github/workflows/update-tournaments.yml` refreshes that file daily around 21:23 UTC / 05:23 China / 06:23 Japan. It can also be run with **Run workflow**. Successful refreshes update the timestamp, even when no new game has finished.
4. Opening recent events triggers an HTTPS refresh at most once per day after a successful check. “刷新” requests another check immediately. The endpoint is configured in `godot/config/tournaments.json`.
5. Selecting a game downloads its official KIF. The app decodes UTF-8 or CP932, removes commentary and timing annotations, verifies the catalog's move hash, parses every move and checks the terminal result. Only a successful record is saved to `user://tournaments/`.

Failed downloads, malformed catalogs, changed move hashes, illegal games, older
indexes and failed cache writes preserve the existing data. Catalog and game
cache writes use a temporary file followed by a rename. Users can keep playing
their own games while visiting the archive; downloaded games open for review.

The official KIF host currently serves these files over HTTP. Its URL is
allowlisted, redirects are disabled in the app, and downloaded move sequences
must match the index delivered over HTTPS. The Android network exception is
limited to this host. These checks detect inconsistent data; they do not
authenticate the organizer's HTTP publication.

## Maintenance

```powershell
python scripts/test_tournaments.py
python scripts/update_tournaments.py
./scripts/test_chessis20.ps1 -CoreOnly -Network
```

When moving or forking the repository, update `index_url` before exporting a new
APK, and enable the workflow on the default branch. The workflow needs repository
contents write permission. A private repository's raw URL cannot serve anonymous
app users; use a publicly readable catalog endpoint for distributed builds.

GitHub schedules can be delayed and public repositories can have scheduled jobs
disabled after 60 days of inactivity. Check the Actions page after repository
settings or permissions change. [GitHub schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

The app does not promise every professional game, live coverage or access to
paid KIF. It uses only publicly readable official links and preserves the
source button for each entry. The latest verified entry for 0.20 is the
[September 8–9, 2026 Ōi game](http://live.shogi.or.jp/oui/kifu/67/oui202609080101.html).
See the [official tournament list](https://www.shogi.or.jp/match/) and
[organizer usage guidance](https://store.shogi.or.jp/view/page/kifuriyou).

Only factual directory information is distributed for recent games. Do not
publish downloaded commentary, images or recent full KIF through this workflow.
