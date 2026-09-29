class_name PoiCutaway
extends BuildingCutaway
## Client cutaway of the M3 forest POIs (cabin_small, lookout_tower): the shared cut-group logic of
## BuildingCutaway (scripts/world/city/building_cutaway.gd) in its legacy mode — hidden groups get
## `visible = false`, exactly as in M3. City buildings use the same logic in shadow-preserving mode (CityBuilding).
## M6a: the world no longer uses it — world_chunk attaches the POIs through CutawayManager.attach (managed by the
## CutawayManager, shadow-preserving mode). Kept for the W0 render check of the legacy `visible = false` mode.


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
