class_name ClockProvider
extends RefCounted

func wall_utc() -> int:
	return int(Time.get_unix_time_from_system())

func monotonic_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
