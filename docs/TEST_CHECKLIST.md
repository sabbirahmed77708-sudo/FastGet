# DROX Browser – manual test checklist

This code was written without being able to compile or run it. Please go through
this list on a real phone and report anything that fails.

## Tabs and live panel
- [ ] Open the browser: homepage shows DROX wordmark, search box, shortcuts.
- [ ] Search "flutter" -> Google results open; the toolbar shows `google.com`.
- [ ] Tap a result: toolbar URL, tab title and favicon in the Tabs panel update.
- [ ] While a page loads, the Tabs panel shows "Loading… N%" and a progress line.
- [ ] Press Back: page goes back, title/URL in the panel update.
- [ ] Tab counter shows the right number; tap it -> left panel opens.
- [ ] Opening/closing the panel does NOT reload the page.
- [ ] "+" opens a new tab (homepage). Switch between tabs: both keep their page.
- [ ] Close a tab with X; close the last tab -> a fresh homepage tab appears.
- [ ] Panel bottom: Back / Home / Forward / + work.
- [ ] Home button shows homepage; Back returns to the page that was open.
- [ ] Open a link with target=_blank: it opens in a new tab.
- [ ] Close the app and reopen the browser: tabs and active tab come back.

## Menu
- [ ] Quick row: Back, Forward, Bookmark (star toggles), Refresh, Settings.
- [ ] New Tab, Downloads, History, Find in Page, Clear Browsing Data work.
- [ ] Block Ads / Capture Audio-Video / Desktop Mode show a check when ON and
      are still ON after restarting the app.
- [ ] Desktop Mode reloads the page as a desktop site.
- [ ] Tapping outside the menu closes it.
- [ ] View Page Resources lists requests for the current page.
- [ ] Return to DROX goes back to the download list.

## Downloads from the browser
- [ ] Tap a direct file link (e.g. a .zip / .pdf): DROX popup appears with the
      right name, type and size.
- [ ] Confirm -> item appears in Downloads, progress/speed move, pause/resume work.
- [ ] A link that returns an HTML page is refused with a clear message.
- [ ] A finished file opens and its size matches the server size.
- [ ] Airplane mode mid-download -> item shows Failed/Paused, Resume continues.

## Errors
- [ ] Open a non-existing domain: "Can't open this page" with Try again.
- [ ] http:// site shows an open-lock icon, https:// shows a closed lock.
