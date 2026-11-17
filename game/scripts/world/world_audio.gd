class_name WorldAudio
extends Node
## 环境音频（docs/technical-design.md §4.1）。
##
## 不同区域拥有独立的环境声层；空间音频同时承担方向引导功能
## （docs/first-scene-design.md §9.2）。

## AudioStreamPlayer 节点名 → 区域 ID。
const ZONE_PLAYERS := {
	"CampAudio": &"camp",
	"ForestAudio": &"forest",
}

var _players: Dictionary = {}


func _ready() -> void:
	for node_name in ZONE_PLAYERS:
		var player := get_node_or_null(node_name) as AudioStreamPlayer
		if player != null:
			_players[ZONE_PLAYERS[node_name]] = player
	GameLog.info("WorldAudio 就绪", {"zones": _players.size()})


## 播放某个区域的环境声层，其余静音。
func activate_zone(zone_id: StringName) -> void:
	for key in _players:
		var player: AudioStreamPlayer = _players[key]
		if key == zone_id:
			if not player.playing:
				player.play()
		else:
			player.stop()


func set_zone_volume(zone_id: StringName, volume_db: float) -> void:
	var player: AudioStreamPlayer = _players.get(zone_id, null)
	if player != null:
		player.volume_db = volume_db
