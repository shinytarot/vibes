# vibes

A page that scatters your images at random across the screen. No grid, no captions, no dates — just a wall of things you liked.

Live examples: [Sophia](https://girl.surgery/website_vibes/), who wrote the original, plus [Xavi](https://xavicf.com/vibes), [Guzey](https://guzey.com/vibes/), [Catherine](https://catherinebrewer.github.io/vibes/), and [mine](https://alexanderlarge.com/vibes).

This is the GitHub Pages version, built so you never have to open a terminal. **The `images/` folder is the page.** Put a file in and it appears. Delete one and it comes down. There's no draft state and nothing to approve.

You need a free GitHub account. That's the only prerequisite.

## Setup

1. Click **Use this template → Create a new repository** at the top of this page.
2. Name it `vibes`, and leave visibility on **Public** — GitHub Pages on a private repo is a paid feature, and this page is public regardless.
3. In your new repo: **Settings → Pages → Source → GitHub Actions**. (Not "Deploy from a branch" — this template deploys from the Action.)
4. Open `images/` and delete the three sample gradients — click one → the **···** menu at the top right → **Delete file** (it's the last item) → **Commit changes**, then the same for the other two.
5. Still in `images/`: **Add file → Upload files**, drag your own photos on, **Commit changes**. Wait for the green tick (below) before uploading a second batch.

Your page is at `https://<your-username>.github.io/vibes/`, live under a minute after each change. Nothing else to switch on.

If you'd rather it served at `https://<your-username>.github.io` with no `/vibes` on the end, name the repo `<your-username>.github.io` at step 2 instead. Both work — the paths are relative.

**If GitHub emails you that a workflow failed, before you've done anything.** Creating a repo from a template can kick off the first run immediately, before step 3 has switched Pages on, and that run fails. It's expected and it's harmless — the next commit you make succeeds. Ignore the email.

## Runs, and why you wait for the tick

Every commit starts a **run** — the Action that converts your images and republishes the page. You watch it in the **Actions** tab: an amber dot means it's working, a green tick means the page is updated, a red ✗ means something went wrong. They take 20–30 seconds.

Commit one thing at a time and let the tick appear before the next one. Starting a second run cancels the first, and a cancelled upload can leave your original photo sitting in the repo's history un-stripped — which is the one thing this whole setup exists to prevent. Deletions are harmless to interrupt; uploads are not.

## Adding images

Open the **`images/` folder first**, then **Add file → Upload files** → drag them on → **Commit changes**.

Opening `images/` first is the part people miss. Dragging files onto the repo's front page uploads them to the top level instead, where nothing looks for them — the commit succeeds, no run starts, and your page doesn't change, with no error anywhere to tell you why.

To remove one: click it → the **···** menu at the top right → **Delete file** → **Commit changes**.

Limits GitHub puts on browser uploads: **25 MB per file** and **100 files at a time**. Phone photos are 3–5 MB, so the file limit is unlikely to bite; the count one will if you drag a whole export folder.

iPhone `.HEIC` files are fine — they get converted like everything else.

To take the page down entirely: open `images/` → the **···** menu → **Delete directory** → commit.

## Alternative: a desktop folder that syncs itself

**macOS only** — it uses a Desktop alias and a launchd job, neither of which exists on Windows or Linux. Everything above works anywhere.

If you'd rather never open github.com at all: get a local copy of your repo onto your Mac (`git clone`, or ask Claude Code to do it), then ask Claude Code to run `scripts/install-local-sync.sh` from inside it. It sets up a `vibes-inbox` alias on your Desktop, wired to a nightly job — drag a photo in and it goes live overnight, drag one out and it comes down, with no commit/upload step in between. `scripts/local-sync.sh` is what runs each night; run it yourself anytime you don't want to wait. `scripts/uninstall-local-sync.sh` turns it back off without touching your photos. If something in the folder can't be published — a video that came off your camera roll with the photos, a damaged file — a plain-text note appears in the folder naming it, and disappears again once you've dealt with it. Nothing to check; it comes to you. Subfolders work, so you can drag a whole album in and keep it filed. The page is flat and only the filename is published, never the folder name — your own filing shouldn't end up in a public URL.

Setting this up needs a terminal and git push access to your repo, which is why it's the Claude-Code path rather than the browser one above. Either flow works and you can switch between them — the installer moves anything already in `images/` into the inbox first, so nothing drops off the page.

Edits you make to `index.html` on your own machine — your words at the top — are kept and pushed by the nightly run. Edit it on github.com instead and the next run picks that up. Edit it in both places on the same day and your local copy wins; the run says so, and the other version is still in the repo's history.

Emptying the folder does *not* empty the page: a run that would leave nothing published — an inbox that's empty, or holding only files it can't use — refuses and leaves the page as it was, because a folder that suddenly went empty is far more likely to have been moved than to mean "take it all down". To actually clear the page: empty the inbox folder first, then open `images/` on github.com and use the **···** menu → **Delete directory**. Deleting it while the inbox still has photos in it just means the next run puts them all back.

## What it does to your images, and why

Every upload gets re-encoded to WebP: resized so the longest edge is 1400px, quality 82. The compressed version replaces the original in the repo. Two reasons, and the first is the one that matters:

**It strips the metadata.** An iPhone photo carries the GPS coordinates of the spot it was taken. This page is public, and so is the repo behind it — so an untouched holiday photo is a public file with your location history in it. The re-encode drops EXIF as a side effect. This is why the Action commits the converted file *over* the original rather than converting on the way out: an original left sitting in the repo is still a public original.

It goes one step further than that, because it has to. Replacing the file isn't enough on its own — the commit you made when you uploaded is still in the repo's history, so a plain `git clone` would hand anyone the untouched original, GPS and all. I tested this rather than assumed it, and that is exactly what happened. So the Action rewinds to the commit you pushed from and rebuilds your upload as a single commit that only ever contained the converted files. The original ends up referenced by nothing and a clone can't reach it.

Honest limit, and it's a real one. Rewinding past a commit doesn't delete it — the object sits on GitHub's servers until their garbage collection gets to it, and anyone holding the hash can still fetch it over plain HTTPS. An earlier version of this paragraph said nobody gets that hash by accident. That was wrong: GitHub publishes it. The Actions API serves it unauthenticated, the build log prints it in the force-push line, and the public events feed archives it. Someone who cares can find it in one request.

So what the rewrite actually buys you is that the original isn't in every clone by default — not that it's gone. Treat this as protection against the casual case only. If a photo's location is genuinely sensitive, strip it before it leaves your machine; don't make a GitHub Action the only thing standing between it and the internet.

**It makes the page loadable.** The images on my own page are 61MB as they came off the phone, and 4.3MB published — a 14× cut, for a page that looks identical, because it draws them 250–500px wide. GitHub Pages does no image optimisation of its own and has a 100GB/month bandwidth limit, so uncompressed genuinely costs you here.

You lose nothing worth keeping. Your originals are still wherever they were; this repo is a display case, not storage.

Two consequences worth knowing:

- **If a file can't be read, it's deleted rather than left alone,** and the run goes red to tell you which. Your other images still went live — the report comes after the deploy — so a red ✗ here means "one file didn't make it", not "nothing worked". It looks aggressive because an undecodable file is one whose metadata can't be stripped either, and leaving it means a public file with your coordinates in it. You still have the original; re-save it as a JPEG and upload it again. The same applies to anything that isn't an image, like a video that came along for the ride off your camera roll.
- **Animated GIFs become a single still frame.** Nobody's fixed this yet.

## Making it yours

To change any file on github.com: open it, click the **pencil** icon at the top right, edit, then **Commit changes**. Same as uploading — it starts a run and the page updates.

Most of it lives in `index.html`:

- **The text.** Near the top there's a title, a credits line, and an HTML comment marking where your own words go. Replace any of it — the layout routes images around whatever text is there, so nothing you add gets covered up.
- **Image size.** Change `goal_pixels` (default `500*300`). Bigger number, bigger images.
- **Search engines.** It ships with `<meta name="robots" content="noindex, nofollow">`, so it won't turn up in search results. Delete that line if you'd rather it did.
- **Compression.** `MAX_EDGE` and `QUALITY` in `scripts/vibes.py`.

## When it breaks

**Page loads but is empty, or alerts about a missing JSON.** The Action hasn't run or it failed. Check the **Actions** tab.

**I uploaded and nothing changed.** The files went to the top level instead of into `images/`. The Action moves them in for you on the next run — but if nothing happened at all, open the `images/` folder *first*, then **Add file → Upload files**.

**The run went red but my photos are up.** That's the intended order. The page deploys before the run reports which files it couldn't use, so the good ones are already live. Open the run in the **Actions** tab and read the "Report rejected files" step for the names.

**Nothing deploys.** Settings → Pages → Source must be **GitHub Actions**.

**My page 404s.** Give the first deploy a couple of minutes, then check the address: `https://<your-username>.github.io/<repo-name>/` — the repo name is part of it unless you named the repo `<your-username>.github.io`.

**A photo is sideways.** Shouldn't happen — the script honours the EXIF orientation flag. If one slips through, open an issue on [the template](https://github.com/alex-is-learning/vibes-template/issues); an issue on your own copy has nobody reading it.

## Credit

The placement algorithm and the original two-file version are [sophiawisdom's gist](https://gist.github.com/sophiawisdom/c1b16fcaca017d1aec2358c6fb619697) — go there if you'd rather run it locally against a folder of screenshots. This template adds the GitHub Pages plumbing, the compression, and the metadata stripping, so the whole thing runs off drag-and-drop.

The placement is deliberately crude: throw each image at a random spot, retry if it overlaps, make the page taller if it can't fit. Everyone's version of this page is a bit rough and it's better for it. Please don't add a lightbox.
