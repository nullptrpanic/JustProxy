# Website Deployment

The public website is a static HTML/CSS site in `website/`. GitHub Actions uploads the contents of that directory to GitHub Pages. Project documentation in `docs/` is not uploaded.

## Public URLs

| Source | Public URL |
| --- | --- |
| `website/index.html` | https://nullptrpanic.github.io/JustProxy/ |
| `website/privacy/index.html` | https://nullptrpanic.github.io/JustProxy/privacy/ |
| `website/style.css` | https://nullptrpanic.github.io/JustProxy/style.css |

`website` is the source directory, not a new URL segment. App Store Connect and `PrivacyView.swift` continue to use the existing URLs. This directory migration does not require an app version change or a new app build.

## First migration from branch-based publishing

The previous setup published `master`'s `/docs` directory. Switch Pages to GitHub Actions when adopting this change:

1. Commit and push the migration on `dev`. The deployment workflow does not publish from `dev`.
2. Open the repository's [Settings > Pages](https://github.com/nullptrpanic/JustProxy/settings/pages).
3. Under **Build and deployment**, change **Source** from **Deploy from a branch** to **GitHub Actions**. The workflow is already provided; no generated template or custom domain is needed.
4. Merge the migration into `master`. The workflow and `website/` must both be present on `master` before the first deployment can run.
5. Open the repository's **Actions** tab and select **Deploy website**. The push to `master` triggers deployment. If the changes were merged before the Pages setting was updated, use **Run workflow**, select **master**, and run it again.
6. Wait for the `deploy` job to succeed, then open both public URLs and verify the stylesheet and navigation links.

The workflow name and manual Run workflow control appear after the workflow exists on the default branch. If the `github-pages` environment has branch restrictions, its allowed deployment branches must include `master`.

Keep HTTPS enabled. The App Store support/privacy URLs do not need to be changed.

## Routine updates

Edit public HTML/CSS files in `website/` on `dev`, review the changes, and merge them into `master` when ready to publish.

[`.github/workflows/pages.yml`](../.github/workflows/pages.yml) runs for changes to `website/**` or the workflow itself on `master`. It also supports manual runs on `master`. Changes limited to README or project documentation do not deploy the website.

The workflow uses GitHub's official checkout and Pages actions, pinned to commit hashes. It grants the deployment job `contents: read`, `pages: write`, and `id-token: write`, and uses the `github-pages` environment. No personal access token, App Store Connect key, or additional repository secret is required. There is no site-generator dependency or build step.

## Local preview

From the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory website
```

Open these local addresses:

- http://127.0.0.1:8765/
- http://127.0.0.1:8765/privacy/

The site uses relative navigation and stylesheet links so the same files work at the local root and at the public `/JustProxy/` project path. Stop the preview server with `Ctrl+C` when finished.

## Deployment checks

After a successful workflow run:

```sh
curl --fail --silent --show-error --output /dev/null \
  https://nullptrpanic.github.io/JustProxy/
curl --fail --silent --show-error --output /dev/null \
  https://nullptrpanic.github.io/JustProxy/privacy/
curl --fail --silent --show-error --output /dev/null \
  https://nullptrpanic.github.io/JustProxy/style.css
```

Also open both pages in a browser and check the policy/support navigation and email link. Keep sensitive credentials, review-only contact information, build output, and project notes out of `website/`; every file in the uploaded website artifact is public.

If deployment fails, inspect the failed step in **Actions > Deploy website**. Confirm that Pages uses **GitHub Actions**, the workflow ran from `master`, and the checkout contains `website/index.html`.

Reference: [Using custom workflows with GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
