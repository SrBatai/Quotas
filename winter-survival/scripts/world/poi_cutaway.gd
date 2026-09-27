class_name PoiCutaway
extends BuildingCutaway
## Client cutaway of the M3 forest POIs (cabin_small, lookout_tower): the shared cut-group logic of
## BuildingCutaway (scripts/world/city/building_cutaway.gd) in its legacy mode — hidden groups get
## `visible = false`, exactly as in M3. City buildings use the same logic in shadow-preserving mode (CityBuilding).
## Provisional until M6a's CutawayManager.


## Returns null when the model has no cut groups.
static func attach(host: Node3D, model: Node3D) -> PoiCutaway:
	if not has_cut_groups(model):
		return null
	var cut := PoiCutaway.new()
	cut.name = "Cutaway"
	cut.hide_mode = HideMode.VISIBLE
	host.add_child(cut)
	cut.setup(model)
	return cut
