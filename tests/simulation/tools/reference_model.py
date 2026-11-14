"""Reference model of Task 01 simulation semantics for contract 2.0.0.

Purpose: generate expected values for the synthetic fixtures under
tests/simulation/fixtures/. It is a test oracle, not the runtime. It implements
only the subset of the contract the fixtures exercise and raises on anything else.
A mistaken model must not define correctness by itself, so closed_form_checks.py
re-derives key totals independently.

Stub policies standing in for Task 02 (world service) and Task 03 (crew adapter)
are documented in tests/simulation/fixtures/README.md, section "Stub policies".
"""
import copy
import hashlib
import json
from collections import deque

CONTRACT_VERSION = "2.0.0"
SNAPSHOT_VERSION = 2
SAVE_VERSION = 2
CREW_TASKS_SCHEMA = 1
RNG_ALGORITHM = "godot-rng-4.7.2"
# Measured with the local Godot 4.7.2 build: RandomNumberGenerator.seed = 42 -> state.
# No fixture consumes randomness, so the state never changes after seeding.
RNG_STATE_BY_SEED = {"42": "708718527385777908"}

DT = 1.0
RATE_ZERO = 1e-12
TERMINAL_TASK = ("completed", "cancelled", "failed")
TERMINAL_EXPEDITION = ("completed", "failed")
PAYLOAD_KEYS = {
    "place_building": {"definition_id", "cell", "rotation_quarters"},
    "set_building_enabled": {"building_id", "enabled"},
    "assign_task": {"task_id", "crew_ids", "priority"},
    "cancel_task": {"task_id"},
    "start_eva": {"site_id", "crew_ids", "work_duration_s", "oxygen_kg_per_crew", "battery_kwh_per_crew"},
    "recall_eva": {"expedition_id"},
    "set_time_scale": {"time_scale"},
}
RUNTIME_ID_KEYS = ("building_id", "crew_id", "expedition_id", "site_id", "task_id")
# Phase order used for tick events (contract section 9 / 11).
PHASE = {"environment": 1, "intent": 2, "power": 3, "process": 4, "demand": 5, "progress": 6,
         "hazards": 7, "finalize": 8}


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))


def fmt_id(kind, n):
    return f"{kind}_{n:06d}"


def entity_refs(primary, data):
    """Sorted unique runtime IDs referenced by an event (contract section 11)."""
    ids = set(primary)
    for k, v in (data or {}).items():
        if k in RUNTIME_ID_KEYS and isinstance(v, str):
            ids.add(v)
        if k == "crew_ids" and isinstance(v, list):
            ids.update(v)
    return sorted(ids)


class ReferenceModel:
    def __init__(self, cfg, content):
        """content: dict with scenario, science, buildings, crew, templates, map, registry."""
        self.cfg = cfg
        self.sc = content["scenario"]
        self.sci = content["science"]
        self.bdefs = content["buildings"]
        self.cdefs = {d["id"]: d for d in content["crew"]["definitions"]}
        self.tpl = content["templates"]["templates"]
        self.map = content["map"]
        self.registry = {r["id"]: r for r in content["registry"]["resources"]}
        self.world_injected_blocked = set()   # harness-only fault injection for the stub world
        self._begin()
        self.s = self._initial_state()

    # ------------------------------------------------------------------ init
    def _initial_state(self):
        cfg, sc = self.cfg, self.sc
        s = {
            "campaign_id": cfg["campaign_id"],
            "tick_index": 0, "time_scale": 1, "accumulator_s": 0.0, "revision": 0,
            "map": {"id": self.map["id"], "revision": self.map["revision"]},
            "rng": {"algorithm_id": RNG_ALGORITHM, "seed": cfg["seed"], "state": RNG_STATE_BY_SEED[cfg["seed"]]},
            "id_counters": {"building": 0, "crew": 0, "event": 0, "expedition": 0, "task": 0},
            "next_receive_sequence": 1, "command_journal": {}, "pending_command_ids": [],
            "committed_effects": {},
            "rates": {rid: 0.0 for rid in self.registry},
            "amounts": {rid: sc["starting_inventory"][rid] for rid in sorted(self.registry) if rid != "energy_kwh"},
            "buildings": {}, "active_events": {}, "sites": {},
            "technology": {"unlocked_ids": list(sc["technology_unlocked_ids"])},
            "per_battery_energy": {}, "prepaid_build_costs": {}, "crop_cycles": {}, "scheduled_events": [],
            "power_summary": {"generated_kw": 0.0, "requested_kw": 0.0, "served_kw": 0.0},
            "alerts": {},
            "crew": {}, "tasks": {}, "expeditions": {},
            "return_caches": {}, "completion_markers": {}, "private_counters": {},
        }
        self.s = s
        for b in sc["starting_buildings"]:
            bid = self.alloc("building")
            s["buildings"][bid] = self.building_record(bid, b["definition_id"], b["cell"], b["rotation_quarters"],
                                                       "commissioned", b["enabled"], b["condition"], None, 1.0)
            if "battery_stored_kwh" in b:
                s["per_battery_energy"][bid] = b["battery_stored_kwh"]
        airlock = self.map["base_airlock_cell"]
        for did in cfg["initial_crew_definition_ids"]:
            cid = self.alloc("crew")
            d = self.cdefs[did]
            s["crew"][cid] = {
                "id": cid, "definition_id": did, "display_name": d["display_name"],
                "status": "idle", "location_kind": "base", "position_m": self.center(airlock),
                "task_id": None, "expedition_id": None, "health": 1.0, "fatigue": 0.0, "stress": 0.0,
                "radiation_dose_msv": 0.0, "skills": dict(d["skills"]),
            }
        for site in sc["sites"]:
            s["sites"][site["id"]] = {"id": site["id"], "definition_id": site["definition_id"], "cell": site["cell"],
                                      "reserved_by_expedition_id": None, "remaining_cargo": dict(site["cargo"])}
        return s

    # ------------------------------------------------------------------ helpers
    def alloc(self, kind):
        self.s["id_counters"][kind] += 1
        return fmt_id(kind, self.s["id_counters"][kind])

    @staticmethod
    def center(cell):
        return [cell[0] + 0.5, 0.0, cell[1] + 0.5]

    @staticmethod
    def building_record(bid, did, cell, rot, life, enabled, cond, task_id, progress):
        return {"id": bid, "definition_id": did, "cell": list(cell), "rotation_quarters": rot,
                "lifecycle": life, "enabled": enabled, "condition": cond,
                "construction_task_id": task_id, "construction_progress": progress,
                "power_requested_kw": 0.0, "power_served_kw": 0.0, "operating_fraction": 0.0,
                "blocking_codes": ["constructing"] if life == "constructing" else []}

    @staticmethod
    def live(b):
        return b["lifecycle"] == "commissioned"

    def bdef(self, b):
        return self.bdefs[b["definition_id"]]

    def speed(self, crew_ids):
        return min(self.cdefs[self.s["crew"][c]["definition_id"]]["movement_speed_m_per_s"] for c in crew_ids)

    def batteries(self):
        return [bid for bid in sorted(self.s["per_battery_energy"]) if self.live(self.s["buildings"][bid])]

    def battery_cap(self, bid):
        return self.bdef(self.s["buildings"][bid])["storage_capacity"]["energy_kwh"]

    def is_accumulator(self, rid):
        return self.registry[rid]["capacity_policy"] == "accumulator"

    def base_capacity(self, rid):
        if self.is_accumulator(rid):
            return None
        if rid == "energy_kwh":
            return sum(self.battery_cap(b) for b in self.batteries())
        cap = self.sc["starting_storage_capacity"].get(rid, 0.0)
        for b in self.s["buildings"].values():
            if self.live(b):
                cap += self.bdef(b)["storage_capacity"].get(rid, 0.0)
        return cap

    def headroom(self, rid):
        cap = self.base_capacity(rid)
        return float("inf") if cap is None else cap - self.base_amount(rid)

    def base_amount(self, rid):
        if rid == "energy_kwh":
            return sum(self.s["per_battery_energy"][b] for b in self.batteries())
        return self.s["amounts"][rid]

    def add_base(self, rid, q):
        assert rid != "energy_kwh"
        self.s["amounts"][rid] += q

    # Ledger account paths resolve to fields of existing authoritative records (spec section 7).
    def _slot(self, path):
        p = path.split("/")
        if p[0] == "suit":
            return self.s["expeditions"][p[1]]["suit_stores"][p[2]], p[3], False
        if p[0] == "cargo":
            return self.s["expeditions"][p[1]]["cargo"], p[2], True
        if p[0] == "return_cache":
            return self.s["return_caches"].setdefault(p[1], {}), p[2], True
        if p[0] == "site":
            return self.s["sites"][p[1]]["remaining_cargo"], p[2], False
        raise KeyError(path)

    def acct(self, path):
        d, k, _ = self._slot(path)
        return d.get(k, 0.0)

    def add_acct(self, path, q):
        d, k, drop_zero = self._slot(path)
        v = d.get(k, 0) + q
        if abs(v) <= 1e-15:
            v = 0.0 if isinstance(v, float) else 0
            if drop_zero:
                d.pop(k, None)
                if path.startswith("return_cache/") and not d:
                    self.s["return_caches"].pop(path.split("/")[1], None)
                return
        d[k] = v

    def energy_debit(self, q):
        for bid in self.batteries():
            take = min(q, self.s["per_battery_energy"][bid])
            self.s["per_battery_energy"][bid] -= take
            q -= take
        assert q <= 1e-12

    def energy_credit(self, q):
        accepted = 0.0
        for bid in self.batteries():
            room = self.battery_cap(bid) - self.s["per_battery_energy"][bid]
            take = min(q - accepted, room)
            self.s["per_battery_energy"][bid] += take
            accepted += take
        return accepted

    def flow(self, name, q):
        if q:
            self.call_flows[name] = self.call_flows.get(name, 0.0) + q

    def marker(self, eid, kind, debits, credits):
        """Persisted completion marker; a retry must match the normalized effect."""
        rec = {"ok": True, "applied_tick": self.s["tick_index"], "kind": kind,
               "debits": dict(sorted(debits.items())), "credits": dict(sorted(credits.items()))}
        old = self.s["committed_effects"].get(eid)
        if old is not None:
            assert canon({k: old[k] for k in ("kind", "debits", "credits")}) == \
                canon({k: rec[k] for k in ("kind", "debits", "credits")}), f"effect id reused: {eid}"
            return False
        self.s["committed_effects"][eid] = rec
        return True

    # ------------------------------------------------------------------ events
    def _begin(self):
        self.flushes = []
        self.outbox = []
        self.resolved = []
        self.tick_events = []
        self.call_flows = {}
        self.state_changed = False

    def emit_now(self, typ, ids, data):
        eid = self.alloc("event")
        self.outbox.append({"id": eid, "type": typ, "tick_index": self.s["tick_index"],
                            "entity_ids": ids, "data": data})

    def tick_event(self, phase, typ, primary, data, effect_id=""):
        self.tick_events.append((PHASE[phase], entity_refs(primary, data), typ, effect_id, data))

    def flush(self, after):
        if self.outbox:
            self.flushes.append({"after": after, "tick_index": self.s["tick_index"], "events": self.outbox})
        self.outbox = []

    # ------------------------------------------------------------------ world stub
    def blocked_cells(self):
        cells = set(self.world_injected_blocked)
        for b in self.s["buildings"].values():
            if b["lifecycle"] != "destroyed":
                for off in self.bdef(b)["footprint_cells"]:
                    cells.add(tuple(self.rot(off, b["rotation_quarters"], b["cell"])))
        return cells

    @staticmethod
    def rot(off, q, at):
        x, z = off
        for _ in range(q % 4):
            x, z = -z, x
        return [at[0] + x, at[1] + z]

    def in_bounds(self, c):
        w, h = self.map["size_cells"]
        return 0 <= c[0] < w and 0 <= c[1] < h

    def bfs(self, a, b, blocked):
        a, b = tuple(a), tuple(b)
        if a in blocked or b in blocked:
            return None
        prev = {a: None}
        q = deque([a])
        while q:
            c = q.popleft()
            if c == b:
                break
            for dx, dz in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                n = (c[0] + dx, c[1] + dz)
                if self.in_bounds(n) and n not in blocked and n not in prev:
                    prev[n] = c
                    q.append(n)
        if b not in prev:
            return None
        path, c = [], b
        while c is not None:
            path.append(list(c))
            c = prev[c]
        return path[::-1]

    def validate_placement(self, did, cell, rot):
        d = self.bdefs[did]
        occ = [self.rot(o, rot, cell) for o in d["footprint_cells"]]
        ent = [self.rot(o, rot, cell) for o in d["entrance_cells"]]
        blocked = self.blocked_cells()
        bad = {"valid": False, "code": "placement_blocked", "reason": "", "occupied_cells": [], "entrance_cells": []}
        for c in occ + ent:
            if not self.in_bounds(c):
                return dict(bad, reason="out of bounds")
        for c in occ:
            if tuple(c) in blocked:
                return dict(bad, reason=f"cell {c} is occupied")
        new_blocked = blocked | {tuple(c) for c in occ}
        airlock = self.map["base_airlock_cell"]
        if not any(self.bfs(airlock, e, new_blocked) for e in ent if tuple(e) not in new_blocked):
            return dict(bad, reason="no reachable entrance")
        return {"valid": True, "code": "ok", "reason": "", "occupied_cells": occ, "entrance_cells": ent}

    def query_route(self, a, b):
        blocked = self.blocked_cells()
        path = self.bfs(a, b, blocked)
        if path is None:
            return {"reachable": False, "code": "route_unreachable", "reason": "no route", "route_id": None,
                    "waypoints_m": [], "distance_m": 0.0}
        key = canon({"map_id": self.map["id"], "map_revision": self.map["revision"],
                     "blocked_cells": sorted(list(c) for c in blocked), "from_cell": list(a), "to_cell": list(b)})
        rid = "route_" + hashlib.sha256(key.encode()).hexdigest()[:16]
        return {"reachable": True, "code": "ok", "reason": "", "route_id": rid,
                "waypoints_m": [self.center(c) for c in path], "distance_m": float(len(path) - 1)}

    # ------------------------------------------------------------------ submission
    @staticmethod
    def rejected(cid, code, reason):
        return {"accepted": False, "command_id": cid, "reason": reason, "code": code,
                "receive_sequence": None, "status": "rejected", "duplicate": False, "result": None}

    def submit(self, cmd):
        cid = cmd.get("command_id")
        if cmd.get("contract_version") != CONTRACT_VERSION:
            return self.rejected(cid, "unsupported_contract", "contract_version must be 2.0.0")
        keys = PAYLOAD_KEYS.get(cmd.get("type"))
        if keys is None:
            return self.rejected(cid, "unsupported_command", "unknown command type")
        if set(cmd.get("payload", {})) != keys:
            return self.rejected(cid, "invalid_schema", "payload keys do not match the command schema")
        j = self.s["command_journal"]
        if cid in j:
            e = j[cid]
            if canon(e["normalized"]) != canon(cmd):
                return self.rejected(cid, "command_id_conflict", "command_id reused with different content")
            return {"accepted": True, "command_id": cid, "reason": "", "code": "ok",
                    "receive_sequence": e["receive_sequence"], "status": e["status"], "duplicate": True,
                    "result": copy.deepcopy(e["result"])}
        seq = self.s["next_receive_sequence"]
        self.s["next_receive_sequence"] += 1
        j[cid] = {"normalized": copy.deepcopy(cmd), "receive_sequence": seq, "status": "queued", "result": None}
        self.s["pending_command_ids"].append(cid)
        return {"accepted": True, "command_id": cid, "reason": "", "code": "ok", "receive_sequence": seq,
                "status": "queued", "duplicate": False, "result": None}

    # ------------------------------------------------------------------ boundary
    def boundary(self):
        changed = False
        ids = list(self.s["pending_command_ids"])
        self.s["pending_command_ids"] = []
        for cid in ids:
            cmd = self.s["command_journal"][cid]["normalized"]
            before = copy.deepcopy(self.s)
            res, domain_events, state_changed = getattr(self, "cmd_" + cmd["type"])(cmd)
            if not res["success"]:
                self.s = before          # working copy discarded: no partial effects
                domain_events, state_changed = [], False
            if state_changed:
                self.s["revision"] += 1
                changed = True
            res["resolved_tick"] = self.s["tick_index"]
            entry = self.s["command_journal"][cid]
            entry["status"] = "resolved"
            entry["result"] = res
            self.emit_now("command_result", entity_refs([], res["data"]), dict(res, command_id=cid))
            for typ, primary, data in domain_events:
                self.emit_now(typ, entity_refs(primary, data), data)
            self.resolved.append([cid, res["success"], res["reason"]])
        return changed

    @staticmethod
    def ok(data):
        return {"success": True, "code": "ok", "reason": "", "resolved_tick": None, "data": data}

    @staticmethod
    def fail(code, reason, data):
        return {"success": False, "code": code, "reason": reason, "resolved_tick": None, "data": data}

    def cmd_set_time_scale(self, cmd):
        ts = cmd["payload"]["time_scale"]
        changed = ts != self.s["time_scale"]
        self.s["time_scale"] = ts
        return self.ok({"time_scale": ts}), [], changed

    def cmd_set_building_enabled(self, cmd):
        p = cmd["payload"]
        b = self.s["buildings"].get(p["building_id"])
        if b is None:
            return self.fail("unknown_entity", "unknown building", {"building_id": p["building_id"]}), [], False
        changed = b["enabled"] != p["enabled"]
        b["enabled"] = p["enabled"]
        return self.ok({"building_id": b["id"]}), [], changed

    def cmd_place_building(self, cmd):
        p = cmd["payload"]
        did = p["definition_id"]
        if did not in self.bdefs:
            return self.fail("unknown_definition", "unknown definition", {"definition_id": did}), [], False
        v = self.validate_placement(did, p["cell"], p["rotation_quarters"])
        if not v["valid"]:
            return self.fail("placement_blocked", v["reason"], {"definition_id": did, "cell": p["cell"]}), [], False
        d = self.bdefs[did]
        for rid in sorted(d["build_cost"]):
            need, have = d["build_cost"][rid], self.base_amount(rid)
            if have < need:
                return self.fail("insufficient_resources", f"{rid}: need {need}, available {have}",
                                 {"definition_id": did, "resource_id": rid}), [], False
        for rid, q in d["build_cost"].items():
            self.add_base(rid, -q)
        bid = self.alloc("building")
        tid = self.alloc("task")
        self.marker(f"cmd:{cmd['command_id']}:build_cost", "build_cost",
                    {f"base/{r}": q for r, q in d["build_cost"].items()}, {})
        self.s["buildings"][bid] = self.building_record(bid, did, p["cell"], p["rotation_quarters"],
                                                        "constructing", True, 1.0, tid, 0.0)
        t = self.tpl["construct"]          # template supplied by apply_command(place_building)
        self.s["tasks"][tid] = {"id": tid, "kind": "construct", "target_id": bid, "status": "queued",
                                "priority": t["default_priority"], "crew_required": t["crew_required"],
                                "assigned_crew_ids": [], "required_work_s": d["construction_work_s"],
                                "completed_work_s": 0.0, "blocked_code": None, "expedition_id": None}
        self.s["prepaid_build_costs"][tid] = dict(d["build_cost"])
        return self.ok({"building_id": bid, "task_id": tid}), [], True

    def cmd_assign_task(self, cmd):
        p = cmd["payload"]
        t = self.s["tasks"].get(p["task_id"])
        if t is None:
            return self.fail("unknown_entity", "unknown task", {"task_id": p["task_id"]}), [], False
        if t["status"] in TERMINAL_TASK or t["kind"] == "eva":
            return self.fail("invalid_state", "task not assignable", {"task_id": t["id"]}), [], False
        if len(t["assigned_crew_ids"]) + len(p["crew_ids"]) > t["crew_required"]:
            return self.fail("invalid_value", "more crew than the task requires", {"task_id": t["id"]}), [], False
        for c in p["crew_ids"]:
            cr = self.s["crew"].get(c)
            if cr is None or cr["status"] != "idle" or cr["location_kind"] != "base":
                return self.fail("crew_unavailable", f"{c} is not idle at base", {"task_id": t["id"], "crew_id": c}), [], False
        for c in p["crew_ids"]:
            self.s["crew"][c].update(status="working", task_id=t["id"])
        t["assigned_crew_ids"] = sorted(t["assigned_crew_ids"] + p["crew_ids"])
        t["status"] = "active"
        t["priority"] = p["priority"]
        return self.ok({"task_id": t["id"], "crew_ids": sorted(p["crew_ids"])}), [], True

    def cmd_cancel_task(self, cmd):
        raise NotImplementedError("cancel_task is not exercised by the v2 fixtures")

    def cmd_start_eva(self, cmd):
        """Check order (contract section 8): site, crew, routes, reserve policy, suit capacity, base stock."""
        p = cmd["payload"]
        site = self.s["sites"].get(p["site_id"])
        if site is None:
            return self.fail("unknown_entity", "unknown site", {"site_id": p["site_id"]}), [], False
        if site["reserved_by_expedition_id"] is not None:
            return self.fail("invalid_state", "site reserved", {"site_id": site["id"]}), [], False
        for c in p["crew_ids"]:
            cr = self.s["crew"].get(c)
            if cr is None or cr["status"] != "idle" or cr["location_kind"] != "base":
                return self.fail("crew_unavailable", f"{c} is not idle at base", {"crew_id": c}), [], False
        airlock = self.map["base_airlock_cell"]
        out = self.query_route(airlock, site["cell"])
        back = self.query_route(site["cell"], airlock)
        if not out["reachable"] or not back["reachable"]:
            return self.fail("route_unreachable", "no route", {"site_id": site["id"]}), [], False
        dur = out["distance_m"] / self.speed(p["crew_ids"]) + p["work_duration_s"] + back["distance_m"] / self.speed(p["crew_ids"])
        rates = self.sci["crew_metabolism"]["eva_suit_rates_per_s"]
        rf = self.sci["eva_policy"]["reserve_fraction"]
        o2, bat = p["oxygen_kg_per_crew"], p["battery_kwh_per_crew"]
        if o2 - rates["oxygen_kg"] * dur < rf * o2 or bat - rates["battery_kwh"] * dur < rf * bat:
            return self.fail("reserve_insufficient", "projected return reserve below policy", {"site_id": site["id"]}), [], False
        for c in sorted(p["crew_ids"]):
            cap = self.cdefs[self.s["crew"][c]["definition_id"]]["suit_capacity"]
            if o2 > cap["oxygen_kg"] or bat > cap["battery_kwh"]:
                return self.fail("capacity_exceeded", f"suit capacity exceeded for {c}", {"crew_id": c}), [], False
        n = len(p["crew_ids"])
        if self.base_amount("oxygen_kg") < o2 * n:
            return self.fail("insufficient_resources", "oxygen", {"resource_id": "oxygen_kg"}), [], False
        if self.base_amount("energy_kwh") < bat * n:
            return self.fail("insufficient_resources", "energy", {"resource_id": "energy_kwh"}), [], False
        eid = self.alloc("expedition")
        tid = self.alloc("task")
        crew_ids = sorted(p["crew_ids"])
        self.s["expeditions"][eid] = {
            "id": eid, "site_id": site["id"], "task_id": tid, "crew_ids": crew_ids, "status": "outbound",
            "route_id": out["route_id"], "route_waypoints_m": out["waypoints_m"],
            "route_distance_m": out["distance_m"], "route_progress_m": 0.0,
            "work_required_s": float(p["work_duration_s"]), "work_completed_s": 0.0,
            "suit_stores": {c: {"oxygen_kg": 0.0, "battery_kwh": 0.0} for c in crew_ids},
            "cargo": {}, "return_margin_s": None, "recall_requested": False,
        }
        self.add_base("oxygen_kg", -o2 * n)
        self.energy_debit(bat * n)
        credits = {}
        for c in crew_ids:
            self.add_acct(f"suit/{eid}/{c}/oxygen_kg", o2)
            self.add_acct(f"suit/{eid}/{c}/battery_kwh", bat)
            credits[f"suit/{eid}/{c}/oxygen_kg"] = o2
            credits[f"suit/{eid}/{c}/battery_kwh"] = bat
            self.s["crew"][c].update(status="eva", location_kind="eva", expedition_id=eid, task_id=tid)
        self.marker(f"crew_tasks:{eid}:eva_load:0", "eva_load",
                    {"base/oxygen_kg": o2 * n, "base/energy_kwh": bat * n}, credits)
        self.s["tasks"][tid] = {"id": tid, "kind": "eva", "target_id": site["id"], "status": "active",
                                "priority": self.tpl["eva"]["default_priority"], "crew_required": n,
                                "assigned_crew_ids": crew_ids, "required_work_s": float(p["work_duration_s"]),
                                "completed_work_s": 0.0, "blocked_code": None, "expedition_id": eid}
        site["reserved_by_expedition_id"] = eid
        self.update_margin(eid)
        return (self.ok({"expedition_id": eid, "task_id": tid}),
                [("eva_launched", [eid], {"site_id": site["id"], "crew_ids": crew_ids})], True)

    def current_cell(self, e):
        if e["status"] in ("working",) or (e["status"] == "stranded" and e["route_progress_m"] >= e["route_distance_m"]):
            return self.s["sites"][e["site_id"]]["cell"]
        p = e["route_progress_m"]
        assert float(p).is_integer(), "fixtures only replan at whole-cell positions"
        wp = e["route_waypoints_m"][int(p)]
        return [int(wp[0] - 0.5), int(wp[2] - 0.5)]

    def cmd_recall_eva(self, cmd):
        eid = cmd["payload"]["expedition_id"]
        e = self.s["expeditions"].get(eid)
        if e is None:
            return self.fail("unknown_entity", "unknown expedition", {"expedition_id": eid}), [], False
        if e["status"] == "returning":
            return self.ok({"expedition_id": eid}), [], False
        if e["status"] in TERMINAL_EXPEDITION:
            return self.fail("invalid_state", f"expedition is {e['status']}", {"expedition_id": eid}), [], False
        here = self.current_cell(e)
        back = self.query_route(here, self.map["base_airlock_cell"])
        if not back["reachable"]:
            if e["status"] == "stranded":
                return self.fail("route_unreachable", "no return route from the current position",
                                 {"expedition_id": eid}), [], False
            e.update(status="stranded", recall_requested=True)
            self.update_margin(eid)
            return self.ok({"expedition_id": eid}), [("eva_recalled", [eid], {"status": "stranded"})], True
        e.update(status="returning", recall_requested=True, route_id=back["route_id"],
                 route_waypoints_m=back["waypoints_m"], route_distance_m=back["distance_m"], route_progress_m=0.0)
        self.update_margin(eid)
        return self.ok({"expedition_id": eid}), [("eva_recalled", [eid], {"status": "returning"})], True

    # ------------------------------------------------------------------ tick
    def tick(self):
        s = self.s
        k = s["tick_index"]
        before = {rid: self.base_amount(rid) for rid in self.registry}
        self.overflowed = set()
        self.tick_events = []
        # 1 environment: no scheduled events in the fixtures
        # 2 intent: release crew from terminal non-EVA tasks
        for cid in sorted(s["crew"]):
            c = s["crew"][cid]
            if c["status"] == "working" and c["task_id"] and s["tasks"][c["task_id"]]["status"] in TERMINAL_TASK:
                c.update(status="idle", task_id=None)
        self.phase_power()
        self.phase_process()
        unmet = self.phase_demand()
        self.phase_progress(unmet)
        # 7 losses/hazards: zero synthetic leakage; CO2 hazard surfaces as the co2_high alert
        self.phase_finalize(k, before)

    def phase_power(self):
        s = self.s
        blds = s["buildings"]
        gen = 0.0
        for bid in sorted(blds):
            b = blds[bid]
            b["power_requested_kw"] = 0.0
            b["power_served_kw"] = 0.0
            if self.live(b) and b["enabled"] and self.bdef(b)["power_generation_kw"] > 0:
                gen += self.bdef(b)["power_generation_kw"] * b["condition"]
        cons = sorted([b for b in blds.values() if self.live(b) and b["enabled"] and self.bdef(b)["power_demand_kw"] > 0],
                      key=lambda b: (-self.bdef(b)["power_priority"], b["id"]))
        bats = [bid for bid in self.batteries() if blds[bid]["enabled"]]
        deliverable = {}
        for bid in bats:
            d = self.bdef(blds[bid])
            deliverable[bid] = min(d["battery_discharge_limit_kw"],
                                   s["per_battery_energy"][bid] * d["battery_discharge_efficiency"] * 3600.0 / DT)
        delivered = {bid: 0.0 for bid in bats}
        rem, requested, served_total = gen, 0.0, 0.0
        for b in cons:
            need = self.bdef(b)["power_demand_kw"]
            requested += need
            got = min(need, rem)
            rem -= got
            for bid in bats:
                if got >= need:
                    break
                take = min(need - got, deliverable[bid] - delivered[bid])
                delivered[bid] += take
                got += take
            b["power_requested_kw"] = need
            b["power_served_kw"] = got
            served_total += got
        for bid in bats:
            if delivered[bid] > 0:
                d = self.bdef(blds[bid])
                out_kwh = delivered[bid] * DT / 3600.0
                stored = out_kwh / d["battery_discharge_efficiency"]
                s["per_battery_energy"][bid] = max(0.0, s["per_battery_energy"][bid] - stored)
                self.flow("external/battery_loss", stored - out_kwh)
        for bid in bats:
            if rem <= 0 or delivered[bid] > 0:
                continue
            d = self.bdef(blds[bid])
            room = self.battery_cap(bid) - s["per_battery_energy"][bid]
            inp = min(d["battery_charge_limit_kw"], rem, room * 3600.0 / (DT * d["battery_charge_efficiency"]))
            rem -= inp
            in_kwh = inp * DT / 3600.0
            s["per_battery_energy"][bid] += in_kwh * d["battery_charge_efficiency"]
            self.flow("external/battery_loss", in_kwh * (1 - d["battery_charge_efficiency"]))
        self.flow("external/curtailment", rem * DT / 3600.0)
        s["power_summary"] = {"generated_kw": gen, "requested_kw": requested, "served_kw": served_total}

    def phase_process(self):
        s = self.s
        for bid in sorted(s["buildings"]):
            b = s["buildings"][bid]
            if b["lifecycle"] == "constructing":
                b["operating_fraction"], b["blocking_codes"] = 0.0, ["constructing"]
            elif not b["enabled"]:
                b["operating_fraction"], b["blocking_codes"] = 0.0, ["disabled"]
            else:
                b["operating_fraction"], b["blocking_codes"] = b["condition"], []
        procs = sorted([b for b in s["buildings"].values() if self.live(b) and b["enabled"]
                        and (self.bdef(b)["process"]["inputs_per_s"] or self.bdef(b)["process"]["outputs_per_s"])],
                       key=lambda b: (-self.bdef(b)["process_priority"], b["id"]))
        for b in procs:
            d = self.bdef(b)
            dem = d["power_demand_kw"]
            pf = b["power_served_kw"] / dem if dem > 0 else 1.0
            codes = []
            if dem > 0 and b["power_served_kw"] <= 0:
                codes.append("no_power")
            elif dem > 0 and pf < 1.0:
                codes.append("partial_power")
            f = min(pf, b["condition"])
            for rid, rate in sorted(d["process"]["inputs_per_s"].items()):
                need = rate * DT
                fr = self.base_amount(rid) / need if need > 0 else 1.0
                if fr < 1.0:
                    codes.append(f"input_limited:{rid}")
                f = min(f, fr)
            for rid, rate in sorted(d["process"]["outputs_per_s"].items()):
                need = rate * DT
                fr = 1.0 if need <= 0 else self.headroom(rid) / need
                if fr < 1.0:
                    codes.append(f"output_full:{rid}")
                f = min(f, fr)
            f = max(0.0, min(1.0, f))
            for rid, rate in d["process"]["inputs_per_s"].items():
                self.add_base(rid, -rate * DT * f)
            for rid, rate in d["process"]["outputs_per_s"].items():
                self.add_base(rid, rate * DT * f)
            if not d["process"]["outputs_per_s"]:
                for rid, rate in d["process"]["inputs_per_s"].items():
                    self.flow(f"external/process_removal/{rid}", rate * DT * f)
            if pf > 0:
                idle = b["power_served_kw"] * DT / 3600.0 * (1.0 - f / pf)
                if idle > 1e-15:
                    self.flow("external/idle_power_loss", idle)
            b["operating_fraction"] = f
            b["blocking_codes"] = sorted(codes)

    def phase_demand(self):
        s = self.s
        met = self.sci["crew_metabolism"]
        unmet = {}
        living = [c for _, c in sorted(s["crew"].items()) if c["status"] != "dead"]
        base = [c for c in living if c["location_kind"] == "base"]
        eva = [c for c in living if c["location_kind"] == "eva"]
        need_code = {"oxygen_kg": "oxygen", "potable_water_kg": "water", "food_kcal": "food"}

        def act(c):
            return "working" if c["status"] in ("working", "travelling") else "idle"
        for rid in sorted({r for a in met["base_activity_rates_per_s"].values() for r in a}):
            reqs = [(c, met["base_activity_rates_per_s"][act(c)][rid] * DT) for c in base]
            total = sum(q for _, q in reqs)
            if total <= 0:
                continue
            frac = min(1.0, self.base_amount(rid) / total)
            used = sum(q * frac for _, q in reqs)
            if frac < 1.0:
                for c, _ in reqs:
                    unmet.setdefault(c["id"], []).append(need_code[rid])
            self.add_base(rid, -used)
            self.flow(f"external/metabolism_in/{rid}", used)
        for rid, rate in sorted(met["base_outputs_per_s"].items()):
            q = rate * DT * len(base)
            put = min(q, self.headroom(rid))       # accumulators: headroom is infinite
            self.add_base(rid, put)
            self.flow(f"external/metabolism_out/{rid}", put)
            if q - put > 1e-15:
                # Obligatory metabolic waste that cannot fit: explicit unrecoverable loss + storage_full.
                self.flow(f"external/capacity_overflow_loss/{rid}", q - put)
                self.overflowed.add(rid)
        sr = met["eva_suit_rates_per_s"]
        for c in eva:
            e = c["expedition_id"]
            for key, code in (("oxygen_kg", "oxygen"), ("battery_kwh", "suit_energy")):
                path = f"suit/{e}/{c['id']}/{key}"
                need = sr[key] * DT
                take = min(need, self.acct(path))
                self.add_acct(path, -take)
                self.flow(f"external/suit_use/{key}", take)
                if take < need:
                    unmet.setdefault(c["id"], []).append(code)
        return unmet

    def update_margin(self, eid):
        e = self.s["expeditions"][eid]
        sr = self.sci["crew_metabolism"]["eva_suit_rates_per_s"]
        if e["status"] in TERMINAL_EXPEDITION or e["status"] == "stranded":
            e["return_margin_s"] = None
            return
        endurance = min(min(self.acct(f"suit/{eid}/{c}/oxygen_kg") / sr["oxygen_kg"],
                            self.acct(f"suit/{eid}/{c}/battery_kwh") / sr["battery_kwh"]) for c in e["crew_ids"])
        speed = self.speed(e["crew_ids"])
        if e["status"] == "returning":
            ret = (e["route_distance_m"] - e["route_progress_m"]) / speed
        else:
            back = self.query_route(self.current_cell(e), self.map["base_airlock_cell"])
            if not back["reachable"]:
                e["return_margin_s"] = None
                return
            ret = back["distance_m"] / speed
        e["return_margin_s"] = endurance - ret

    @staticmethod
    def point_on_route(e):
        wps, p = e["route_waypoints_m"], e["route_progress_m"]
        i = min(int(p), len(wps) - 1)
        if i == len(wps) - 1:
            return list(wps[-1])
        a, b, t = wps[i], wps[i + 1], p - int(p)
        return [a[j] + (b[j] - a[j]) * t for j in range(3)]

    def phase_progress(self, unmet):
        s = self.s
        rate = self.tpl["construct"]["labor_rate_work_s_per_crew_s"]
        for tid in sorted(s["tasks"]):
            t = s["tasks"][tid]
            if t["kind"] != "construct" or t["status"] != "active":
                continue
            labor = sum(rate * DT for cid in sorted(t["assigned_crew_ids"])
                        if s["crew"][cid]["status"] == "working" and s["crew"][cid]["location_kind"] == "base"
                        and cid not in unmet)
            t["completed_work_s"] = min(t["required_work_s"], t["completed_work_s"] + labor)
            s["buildings"][t["target_id"]]["construction_progress"] = t["completed_work_s"] / t["required_work_s"]
        for eid in sorted(s["expeditions"]):
            e = s["expeditions"][eid]
            if e["status"] in TERMINAL_EXPEDITION or e["status"] == "stranded":
                continue
            speed = self.speed(e["crew_ids"])
            task = s["tasks"][e["task_id"]]
            if e["status"] == "outbound":
                e["route_progress_m"] = min(e["route_distance_m"], e["route_progress_m"] + speed * DT)
                if e["route_progress_m"] >= e["route_distance_m"]:
                    e["status"] = "working"
            elif e["status"] == "working":
                if not any(c in unmet for c in e["crew_ids"]):
                    e["work_completed_s"] = min(e["work_required_s"], e["work_completed_s"] + DT)
                task["completed_work_s"] = e["work_completed_s"]     # Task 01 mirror
                if e["work_completed_s"] >= e["work_required_s"]:
                    self.salvage(e)
                    site = s["sites"][e["site_id"]]
                    back = self.query_route(site["cell"], self.map["base_airlock_cell"])
                    if back["reachable"]:
                        e.update(status="returning", route_id=back["route_id"], route_waypoints_m=back["waypoints_m"],
                                 route_distance_m=back["distance_m"], route_progress_m=0.0)
                    else:
                        e["status"] = "stranded"
            elif e["status"] == "returning":
                e["route_progress_m"] = min(e["route_distance_m"], e["route_progress_m"] + speed * DT)
                if e["route_progress_m"] >= e["route_distance_m"]:
                    self.return_home(e)
                    continue
            pos = self.point_on_route(e) if e["status"] != "working" else self.center(s["sites"][e["site_id"]]["cell"])
            for cid in e["crew_ids"]:
                s["crew"][cid]["position_m"] = list(pos)
            self.update_margin(eid)

    def salvage(self, e):
        s = self.s
        site = s["sites"][e["site_id"]]
        cap = sum(self.cdefs[s["crew"][c]["definition_id"]]["carry_capacity_count"] for c in e["crew_ids"])
        debits, credits = {}, {}
        for rid in sorted(site["remaining_cargo"]):
            take = min(site["remaining_cargo"][rid], cap)
            if take <= 0:
                continue
            self.add_acct(f"site/{site['id']}/{rid}", -take)
            self.add_acct(f"cargo/{e['id']}/{rid}", take)
            debits[f"site/{site['id']}/{rid}"] = take
            credits[f"cargo/{e['id']}/{rid}"] = take
            cap -= take
        self.marker(f"crew_tasks:{e['id']}:salvage_collect:0", "salvage_collect", debits, credits)

    def return_home(self, e):
        s = self.s
        eid = e["id"]
        salvaged = f"crew_tasks:{eid}:salvage_collect:0" in s["committed_effects"]
        if salvaged:
            debits, credits = {}, {}
            for rid in sorted(e["cargo"]):
                q = self.acct(f"cargo/{eid}/{rid}")
                fit = min(q, self.headroom(rid))
                self.add_acct(f"cargo/{eid}/{rid}", -q)
                debits[f"cargo/{eid}/{rid}"] = q
                if fit > 0:
                    self.add_base(rid, fit)
                    credits[f"base/{rid}"] = fit
                if q - fit > 0:
                    self.add_acct(f"return_cache/{eid}/{rid}", q - fit)
                    credits[f"return_cache/{eid}/{rid}"] = q - fit
            self.marker(f"crew_tasks:{eid}:cargo_return:0", "cargo_return", debits, credits)
        debits, credits = {}, {}
        for cid in e["crew_ids"]:
            o = self.acct(f"suit/{eid}/{cid}/oxygen_kg")
            put = min(o, self.headroom("oxygen_kg"))
            self.add_base("oxygen_kg", put)
            self.flow("external/vent_loss/oxygen_kg", o - put)
            self.add_acct(f"suit/{eid}/{cid}/oxygen_kg", -o)
            bq = self.acct(f"suit/{eid}/{cid}/battery_kwh")
            acc = self.energy_credit(bq)
            self.flow("external/vent_loss/energy_kwh", bq - acc)
            self.add_acct(f"suit/{eid}/{cid}/battery_kwh", -bq)
            debits[f"suit/{eid}/{cid}/oxygen_kg"] = o
            debits[f"suit/{eid}/{cid}/battery_kwh"] = bq
            credits["base/oxygen_kg"] = credits.get("base/oxygen_kg", 0.0) + put
            credits["base/energy_kwh"] = credits.get("base/energy_kwh", 0.0) + acc
        self.marker(f"crew_tasks:{eid}:eva_return:0", "eva_return", debits, credits)
        e["status"] = "completed"
        e["return_margin_s"] = None
        task = s["tasks"][e["task_id"]]
        task["status"] = "completed" if salvaged else "cancelled"
        s["sites"][e["site_id"]]["reserved_by_expedition_id"] = None
        airlock = self.center(self.map["base_airlock_cell"])
        for cid in e["crew_ids"]:
            # Returned EVA crew switch to base immediately (contract section 8).
            s["crew"][cid].update(status="idle", location_kind="base", expedition_id=None, task_id=None,
                                  position_m=list(airlock))
        self.tick_event("progress", "eva_returned", [eid], {"crew_ids": e["crew_ids"], "salvage_collected": salvaged})
        self.tick_event("progress", "task_completed" if salvaged else "task_cancelled", [task["id"]], {})

    def drain_return_caches(self):
        s = self.s
        for eid in sorted(s["return_caches"]):
            for rid in sorted(s["return_caches"].get(eid, {})):
                q = self.acct(f"return_cache/{eid}/{rid}")
                fit = min(q, self.headroom(rid))
                if fit > 0:
                    # tick-scoped effect tick:{n}:return_cache:{eid}:{rid}; never persisted
                    self.add_acct(f"return_cache/{eid}/{rid}", -fit)
                    self.add_base(rid, fit)

    def phase_finalize(self, k, before):
        s = self.s
        for tid in sorted(s["tasks"]):
            t = s["tasks"][tid]
            if t["kind"] == "construct" and t["status"] == "active" and t["completed_work_s"] >= t["required_work_s"]:
                b = s["buildings"][t["target_id"]]
                self.marker(f"core:{tid}:commission", "commission", {}, {})
                b.update(lifecycle="commissioned", blocking_codes=[], operating_fraction=0.0)
                t["status"] = "completed"
                del s["prepaid_build_costs"][tid]
                self.tick_event("finalize", "building_commissioned", [b["id"]], {"task_id": tid})
                self.tick_event("finalize", "task_completed", [tid], {})
        self.drain_return_caches()
        s["tick_index"] += 1
        s["revision"] += 1
        for rid in self.registry:
            r = (self.base_amount(rid) - before[rid]) / DT
            s["rates"][rid] = 0.0 if abs(r) < RATE_ZERO else r
        self.compute_alerts(k)
        # Events: phase order first, then entity-ID array, type, effect ID; IDs allocated after sorting.
        for _, ids, typ, _, data in sorted(self.tick_events, key=lambda x: (x[0], x[1], x[2], x[3])):
            eid = self.alloc("event")
            self.outbox.append({"id": eid, "type": typ, "tick_index": k, "entity_ids": ids, "data": data})
        self.tick_events = []
        self.check_invariants()

    def forecast(self, rid):
        r = self.s["rates"][rid]
        return self.base_amount(rid) / -r if r < 0 else None

    def compute_alerts(self, k):
        s = self.s
        th = self.sci["alerts"]
        want = {}
        for bid in sorted(s["buildings"]):
            b = s["buildings"][bid]
            if b["power_requested_kw"] > 0 and b["power_served_kw"] < b["power_requested_kw"]:
                want[f"power_shortfall:{bid}"] = ("power_shortfall", "Equipment is not receiving full power.", "warning", [bid])
        cap = self.base_capacity("energy_kwh")
        if cap and self.base_amount("energy_kwh") < th["battery_low_fraction"] * cap:
            want["battery_low"] = ("battery_low", "Stored electrical energy is low.", "warning", [])
        if self.base_amount("co2_kg") >= th["co2_high_kg"]:
            want["co2_high"] = ("co2_high", "Cabin CO2 is above the alert level.", "critical", [])
        fo = self.forecast("oxygen_kg")
        if fo is not None and fo < th["low_oxygen_forecast_s"]:
            want["low_oxygen"] = ("low_oxygen", "Oxygen reserve forecast is low.", "critical", [])
        for rid in sorted(self.overflowed):
            want[f"storage_full:{rid}"] = ("storage_full", "Storage is full; overflow is being lost.", "warning", [])
        for eid in sorted(s["expeditions"]):
            e = s["expeditions"][eid]
            if e["status"] == "stranded":
                want[f"expedition_stranded:{eid}"] = ("expedition_stranded", "EVA team has no route home.", "critical", [eid])
            elif e["return_margin_s"] is not None and e["return_margin_s"] < th["expedition_low_margin_s"]:
                want[f"expedition_low_margin:{eid}"] = ("expedition_low_margin", "EVA return margin is low.", "warning", [eid])
        new = {}
        for aid in sorted(want):
            code, msg, sev, ents = want[aid]
            first = s["alerts"][aid]["first_tick"] if aid in s["alerts"] else k
            new[aid] = {"id": aid, "code": code, "message": msg, "severity": sev, "entity_ids": ents, "first_tick": first}
        s["alerts"] = new

    def check_invariants(self):
        for rid in self.registry:
            a = self.base_amount(rid)
            assert a >= -1e-12, (rid, a)
            cap = self.base_capacity(rid)
            assert cap is None or a <= cap + 1e-9, (rid, a)
            if self.registry[rid]["whole_valued"]:
                assert float(a).is_integer(), (rid, a)

    # ------------------------------------------------------------------ public calls
    def step(self):
        self._begin()
        changed = self.boundary()
        self.flush("boundary")
        if self.s["time_scale"] > 0:
            self.tick()
            self.flush("tick")
            changed = True
        self.state_changed = changed
        return self.flushes

    def advance(self, real):
        self._begin()
        changed = self.boundary()
        self.flush("boundary")
        s = self.s
        s["accumulator_s"] += real * s["time_scale"]
        n = 0
        while s["time_scale"] > 0 and s["accumulator_s"] >= DT and n < 120:
            if n > 0:
                changed = self.boundary() or changed
                self.flush("boundary")
                if s["time_scale"] == 0:
                    break
            self.tick()
            self.flush("tick")
            s["accumulator_s"] -= DT
            n += 1
            changed = True
        self.state_changed = changed
        return self.flushes

    def resource_records(self):
        out = {}
        for rid in sorted(self.registry):
            amt, rate = self.base_amount(rid), self.s["rates"][rid]
            out[rid] = {"id": rid, "unit": self.registry[rid]["unit"], "amount": amt,
                        "capacity": self.base_capacity(rid),
                        "reserved": 0 if self.registry[rid]["whole_valued"] else 0.0,
                        "net_rate_per_s": rate, "forecast_empty_s": (amt / -rate) if rate < 0 else None}
        return out

    def snapshot(self):
        s = self.s
        return copy.deepcopy({
            "contract_version": CONTRACT_VERSION, "snapshot_version": SNAPSHOT_VERSION,
            "campaign_id": s["campaign_id"], "revision": s["revision"],
            "clock": {"tick_index": s["tick_index"], "elapsed_s": float(s["tick_index"]), "time_scale": s["time_scale"]},
            "rng": {"seed": s["rng"]["seed"], "state": s["rng"]["state"]},
            "map": s["map"],
            "resources": self.resource_records(),
            "power": dict(s["power_summary"], battery_stored_kwh=self.base_amount("energy_kwh"),
                          battery_capacity_kwh=self.base_capacity("energy_kwh")),
            "buildings": dict(sorted(s["buildings"].items())),
            "crew": dict(sorted(s["crew"].items())),
            "tasks": dict(sorted(s["tasks"].items())),
            "expeditions": dict(sorted(s["expeditions"].items())),
            "sites": dict(sorted(s["sites"].items())),
            "technology": s["technology"],
            "active_events": s["active_events"],
            "alerts": [s["alerts"][a] for a in sorted(s["alerts"])],
        })

    # ------------------------------------------------------------------ persistence
    def export_save(self):
        s = copy.deepcopy(self.s)
        core = {
            "clock": {"tick_index": s["tick_index"], "time_scale": s["time_scale"], "accumulator_s": s["accumulator_s"]},
            "rng": s["rng"], "map": s["map"], "id_counters": s["id_counters"],
            "next_receive_sequence": s["next_receive_sequence"], "revision": s["revision"],
            "command_journal": s["command_journal"], "pending_command_ids": s["pending_command_ids"],
            "committed_effects": s["committed_effects"],
            "power_summary": s["power_summary"], "alerts": s["alerts"],
            "resources": self.resource_records(),
            "buildings": s["buildings"], "active_events": s["active_events"], "sites": s["sites"],
            "technology": s["technology"], "per_battery_energy": s["per_battery_energy"],
            "prepaid_build_costs": s["prepaid_build_costs"], "crop_cycles": s["crop_cycles"],
            "scheduled_events": s["scheduled_events"],
        }
        return copy.deepcopy({
            "format": "mars-outpost-save", "save_version": SAVE_VERSION, "contract_version": CONTRACT_VERSION,
            "campaign_id": s["campaign_id"], "definition_manifest": self.cfg["definition_manifest"],
            "core": core,
            "subsystems": {"crew_tasks": {"schema_version": CREW_TASKS_SCHEMA, "state": {
                "crew": s["crew"], "tasks": s["tasks"], "expeditions": s["expeditions"],
                "return_caches": s["return_caches"], "completion_markers": s["completion_markers"],
                "private_counters": s["private_counters"]}}},
        })

    def import_save(self, record):
        """Validate into a candidate; replace state only if every check passes."""
        def bad(code, reason):
            return {"ok": False, "code": code, "reason": reason}
        rec = json.loads(json.dumps(record))
        if rec.get("format") != "mars-outpost-save":
            return bad("invalid_save", "not a Mars Outpost save")
        if rec.get("save_version") != SAVE_VERSION or rec.get("contract_version") != CONTRACT_VERSION:
            return bad("incompatible_save", "unsupported save_version or contract_version")
        if rec.get("definition_manifest") != self.cfg["definition_manifest"]:
            return bad("definition_mismatch", "definition manifest differs from the loaded content")
        sub = rec["subsystems"]["crew_tasks"]
        if sub.get("schema_version") != CREW_TASKS_SCHEMA:
            return bad("incompatible_save", "unsupported crew_tasks schema_version")
        core, st = rec["core"], sub["state"]
        cand = {
            "campaign_id": rec["campaign_id"], "tick_index": int(core["clock"]["tick_index"]),
            "time_scale": int(core["clock"]["time_scale"]), "accumulator_s": core["clock"]["accumulator_s"],
            "revision": int(core["revision"]), "map": core["map"], "rng": core["rng"],
            "id_counters": {k: int(v) for k, v in core["id_counters"].items()},
            "next_receive_sequence": int(core["next_receive_sequence"]),
            "command_journal": core["command_journal"], "pending_command_ids": core["pending_command_ids"],
            "committed_effects": core["committed_effects"],
            "rates": {rid: r["net_rate_per_s"] for rid, r in core["resources"].items()},
            "amounts": {rid: r["amount"] for rid, r in core["resources"].items() if rid != "energy_kwh"},
            "buildings": core["buildings"], "active_events": core["active_events"], "sites": core["sites"],
            "technology": core["technology"], "per_battery_energy": core["per_battery_energy"],
            "prepaid_build_costs": core["prepaid_build_costs"], "crop_cycles": core["crop_cycles"],
            "scheduled_events": core["scheduled_events"], "power_summary": core["power_summary"],
            "alerts": core["alerts"],
            "crew": st["crew"], "tasks": st["tasks"], "expeditions": st["expeditions"],
            "return_caches": st["return_caches"], "completion_markers": st["completion_markers"],
            "private_counters": st["private_counters"],
        }
        old = self.s
        self.s = cand
        try:
            if set(core["resources"]) != set(self.registry):
                raise ValueError("resource set differs from the registry")
            for rid, r in core["resources"].items():
                if r["unit"] != self.registry[rid]["unit"] or r["capacity"] != self.base_capacity(rid):
                    raise ValueError(f"{rid}: unit/capacity disagree with definitions")
            if abs(core["resources"]["energy_kwh"]["amount"] - self.base_amount("energy_kwh")) > 1e-9:
                raise ValueError("energy_kwh aggregate does not equal per-battery total")
            for tid, t in cand["tasks"].items():
                if t["kind"] == "construct" and t["target_id"] not in cand["buildings"]:
                    raise ValueError(f"{tid} references unknown building {t['target_id']}")
            self.check_invariants()
        except (ValueError, AssertionError, KeyError) as exc:
            self.s = old
            return bad("invalid_save", str(exc))
        self.state_changed = True
        return {"ok": True, "code": "ok", "reason": ""}
