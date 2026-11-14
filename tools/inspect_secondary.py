import bpy, os, json
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
report={}
for key in ('lily','rin','aki'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,'assets/characters',key+'.glb'))
    rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    item={'head':list(rig.data.bones['Head'].head_local),'hips':list(rig.data.bones['Hips'].head_local),'hair':[]}
    for obj in bpy.data.objects:
        if obj.type!='MESH':continue
        ids={v for p in obj.data.polygons if p.material_index<len(obj.data.materials) and obj.data.materials[p.material_index] and obj.data.materials[p.material_index].name.startswith('HunterHair_') for v in p.vertices}
        if not ids:continue
        coordinates=[obj.data.vertices[v].co for v in ids]
        item['hair'].append({'mesh':obj.name,'vertices':len(ids),'min':[min(v[i] for v in coordinates) for i in range(3)],'max':[max(v[i] for v in coordinates) for i in range(3)]})
    item['hair_bones']=[{'name':b.name,'parent':b.parent.name if b.parent else '', 'head':list(b.head_local),'tail':list(b.tail_local)} for b in rig.data.bones if 'hair' in b.name.lower() or 'pon' in b.name.lower()]
    report[key]=item
with open(os.path.join(ROOT,'.tools/secondary_inspection.json'),'w') as f:json.dump(report,f,indent=2)
