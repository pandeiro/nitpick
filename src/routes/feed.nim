# SPDX-License-Identifier: AGPL-3.0-only
import jester

import router_utils
import ".."/[feed]

proc createFeedRouter*(cfg: Config) =
  router feedRoutes:
    get "/.feed/status":
      let statusJson = await buildFeedStatusJson()
      respJson statusJson

    post "/.feed/refresh":
      triggerFeedRefresh()
      if acceptJson():
        respJson refreshRespJson()
      else:
        redirect("/")
