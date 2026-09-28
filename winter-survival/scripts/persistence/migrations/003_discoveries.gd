extends RefCounted
## Migration 3: zone discovery (H2, PLAN C35; docs/research/10_hud_ux.md appendix §6.1 and §8.7). Discovering a zone
## is server-authoritative and, with the `shared_discovery` rule (default on), shared by the group: one row per zone
## and scope. `scope` = "group" (shared) or the discoverer's token hash (rule off: every player keeps their own).
## `by_name` is the display name the feed shows («Ana descubrió: Las Torres»), `day` the game day, `ts` unix time.

const VERSION := 3


func sqlite() -> PackedStringArray:
	return PackedStringArray([
		"CREATE TABLE IF NOT EXISTS discoveries(scope TEXT NOT NULL, zone_id TEXT NOT NULL, by_token TEXT, by_name TEXT, day INT, ts INT, PRIMARY KEY(scope, zone_id));",
	])


func document(doc: Dictionary) -> void:
	if not doc.get("discoveries") is Dictionary:
		doc["discoveries"] = {}
