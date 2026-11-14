extends SceneTree
func _initialize() -> void:
	for type in ["Skeleton3D","AnimationTree","SkeletonModifier3D"]:
		var props: Array[String] = []
		for p in ClassDB.class_get_property_list(type):
			if "callback" in p.name or "process" in p.name:props.append(p.name)
		print(type," CALLBACKS ",props)
	print("SKELETON ENUMS ",ClassDB.class_get_enum_constants("Skeleton3D","ModifierCallbackModeProcess"))
	quit()
