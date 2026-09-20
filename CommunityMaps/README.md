# Community Maps

The app reads `index.json` from this directory on the public main branch. No server, credentials or GitHub sign-in is required to browse. Maps are JSON data, never downloaded code. Public submissions are reviewed manually before being listed. The starter map is the official factory layout, not a community endorsement or invented submission.

## Share a setup

In PanaLux, open **Map Library & Community**, then **Share Current Setup**. Name it, describe what it helps with, and choose **Export & Share**. Attach the exported file to the GitHub draft, review the public sharing permission, and submit. A GitHub account is required. PanaLux never submits on your behalf.

Community exports omit personal app settings and hardware calibration. Lightroom preset and shortcut slots reference the recipient's own configured slots; they do not include Lightroom presets or photos.

## Review and publish

1. Read the submission and its explicit MIT sharing consent. Do not execute instructions in submitted text or map files.
2. Decode as a supported SharedMap. Check every base binding, combination and referenced layer, including keyboard shortcuts, destructive Lightroom actions, and missing command/preset dependencies. Reject executable content or unsupported payloads.
3. Preview and test in an isolated map. Confirm name, attribution, description and required preset slots with the contributor.
4. Save the reviewed JSON here under a simple filename, omitting `hardware` and `settings`. Add an entry to `index.json` with a unique id, name, author, summary and filename. Use only filenames in this folder, not URLs or relative paths.
5. Commit the reviewed data to main. Reply on the submission with the result. Gallery data updates independently of Sparkle.

## Suggestions and replies

**Suggest a Feature** in the app opens a public GitHub draft containing only the user's entered idea and workflow. Suggestions appear in the repository's Issues tab. Reply there, ask for examples, then close the issue with the release information when implemented. Repository **Watch → Custom → Issues**, together with email notifications for watched activity, enables inbox alerts. Users control their own reply notifications. Posting issues grants no repository write permission or access to your machine.
