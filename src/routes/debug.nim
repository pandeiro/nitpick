# SPDX-License-Identifier: AGPL-3.0-only
import jester
import router_utils
import ".."/[auth, types, redis_cache]

proc createDebugRouter*(cfg: Config) =
  router debug:
    get "/.health":
      respJson getSessionPoolHealth()

    get "/.sessions":
      cond cfg.enableDebug
      respJson getSessionPoolDebug()

    get "/.feed":
      cond cfg.enableDebug
      respJson await getGlobalFeedDebug()

    get "/.feed/clear":
      cond cfg.enableDebug
      await clearGlobalFeed()
      resp "Feed cleared"
