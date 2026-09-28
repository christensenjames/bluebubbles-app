# Upstream PR candidates

A running list of the fork's fixes that are worth offering to `BlueBubblesApp/bluebubbles-app`. None
has been sent yet. The fork merges everything; upstream gets only what a maintainer would want to
review: user-visible defects with a short, self-contained diff.

Upstream context (2026-09-28): the last upstream merge was 2026-09-06, and our own PR #3273 (manual
mark-read button) has had no review since 2026-09-13. Send a few at a time, starting at the top.

"Applies" was measured with `git merge-tree` of the fix commit against `upstream/master`
(`e2eaced6e`) on 2026-09-28. "Clean" means the patch applies textually. It does not mean the patch
is independent of other fork changes, so rebuild on `upstream/master` before opening any PR.

## Send first

| unit | defect | applies | before sending |
|---|---|---|---|
| U27 | An interrupted first sync hides every message it had not fetched yet, permanently. | clean | Use the corrected version from `autonomous/integration` (`89cf00a2c`), not the raw `u27` branch. |
| U117 | A split notification reply (a URL at either end, on a Catalina-or-older server) stops every later message from sending until restart. | clean | Android device test. U135 is its follow-up and is stacked on it. |
| U133 | The composer throws on text it did not type, causing double sends, a failed forward and wiped drafts. | clean | - |
| U143 | Messages from a contact's secondary address are saved but never shown. | clean | - |
| U127 | Moving the API timeout slider drops the custom, ngrok and zrok headers until restart. | clean | U136 (the same gap for isolate requests) is stacked on it. |
| U125 | Google OAuth tokens are written to the log users export and share. | clean | - |
| U126 | The socket keeps dialling a server address that is no longer valid. | clean | Android device test (wifi to cellular). |
| U151 | First-time setup hangs on "Syncing..." forever when the server fails. | clean | - |

## Worth sending

| unit | defect | applies | before sending |
|---|---|---|---|
| U118 | Tapping a notification marks the chat being left as read and sends its read receipt. | clean | Android device test. |
| U147 | A startup failure on desktop leaves the splash screen up forever, with no error. | conflicts in `lib/main.dart` | Rebase onto `upstream/master`. |
| U26 | Attributed-body parts are added after the function has already returned. | clean | Use the corrected version from `autonomous/integration`. |
| U24 | "Mark all as read" leaves wrong badges and stops at the first server error. | clean | Use the corrected version from `autonomous/integration`. Overlaps our open #3273 area. |
| U25 | Mentions are sliced against the wrong string in redacted mode. | clean | Use the corrected version from `autonomous/integration`. |
| U154 | Send in the new chat creator can go to the previous chat, and the group limit lets a second recipient through. | clean | - |
| U148 | Swipe-to-reply and bubble effects use the wrong part of a multi-part message. | clean | - |
| U128 | Attachment re-downloads and temp attachments break the download queue. | clean | - |

## Not upstream as they stand

- Lint and deprecation cleanups (the 2026-09-18 `ubcs`/deprecation/dead-code branches, U110, U155):
  broad churn with little user impact. U110 carries two real bugs (a forward with attachments throws;
  scheduling a message can close the conversation). Send those two as their own small PR if upstream
  wants them.
- U102 (passphrase bytes): check that the server derives its key the same way before offering it.
- Anything that depends on a fork-only change (`feat/send-emoji-tapbacks`, or the 2026-09-18 base).
