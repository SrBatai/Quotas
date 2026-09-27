extends Node3D
## Stand-in for the local Player in the city bench: the properties CameraRig, CityCut and Silhouettes read.

var is_local: bool = true
var move_dir: Vector3 = Vector3.ZERO
var in_house: bool = false
var dead: bool = false
var outfit: int = 0
var aim_point: Vector3 = Vector3.ZERO
