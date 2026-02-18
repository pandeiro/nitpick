# SPDX-License-Identifier: AGPL-3.0-only
import tables, macros, strutils
import karax/[karaxdsl, vdom]

import renderutils
import ../types, ../prefs_impl

macro renderPrefs*(prefs: untyped): untyped =
  let stmtList = nnkStmtList.newTree()
  result = nnkCall.newTree(ident("buildHtml"), ident("tdiv"), stmtList)

  for header, options in prefList:
    stmtList.add nnkCall.newTree(
      ident("legend"),
      nnkStmtList.newTree(
        nnkCommand.newTree(ident("text"), newLit(header))))

    for pref in options:
      let
        procName = ident("gen" & capitalizeAscii($pref.kind))
        fieldName = ident(pref.name)
      
      var call = nnkCall.newTree(procName, newLit(pref.name), newLit(pref.label), 
                                 nnkDotExpr.newTree(prefs, fieldName))

      case pref.kind
      of checkbox: discard
      of input: call.add newLit(pref.placeholder)
      of select:
        if pref.name == "theme":
          call.add ident("themes")
        else:
          call.add newLit(pref.options)

      stmtList.add call

proc renderPreferences*(prefs: Prefs; path: string; themes: seq[string];
                        prefsUrl: string): VNode =
  buildHtml(tdiv(class="overlay-panel")):
    fieldset(class="preferences"):
      form(`method`="post", action="/saveprefs", autocomplete="off"):
        refererField path

        renderPrefs(prefs)

        legend: text "Bookmark"
        p(class="bookmark-note"):
          text "Save this URL to restore your preferences (?prefs works on all pages)"
        pre(class="prefs-code"):
          text prefsUrl
        p(class="bookmark-note"):
          verbatim "You can override preferences with query parameters (e.g. <code>?hlsPlayback=on</code>). These overrides aren't saved to cookies, and links won't retain the parameters. Intended for configuring RSS feeds and other cookieless environments. Hover over a preference to see its name."

        h4(class="note"):
          text "Preferences are stored client-side using cookies without any personal information."

        button(`type`="submit", class="pref-submit"):
          text "Save preferences"

      buttonReferer "/resetprefs", "Reset preferences", path, class="pref-reset"
