extends RefCounted
## Pure campaign-calendar queries. A campaign abstraction, not a Mars sol or launch-window claim.
## `calendar` is the committed campaign.calendar record; ticks are whole simulated seconds.
const ORDER_LEAD_DAYS := 30

static func day_index(calendar: Dictionary, tick: int) -> int:
	return tick / int(calendar.day_seconds)

static func shipment_period_s(calendar: Dictionary) -> int:
	return int(calendar.shipment_days) * int(calendar.day_seconds)

static func order_lead_s(calendar: Dictionary) -> int:
	return ORDER_LEAD_DAYS * int(calendar.day_seconds)

static func next_day_start(calendar: Dictionary, tick: int) -> int:
	return (day_index(calendar, tick) + 1) * int(calendar.day_seconds)

static func next_shipment_cycle(calendar: Dictionary, tick: int) -> int:
	## First cycle whose arrival is strictly after `tick`. Cycle 1 arrives on day 180.
	return tick / shipment_period_s(calendar) + 1

static func shipment_arrival(calendar: Dictionary, cycle: int) -> int:
	return cycle * shipment_period_s(calendar)

static func order_deadline(calendar: Dictionary, cycle: int) -> int:
	return shipment_arrival(calendar, cycle) - order_lead_s(calendar)

static func next_deadline_cycle(calendar: Dictionary, tick: int) -> int:
	## First cycle whose ordering deadline is strictly after `tick`.
	var cycle := next_shipment_cycle(calendar, tick)
	if order_deadline(calendar, cycle) <= tick: cycle += 1
	return cycle

static func describe(calendar: Dictionary, tick: int) -> Dictionary:
	var day_s := int(calendar.day_seconds)
	var index := day_index(calendar, tick)
	var second := tick - index * day_s
	var cycle := next_shipment_cycle(calendar, tick)
	var deadline_cycle := next_deadline_cycle(calendar, tick)
	return {"elapsed_s": tick, "day_index": index, "mission_day": index + 1,
		"month": index / int(calendar.month_days) + 1, "day_of_month": index % int(calendar.month_days) + 1,
		"second_of_day": second, "hour": second / 3600, "minute": (second % 3600) / 60,
		"shipments_arrived": cycle - 1, "next_shipment_cycle": cycle,
		"next_shipment_s": shipment_arrival(calendar, cycle),
		"seconds_until_shipment": shipment_arrival(calendar, cycle) - tick,
		"next_order_deadline_cycle": deadline_cycle,
		"next_order_deadline_s": order_deadline(calendar, deadline_cycle),
		"campaign_complete": index >= int(calendar.campaign_days)}
