#!/usr/bin/env python3
"""
Nitpick Feed Study Tool

Investigates the effectiveness of the search-based feed vs individual user timelines.

Collects empirical data on:
- How many tweets the search endpoint returns vs individual timeline fetches
- How many distinct users are represented in search results
- How fresh/stale search results are compared to timelines
- How Twitter's cache behaves over time
- What rate limit headroom exists per endpoint

Usage:
    # 1. Harvest users from a remote Nitpick instance
    python tools/feed_study.py harvest --remote https://twitter.ottertime.com -o data/remote_users.json

    # 2. Import harvested users into local instance
    python tools/feed_study.py import data/remote_users.json

    # 3. Run a measurement cycle
    python tools/feed_study.py measure -o data/measurement.jsonl

    # 4. Run timed cache test
    python tools/feed_study.py cache-test --interval 120 --repetitions 15 -o data/cache_test.jsonl

    # 5. Generate summary from collected data
    python tools/feed_study.py report data/measurement.jsonl
"""

import argparse
import json
import sys
import time
import os
from datetime import datetime, timezone
from urllib.parse import urljoin
from collections import defaultdict

import requests


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def ts_now():
    """Return current UTC timestamp as ISO string."""
    return datetime.now(timezone.utc).isoformat()


def epoch_now():
    """Return current Unix epoch as int."""
    return int(time.time())


def jsonl_append(path, record):
    """Append one JSON object to a JSONL file, creating dirs if needed."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps(record, default=str) + "\n")


def jsonl_read(path):
    """Yield parsed JSON objects from a JSONL file."""
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def api_get(session, base, path, **kwargs):
    """Make a JSON API GET request with Accept header."""
    headers = {"Accept": "application/json"}
    if "headers" in kwargs:
        headers.update(kwargs.pop("headers"))
    url = urljoin(base, path)
    resp = session.get(url, headers=headers, timeout=30, **kwargs)
    return resp


def api_post(session, base, path, data=None):
    """Make a POST request with Accept header."""
    headers = {"Accept": "application/json"}
    url = urljoin(base, path)
    resp = session.post(url, headers=headers, data=data, timeout=30)
    return resp


def extract_rate_limits(resp):
    """Extract rate limit headers from a response."""
    return {
        "remaining": resp.headers.get("x-rate-limit-remaining"),
        "reset": resp.headers.get("x-rate-limit-reset"),
        "limit": resp.headers.get("x-rate-limit-limit"),
    }


# ---------------------------------------------------------------------------
# Subcommand: harvest
# ---------------------------------------------------------------------------

def cmd_harvest(args):
    """
    Harvest user lists from a remote Nitpick instance via its JSON API.
    Collects:
      - Following lists (members per list)
      - Feed authors (from home page and pagination)
    """
    remote = args.remote.rstrip("/")
    session = requests.Session()
    result = {
        "harvested_at": ts_now(),
        "remote": remote,
        "lists": {},
        "feed_authors": set(),
        "all_members": set(),
    }

    print(f"[harvest] Fetching from {remote} ...")

    # --- Following lists ---
    resp = api_get(session, remote, "/following")
    if resp.status_code == 200:
        try:
            data = resp.json()
            for lst in data.get("lists", []):
                name = lst.get("name", "unnamed")
                members = lst.get("members", [])
                result["lists"][name] = members
                for m in members:
                    result["all_members"].add(m.lower())
                print(f"  list '{name}': {len(members)} members")
        except Exception as e:
            print(f"  [warn] Could not parse /following: {e}")
    else:
        print(f"  [warn] /following returned HTTP {resp.status_code}")

    # --- Feed authors (home page + pagination) ---
    cursor = ""
    page = 0
    max_pages = 5  # harvest up to 5 pages of feed
    while page < max_pages:
        params = {}
        if cursor:
            params["cursor"] = cursor
        resp = api_get(session, remote, "/", params=params)
        if resp.status_code != 200:
            print(f"  [warn] feed page {page} returned HTTP {resp.status_code}")
            break
        try:
            data = resp.json()
        except Exception:
            break
        for t in data.get("tweets", []):
            author = t.get("author", {})
            username = author.get("username", "")
            if username:
                result["feed_authors"].add(username.lower())
        cursor = data.get("pagination", {}).get("next_cursor", "")
        meta = data.get("meta", {})
        print(f"  feed page {page}: {len(data.get('tweets', []))} tweets, "
              f"cursor={'yes' if cursor else 'no'}, "
              f"sampled={meta.get('sampled_count')}, "
              f"following={meta.get('following_count')}")
        page += 1
        if not cursor:
            break
        time.sleep(1)  # be gentle

    # Convert sets to sorted lists for JSON serialization
    result["feed_authors"] = sorted(result["feed_authors"])
    result["all_members"] = sorted(result["all_members"])

    # Write output
    with open(args.output, "w") as f:
        json.dump(result, f, indent=2, default=str)
    print(f"\n[harvest] Wrote {args.output}")
    print(f"  Lists: {len(result['lists'])}")
    print(f"  List members (unique): {len(result['all_members'])}")
    print(f"  Feed authors (unique): {len(result['feed_authors'])}")
    print(f"  Union (all unique users): {len(set(result['all_members']) | set(result['feed_authors']))}")


# ---------------------------------------------------------------------------
# Subcommand: import_
# ---------------------------------------------------------------------------

def cmd_import(args):
    """
    Import harvested users into the local Nitpick instance.
    Adds each user to the specified list (default: "default").
    """
    base = args.base.rstrip("/")
    list_name = args.list
    session = requests.Session()

    with open(args.input) as f:
        data = json.load(f)

    # Decide which users to import
    if args.source == "lists":
        users = data.get("all_members", [])
        print(f"[import] Importing {len(users)} list members to '{list_name}'")
    elif args.source == "feed":
        users = data.get("feed_authors", [])
        print(f"[import] Importing {len(users)} feed authors to '{list_name}'")
    elif args.source == "all":
        users = sorted(set(data.get("all_members", [])) | set(data.get("feed_authors", [])))
        print(f"[import] Importing {len(users)} combined users to '{list_name}'")
    else:
        print(f"[error] Unknown source: {args.source}")
        sys.exit(1)

    # Check current following list
    resp = api_get(session, base, "/following")
    existing = set()
    if resp.status_code == 200:
        try:
            d = resp.json()
            for lst in d.get("lists", []):
                if lst.get("name") == list_name:
                    existing = set(m.lower() for m in lst.get("members", []))
        except Exception:
            pass
    print(f"  Currently {len(existing)} users in '{list_name}' list")

    imported = 0
    skipped = 0
    errors = 0
    for user in users:
        if user.lower() in existing:
            skipped += 1
            continue
        resp = api_post(session, base, "/follow", data={"username": user, "list": list_name})
        if resp.status_code in (200, 302):
            imported += 1
            existing.add(user.lower())
        else:
            errors += 1
            if errors <= 5:
                print(f"  [warn] Failed to follow '{user}': HTTP {resp.status_code}")
        # Be gentle
        if imported % 20 == 0 and imported > 0:
            time.sleep(0.5)

    print(f"  Imported: {imported}, skipped: {skipped}, errors: {errors}")
    print(f"  Total now in '{list_name}': {len(existing)}")


# ---------------------------------------------------------------------------
# Subcommand: measure
# ---------------------------------------------------------------------------

def cmd_measure(args):
    """
    Run one measurement cycle:
    1. Fetch the search-based feed (home page)
    2. Fetch the following list
    3. Fetch feed debug info
    4. Fetch session health
    5. For each followed user, fetch their individual timeline
    6. Record everything to JSONL
    """
    base = args.base.rstrip("/")
    session = requests.Session()
    run_id = f"measure_{epoch_now()}"
    outpath = args.output
    list_name = args.list

    print(f"[measure] Run {run_id}")
    print(f"[measure] Target: {base}, list: '{list_name}'")
    print()

    # ---------------------------------------------------------------
    # 1. Search-based feed
    # ---------------------------------------------------------------
    print("[measure] 1. Fetching search-based feed ...")
    params = {}
    if list_name != "default":
        params["list"] = list_name
    resp = api_get(session, base, "/", params=params)
    feed_data = resp.json() if resp.status_code == 200 else {}
    feed_rate_limits = extract_rate_limits(resp)
    feed_tweets = feed_data.get("tweets", [])
    feed_meta = feed_data.get("meta", {})
    feed_pagination = feed_data.get("pagination", {})

    # Summarize feed
    feed_users = set()
    feed_tweet_ids = set()
    feed_tweet_ages = []
    for t in feed_tweets:
        tid = t.get("id", "")
        if tid:
            feed_tweet_ids.add(tid)
        author = t.get("author", {})
        username = author.get("username", "")
        if username:
            feed_users.add(username.lower())
        created = t.get("created_at", "")
        if created:
            try:
                dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
                age = epoch_now() - int(dt.timestamp())
                feed_tweet_ages.append(age)
            except Exception:
                pass

    feed_record = {
        "event": "search_feed",
        "run_id": run_id,
        "timestamp": ts_now(),
        "list": list_name,
        "http_status": resp.status_code,
        "rate_limits": feed_rate_limits,
        "n_tweets": len(feed_tweets),
        "n_users": len(feed_users),
        "users": sorted(feed_users),
        "tweet_ids": sorted(feed_tweet_ids, key=lambda x: int(x) if x.isdigit() else 0, reverse=True),
        "tweet_ages_seconds": sorted(feed_tweet_ages, reverse=True),
        "min_age_seconds": min(feed_tweet_ages) if feed_tweet_ages else None,
        "max_age_seconds": max(feed_tweet_ages) if feed_tweet_ages else None,
        "mean_age_seconds": (sum(feed_tweet_ages) / len(feed_tweet_ages)) if feed_tweet_ages else None,
        "meta": feed_meta,
        "pagination": feed_pagination,
    }
    jsonl_append(outpath, feed_record)
    print(f"    Tweets: {len(feed_tweets)}, Users represented: {len(feed_users)}, "
          f"Age range: {feed_record.get('min_age_seconds', '?')}s - {feed_record.get('max_age_seconds', '?')}s")
    if feed_record.get("mean_age_seconds") is not None:
        print(f"    Mean age: {feed_record['mean_age_seconds']:.0f}s")
    print(f"    Rate limit remaining: {feed_rate_limits.get('remaining', '?')}")

    # ---------------------------------------------------------------
    # 2. Following list
    # ---------------------------------------------------------------
    print("\n[measure] 2. Fetching following list ...")
    resp = api_get(session, base, "/following")
    following_data = resp.json() if resp.status_code == 200 else {}
    followed_users = []
    for lst in following_data.get("lists", []):
        if lst.get("name") == list_name:
            followed_users = [m.lower() for m in lst.get("members", [])]
            break
    # Fallback: if list not found, use all_members
    if not followed_users:
        for lst in following_data.get("lists", []):
            for m in lst.get("members", []):
                if m.lower() not in followed_users:
                    followed_users.append(m.lower())

    print(f"    Followed users in '{list_name}': {len(followed_users)}")

    # ---------------------------------------------------------------
    # 3. Feed debug info (search pool state)
    # ---------------------------------------------------------------
    print("\n[measure] 3. Fetching feed debug info ...")
    resp = api_get(session, base, "/.feed")
    feed_debug = {}
    if resp.status_code == 200:
        try:
            feed_debug = resp.json()
            pool = feed_debug.get("searchPool", [])
            total_sampled = sum(len(e.get("users", [])) for e in pool)
            print(f"    Search pool entries: {len(pool)}, total sampled users: {total_sampled}")
            for i, entry in enumerate(pool):
                print(f"      Entry {i}: {len(entry.get('users', []))} users, cursor={'yes' if entry.get('cursor') else 'no'}")
        except Exception:
            print("    (could not parse)")
    else:
        print(f"    (HTTP {resp.status_code} — debug may be disabled)")

    # ---------------------------------------------------------------
    # 4. Session health
    # ---------------------------------------------------------------
    print("\n[measure] 4. Fetching session pool health ...")
    resp = api_get(session, base, "/.health")
    session_health = {}
    if resp.status_code == 200:
        try:
            session_health = resp.json()
            s = session_health.get("sessions", {})
            r = session_health.get("requests", {})
            print(f"    Sessions: {s.get('total', '?')} total, {s.get('limited', '?')} limited")
            print(f"    Total requests: {r.get('total', '?')}")
            for api_name, count in r.get("apis", {}).items():
                print(f"      {api_name}: {count} reqs")
        except Exception:
            print("    (could not parse)")
    else:
        print(f"    (HTTP {resp.status_code})")

    # Record snapshot
    jsonl_append(outpath, {
        "event": "snapshot",
        "run_id": run_id,
        "timestamp": ts_now(),
        "following_count": len(followed_users),
        "feed_debug": feed_debug,
        "session_health": session_health,
    })

    # ---------------------------------------------------------------
    # 5. Individual user timelines
    # ---------------------------------------------------------------
    print(f"\n[measure] 5. Fetching individual timelines for {len(followed_users)} users ...")
    print(f"    (this will reveal rate limit capacity)")

    timeline_results = []
    rate_limited_count = 0
    error_count = 0
    success_count = 0
    total_timeline_tweets = 0
    all_timeline_users = set()

    for idx, username in enumerate(followed_users):
        # respect rate limiting from local instance
        resp = api_get(session, base, f"/@{username}")
        tl_rate_limits = extract_rate_limits(resp)

        record = {
            "event": "user_timeline",
            "run_id": run_id,
            "timestamp": ts_now(),
            "username": username,
            "index": idx,
            "http_status": resp.status_code,
            "rate_limits": tl_rate_limits,
        }

        if resp.status_code == 200:
            try:
                tl_data = resp.json()
                # Profile response: tweets are nested under data["tweets"]["tweets"]
                tweets_container = tl_data.get("tweets", {})
                if isinstance(tweets_container, dict):
                    tweets = tweets_container.get("tweets", [])
                    tl_pagination = tweets_container.get("pagination", {})
                    tl_meta = tweets_container.get("meta", {})
                else:
                    tweets = tweets_container
                    tl_pagination = {}
                    tl_meta = {}
                user_info = tl_data.get("user", {})
                record["tweet_count"] = len(tweets)
                record["tweet_ids"] = [t.get("id", "") for t in tweets if t.get("id")]
                record["pagination"] = tl_pagination
                record["meta"] = tl_meta
                record["user_info"] = {
                    "id": user_info.get("id", ""),
                    "username": user_info.get("username", ""),
                    "tweets_count": user_info.get("tweets_count", 0),
                    "following_count": user_info.get("following_count", 0),
                }
                # Ages
                ages = []
                for t in tweets:
                    created = t.get("created_at", "")
                    if created:
                        try:
                            dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
                            ages.append(epoch_now() - int(dt.timestamp()))
                        except Exception:
                            pass
                if ages:
                    record["tweet_ages_seconds"] = ages
                    record["min_age_seconds"] = min(ages)
                    record["max_age_seconds"] = max(ages)
                    record["mean_age_seconds"] = sum(ages) / len(ages)

                total_timeline_tweets += len(tweets)
                all_timeline_users.add(username.lower())
                success_count += 1
                if (idx + 1) % 10 == 0:
                    print(f"      [{idx+1}/{len(followed_users)}] {username}: {len(tweets)} tweets, "
                          f"rate limit remaining: {tl_rate_limits.get('remaining', '?')}")

            except Exception as e:
                record["error"] = str(e)
                error_count += 1
                print(f"      [{idx+1}/{len(followed_users)}] {username}: parse error: {e}")
        elif resp.status_code == 429:
            rate_limited_count += 1
            record["error"] = "rate_limited"
            print(f"      [{idx+1}/{len(followed_users)}] {username}: RATE LIMITED (429)")
            # Record remaining users as skipped
            remaining = len(followed_users) - idx - 1
            print(f"      -> Stopping early. {remaining} users skipped due to rate limit.")
            timeline_results.append(record)
            jsonl_append(outpath, record)
            break
        elif resp.status_code == 404:
            record["error"] = "not_found"
            error_count += 1
            if error_count <= 5:
                print(f"      [{idx+1}/{len(followed_users)}] {username}: not found (404)")
        else:
            record["error"] = f"http_{resp.status_code}"
            error_count += 1
            if error_count <= 5:
                print(f"      [{idx+1}/{len(followed_users)}] {username}: HTTP {resp.status_code}")

        timeline_results.append(record)
        jsonl_append(outpath, record)

        # Small delay to avoid hammering
        time.sleep(0.25)

    # ---------------------------------------------------------------
    # Summary
    # ---------------------------------------------------------------
    print(f"\n[measure] === Run Summary ===")
    print(f"  Search feed: {len(feed_tweets)} tweets from {len(feed_users)} users")
    print(f"  Individual timelines: {success_count} succeeded, {rate_limited_count} rate limited, {error_count} errors")
    print(f"  Total timeline tweets: {total_timeline_tweets} from {len(all_timeline_users)} users")

    # Compare overlap
    overlap_users = feed_users & all_timeline_users
    print(f"\n  User overlap (in both search + timeline): {len(overlap_users)}")

    # Per-user comparison (for users that appear in both)
    print(f"\n  Per-user tweet yield comparison:")
    timeline_by_user = {}
    for rec in timeline_results:
        if rec.get("event") == "user_timeline" and rec.get("tweet_count", 0) > 0:
            timeline_by_user[rec["username"].lower()] = {
                "n_tweets": rec["tweet_count"],
                "tweet_ids": set(rec.get("tweet_ids", [])),
                "mean_age": rec.get("mean_age_seconds"),
            }

    for user in sorted(overlap_users)[:20]:  # show first 20
        tl_info = timeline_by_user.get(user, {})
        tl_n = tl_info.get("n_tweets", 0)
        tl_ids = tl_info.get("tweet_ids", set())
        # Count this user's tweets in the search feed
        search_n = sum(1 for t in feed_tweets
                       if t.get("author", {}).get("username", "").lower() == user)
        search_ids = set(t.get("id", "") for t in feed_tweets
                         if t.get("author", {}).get("username", "").lower() == user)
        overlap_ids = search_ids & tl_ids
        coverage = (len(overlap_ids) / len(tl_ids) * 100) if tl_ids else 0
        print(f"    @{user}: search={search_n} tweets, timeline={tl_n} tweets, "
              f"overlap={len(overlap_ids)}/{len(tl_ids)} ({coverage:.0f}%)")

    if len(overlap_users) > 20:
        print(f"    ... and {len(overlap_users) - 20} more users")

    # Overall coverage
    total_tl_tweets = sum(tl_info.get("n_tweets", 0) for tl_info in timeline_by_user.values())
    total_search_tweets = len(feed_tweets)
    if total_tl_tweets > 0:
        overall_coverage = (total_search_tweets / total_tl_tweets) * 100
        print(f"\n  Overall tweet coverage: {total_search_tweets} / {total_tl_tweets} = {overall_coverage:.1f}%")

    # Append final summary to JSONL
    jsonl_append(outpath, {
        "event": "summary",
        "run_id": run_id,
        "timestamp": ts_now(),
        "search_n_tweets": len(feed_tweets),
        "search_n_users": len(feed_users),
        "timeline_success": success_count,
        "timeline_rate_limited": rate_limited_count,
        "timeline_errors": error_count,
        "timeline_n_tweets": total_timeline_tweets,
        "timeline_n_users": len(all_timeline_users),
        "overlap_users": len(overlap_users),
        "overall_coverage_pct": overall_coverage if total_tl_tweets > 0 else None,
    })
    print(f"\n[measure] Results appended to {outpath}")


# ---------------------------------------------------------------------------
# Subcommand: cache-test
# ---------------------------------------------------------------------------

def cmd_cache_test(args):
    """
    Run the search-based feed fetch repeatedly at fixed intervals.
    Purpose: detect Twitter's cache TTL by observing when new tweets appear.
    """
    base = args.base.rstrip("/")
    session = requests.Session()
    outpath = args.output
    interval = args.interval        # seconds between queries
    repetitions = args.repetitions
    list_name = args.list

    print(f"[cache-test] {repetitions} queries every {interval}s on list '{list_name}'")
    print(f"[cache-test] Expected duration: ~{repetitions * interval / 60:.1f} minutes")
    print()

    previous_tweet_ids = set()
    previous_users = set()
    results = []

    for i in range(repetitions):
        params = {}
        if list_name != "default":
            params["list"] = list_name
        t0 = time.time()
        resp = api_get(session, base, "/", params=params)
        elapsed = time.time() - t0
        rate_limits = extract_rate_limits(resp)

        tweet_ids = set()
        users = set()
        ages = []
        if resp.status_code == 200:
            try:
                data = resp.json()
                for t in data.get("tweets", []):
                    tid = t.get("id", "")
                    if tid:
                        tweet_ids.add(tid)
                    author = t.get("author", {})
                    username = author.get("username", "")
                    if username:
                        users.add(username.lower())
                    created = t.get("created_at", "")
                    if created:
                        try:
                            dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
                            ages.append(epoch_now() - int(dt.timestamp()))
                        except Exception:
                            pass
            except Exception:
                pass

        # Compare with previous
        new_ids = tweet_ids - previous_tweet_ids
        new_users = users - previous_users
        lost_ids = previous_tweet_ids - tweet_ids

        record = {
            "event": "cache_ping",
            "run_id": f"cache_{epoch_now()}",
            "iteration": i,
            "timestamp": ts_now(),
            "http_status": resp.status_code,
            "response_time_seconds": round(elapsed, 3),
            "rate_limits": rate_limits,
            "n_tweets": len(tweet_ids),
            "n_users": len(users),
            "n_new_tweets": len(new_ids),
            "n_new_users": len(new_users),
            "n_lost_tweets": len(lost_ids),
            "tweet_ids": sorted(tweet_ids, key=lambda x: int(x) if x.isdigit() else 0, reverse=True)[:50],
            "users": sorted(users),
            "tweet_ages_seconds": sorted(ages, reverse=True)[:20],
            "min_age": min(ages) if ages else None,
            "max_age": max(ages) if ages else None,
            "mean_age": (sum(ages) / len(ages)) if ages else None,
        }
        results.append(record)
        jsonl_append(outpath, record)

        # Print status
        ts = datetime.now().strftime("%H:%M:%S")
        new_flag = f" +{len(new_ids)} new" if new_ids else ""
        lim = rate_limits.get("remaining", "?")
        print(f"  [{ts}] iter {i+1}/{repetitions}: {len(tweet_ids)} tweets, "
              f"{len(users)} users{new_flag}, "
              f"rate_remaining={lim}, "
              f"{elapsed:.1f}s")

        previous_tweet_ids = tweet_ids
        previous_users = users

        if i < repetitions - 1:
            time.sleep(interval)

    # Summary
    print(f"\n[cache-test] === Summary ===")
    first_n = results[0]["n_tweets"] if results else 0
    last_n = results[-1]["n_tweets"] if results else 0
    total_unique_ids = set()
    for r in results:
        total_unique_ids.update(r.get("tweet_ids", []))
    print(f"  First query: {first_n} tweets")
    print(f"  Last query:  {last_n} tweets")
    print(f"  Unique tweets seen across all queries: {len(total_unique_ids)}")
    print(f"  Results written to {outpath}")


# ---------------------------------------------------------------------------
# Subcommand: report
# ---------------------------------------------------------------------------

def cmd_report(args):
    """
    Generate a summary report from collected measurement data.
    """
    path = args.input
    records = list(jsonl_read(path))

    if not records:
        print("[report] No data found.")
        return

    print(f"[report] Analyzing {len(records)} records from {path}")
    print()

    # Separate by event type
    searches = [r for r in records if r.get("event") == "search_feed"]
    timelines = [r for r in records if r.get("event") == "user_timeline"]
    summaries = [r for r in records if r.get("event") == "summary"]
    cache_pings = [r for r in records if r.get("event") == "cache_ping"]

    if searches:
        print("=== Search Feed Results ===")
        for s in searches:
            print(f"  Run {s.get('run_id', '?')}: {s.get('n_tweets', '?')} tweets, "
                  f"{s.get('n_users', '?')} users, "
                  f"mean age {s.get('mean_age_seconds', '?'):.0f}s, "
                  f"rate_remaining={s.get('rate_limits', {}).get('remaining', '?')}")
        print()

    if timelines:
        successes = [t for t in timelines if t.get("http_status") == 200]
        rate_limited = [t for t in timelines if t.get("http_status") == 429]
        errors = [t for t in timelines if t.get("http_status") not in (200, 429)]
        total_tweets = sum(t.get("tweet_count", 0) for t in successes)
        ages = []
        for t in successes:
            ta = t.get("tweet_ages_seconds", [])
            if ta:
                ages.extend(ta)

        print("=== Individual Timeline Fetches ===")
        print(f"  Attempted: {len(timelines)}")
        print(f"  Succeeded: {len(successes)}")
        print(f"  Rate limited: {len(rate_limited)}")
        print(f"  Errors: {len(errors)}")
        print(f"  Total timeline tweets: {total_tweets}")
        if ages:
            print(f"  Timeline tweet ages: min={min(ages):.0f}s, max={max(ages):.0f}s, "
                  f"mean={sum(ages)/len(ages):.0f}s")
        print()

        # Per-user breakdown
        print("  Per-user tweet counts (top 30 by tweet count):")
        user_counts = [(t.get("username", "?"), t.get("tweet_count", 0)) for t in successes]
        user_counts.sort(key=lambda x: -x[1])
        for username, count in user_counts[:30]:
            print(f"    @{username}: {count} tweets")
        print()

    if summaries:
        print("=== Measurement Summaries ===")
        for s in summaries:
            cov = s.get("overall_coverage_pct")
            cov_str = f"{cov:.1f}%" if cov is not None else "N/A"
            print(f"  Run {s.get('run_id', '?')}: "
                  f"search={s.get('search_n_tweets', '?')} tweets/{s.get('search_n_users', '?')} users, "
                  f"timeline={s.get('timeline_n_tweets', '?')} tweets/{s.get('timeline_n_users', '?')} users, "
                  f"coverage={cov_str}")
        print()

    if cache_pings:
        print("=== Cache Test ===")
        n_iters = len(cache_pings)
        first = cache_pings[0]
        last = cache_pings[-1]
        all_ids = set()
        for p in cache_pings:
            all_ids.update(p.get("tweet_ids", []))
        new_per_iter = [p.get("n_new_tweets", 0) for p in cache_pings]
        print(f"  Iterations: {n_iters}")
        print(f"  Unique tweets seen: {len(all_ids)}")
        print(f"  First: {first.get('n_tweets', '?')} tweets, "
              f"Last: {last.get('n_tweets', '?')} tweets")
        print(f"  New tweets per iteration: min={min(new_per_iter)}, "
              f"max={max(new_per_iter)}, total={sum(new_per_iter)}")
        # Detect if cache refreshed
        seen_increase = any(n > 0 for n in new_per_iter[1:])
        print(f"  New tweets appeared after first query: {'YES' if seen_increase else 'NO'}")
        if seen_increase:
            first_new_idx = next((i for i, n in enumerate(new_per_iter[1:], 1) if n > 0), None)
            if first_new_idx is not None:
                elapsed = first_new_idx * (args.interval if hasattr(args, 'interval') else 0)
                print(f"  First new tweets appeared at iteration {first_new_idx} "
                      f"(~{elapsed}s into test)")
        print()

    if not any([searches, timelines, summaries, cache_pings]):
        print("  (no recognized event types found)")
        print("  Expected events: search_feed, user_timeline, summary, cache_ping")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Nitpick Feed Study Tool — investigate feed freshness",
    )
    parser.add_argument("--base", default="http://localhost:7000",
                        help="Local Nitpick instance URL (default: http://localhost:7000)")

    sub = parser.add_subparsers(dest="command", required=True)

    # --- harvest ---
    p_harvest = sub.add_parser("harvest", help="Harvest users from a remote Nitpick instance")
    p_harvest.add_argument("--remote", required=True,
                           help="Remote instance URL (e.g. https://twitter.ottertime.com)")
    p_harvest.add_argument("-o", "--output", default="data/remote_users.json",
                           help="Output file (default: data/remote_users.json)")
    p_harvest.set_defaults(func=cmd_harvest)

    # --- import ---
    p_import = sub.add_parser("import", help="Import harvested users into local instance")
    p_import.add_argument("input", help="Harvest JSON file from 'harvest' command")
    p_import.add_argument("--source", choices=["lists", "feed", "all"], default="all",
                          help="Which users to import (default: all)")
    p_import.add_argument("--list", default="default",
                          help="Target list name (default: default)")
    p_import.set_defaults(func=cmd_import)

    # --- measure ---
    p_measure = sub.add_parser("measure", help="Run a measurement cycle")
    p_measure.add_argument("-o", "--output", default="data/measurement.jsonl",
                           help="Output JSONL file (default: data/measurement.jsonl)")
    p_measure.add_argument("--list", default="default",
                           help="Feed list to test (default: default)")
    p_measure.set_defaults(func=cmd_measure)

    # --- cache-test ---
    p_cache = sub.add_parser("cache-test", help="Repeated feed queries at timed intervals")
    p_cache.add_argument("-o", "--output", default="data/cache_test.jsonl",
                         help="Output JSONL file")
    p_cache.add_argument("--interval", type=int, default=120,
                         help="Seconds between queries (default: 120)")
    p_cache.add_argument("--repetitions", type=int, default=15,
                         help="Number of queries (default: 15)")
    p_cache.add_argument("--list", default="default",
                         help="Feed list to test (default: default)")
    p_cache.set_defaults(func=cmd_cache_test)

    # --- report ---
    p_report = sub.add_parser("report", help="Generate summary from collected data")
    p_report.add_argument("input", help="JSONL file with measurement data")
    p_report.set_defaults(func=cmd_report)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
